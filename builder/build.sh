#!/bin/bash
# ==============================================================================
# dumanOS Ultra-Fast ARM64 ISO Generator (Optimized SquashFS & Clean Unmount)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build-arm64"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "    dumanOS ARM64 Hızlı ISO Derleme Başlatılıyor          "
echo "=========================================================="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

# Determine keyring path
KEYRING_ARG=""
if [ -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
    KEYRING_ARG="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
fi

# 1. Base system creation with mmdebstrap (~60s)
echo "[1/6] mmdebstrap ile temel Debian 12 ARM64 sistemi kuruluyor..."
mmdebstrap \
    --arch=arm64 \
    --variant=minbase \
    $KEYRING_ARG \
    --components="main,contrib,non-free,non-free-firmware" \
    --include="ca-certificates,curl,gnupg,eatmydata,linux-image-arm64,grub-efi-arm64-bin,live-boot,live-config" \
    bookworm \
    "$ROOTFS" \
    http://deb.debian.org/debian/

# 2. Configure Repositories & Fast APT Options
echo "[2/6] Paket depoları ve hızlandırıcılar ayarlanıyor..."
mkdir -p "$ROOTFS/etc/apt/apt.conf.d"
cat << 'EOF' > "$ROOTFS/etc/apt/sources.list"
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

cat << 'EOF' > "$ROOTFS/etc/apt/apt.conf.d/99speed"
APT::Install-Recommends "0";
APT::Install-Suggests "0";
Acquire::Languages "none";
DPkg::Options {
   "--force-confdef";
   "--force-confold";
};
EOF

# Copy qemu emulator so chroot works seamlessly on x86 runner
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true

# Mount virtual filesystems for chroot
mount --bind /dev "$ROOTFS/dev"
mount --bind /run "$ROOTFS/run"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"

# 3. Chroot & Install Custom Packages (KDE Wayland, PipeWire, Mesa, Waydroid)
echo "[3/6] Masaüstü ve sistem bileşenleri kuruluyor..."
cp "$SCRIPT_DIR/packages.list" "$ROOTFS/tmp/packages.list"

chroot "$ROOTFS" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
apt-get update
eatmydata apt-get install -y --no-install-recommends \$(grep -v '^#' /tmp/packages.list | tr '\n' ' ')

# Clean caches to keep ISO small and fast
apt-get clean
rm -rf /tmp/packages.list /var/lib/apt/lists/* /var/cache/apt/* /usr/share/doc/* /usr/share/man/*
"

# Remove qemu static binary from target rootfs
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"

# 4. Copy Overlays (Custom scripts, services, configs)
echo "[4/6] dumanOS özel ayarları ve scriptleri kopyalanıyor..."
cp -r "$PROJECT_ROOT/overlay/"* "$ROOTFS/"
chmod +x "$ROOTFS/usr/local/bin/"* 2>/dev/null || true

# 5. User Creation & Hostname
echo "[5/6] Canlı kullanıcı (duman) ve servisler yapılandırılıyor..."
chroot "$ROOTFS" /bin/bash -c "
echo 'dumanos' > /etc/hostname
echo '127.0.0.1 localhost dumanos' > /etc/hosts

useradd -m -s /bin/bash -G sudo,audio,video,render,plugdev duman || true
echo 'duman:duman' | chpasswd
echo 'root:duman' | chpasswd
echo 'duman ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

systemctl enable sddm.service || true
systemctl enable NetworkManager.service || true
systemctl enable dumanos-firstboot.service || true
"

# Copy Kernel & Initrd BEFORE unmounting/squashing
echo "[*] Çekirdek ve Initrd ISO dizinine kopyalanıyor..."
mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/grub"
KERNEL_IMAGE=$(ls "$ROOTFS/boot" | grep -E 'vmlinuz|vmlinux' | head -n 1)
INITRD_IMAGE=$(ls "$ROOTFS/boot" | grep initrd | head -n 1)
cp "$ROOTFS/boot/$KERNEL_IMAGE" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/$INITRD_IMAGE" "$ISO_DIR/live/initrd"

# CRITICAL: Cleanly UNMOUNT all virtual filesystems BEFORE SquashFS!
# If /proc and /sys remain mounted, mksquashfs tries to compress infinite dynamic kernel structures!
echo "[*] Sanal dosya sistemleri ayrılıyor (Unmount)..."
umount -lf "$ROOTFS/dev" 2>/dev/null || true
umount -lf "$ROOTFS/run" 2>/dev/null || true
umount -lf "$ROOTFS/proc" 2>/dev/null || true
umount -lf "$ROOTFS/sys" 2>/dev/null || true

# Clean up empty mount points inside rootfs
rm -rf "$ROOTFS/proc/"* "$ROOTFS/sys/"* "$ROOTFS/dev/"* "$ROOTFS/run/"*

# 6. Ultra-Fast Parallel SquashFS (Takes ~30-45 seconds now!)
echo "[6/6] Yüksek hızlı SquashFS sıkıştırması başlatılıyor..."
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp gzip \
    -processors $(nproc) \
    -e proc sys dev run tmp \
    -noappend

# GRUB EFI Configuration
cat << 'EOF' > "$ISO_DIR/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "dumanOS Live ARM64 (KDE Wayland + Android Engine)" {
    linux /live/vmlinuz boot=live quiet splash components username=duman hostname=dumanos
    initrd /live/initrd
}

menuentry "dumanOS (Güvenli Mod - Nomodeset)" {
    linux /live/vmlinuz boot=live nomodeset components username=duman hostname=dumanos
    initrd /live/initrd
}
EOF

# Build EFI Bootable ISO with xorriso
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "DUMANOS_ARM64" \
    -output "$OUTPUT_DIR/dumanOS-arm64.iso" \
    "$ISO_DIR"

echo "=========================================================="
echo " [✓] dumanOS ARM64 ISO başarıyla oluşturuldu:"
echo "     $OUTPUT_DIR/dumanOS-arm64.iso"
echo "=========================================================="
