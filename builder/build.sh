#!/bin/bash
# ==============================================================================
# dumanOS Ultra-Fast ARM64 ISO Generator (Official Base RootFS Pipeline)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build-arm64"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "    dumanOS ARM64 Hızlı ISO Derleme Başlatılıyor (RootFS)  "
echo "=========================================================="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

# 1. Download & Extract Official Debian 12 ARM64 Base (Takes ~10 seconds)
echo "[1/6] Resmi Debian 12 ARM64 hazır tabanı indiriliyor (Hızlı Pipeline)..."
ROOTFS_TAR="$BUILD_DIR/debian-12-base-arm64.tar.xz"
if [ ! -f "$ROOTFS_TAR" ]; then
    curl -L "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-arm64.tar.xz" -o "$ROOTFS_TAR"
fi

echo "[*] Taban sistem açılıyor..."
tar -xf "$ROOTFS_TAR" -C "$ROOTFS"

# 2. Configure Repositories & Fast APT Options
echo "[2/6] Paket depoları ve hızlandırıcılar ayarlanıyor..."
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

# Mount virtual filesystems
mount --bind /dev "$ROOTFS/dev"
mount --bind /run "$ROOTFS/run"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sysfs "$ROOTFS/sys"

cleanup() {
    echo "[*] Temizleme işlemi yapılıyor..."
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
    umount -lf "$ROOTFS/run" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
}
trap cleanup EXIT

# 3. Chroot & Install Custom Packages (KDE Wayland, PipeWire, Waydroid, Live-Boot)
echo "[3/6] Masaüstü ve sistem bileşenleri kuruluyor..."
cp "$SCRIPT_DIR/packages.list" "$ROOTFS/tmp/packages.list"

chroot "$ROOTFS" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
apt-get update
apt-get install -y --no-install-recommends \
    linux-image-arm64 \
    grub-efi-arm64-bin \
    live-boot \
    live-config \
    \$(grep -v '^#' /tmp/packages.list | tr '\n' ' ')

# Remove cloud-init if present to boot instantly as desktop
apt-get purge -y cloud-init 2>/dev/null || true

# Clean caches to save space
apt-get clean
rm -rf /tmp/packages.list /var/lib/apt/lists/* /var/cache/apt/*
"

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

# 6. Compress RootFS (SquashFS) & Build Bootable EFI ISO
echo "[6/6] SquashFS sıkıştırması ve ISO oluşturuluyor..."
mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/grub"
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp zstd -Xcompression-level 9 -processors $(nproc) -noappend

# Copy Kernel & Initrd
KERNEL_IMAGE=$(ls "$ROOTFS/boot" | grep -E 'vmlinuz|vmlinux' | head -n 1)
INITRD_IMAGE=$(ls "$ROOTFS/boot" | grep initrd | head -n 1)
cp "$ROOTFS/boot/$KERNEL_IMAGE" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/$INITRD_IMAGE" "$ISO_DIR/live/initrd"

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
