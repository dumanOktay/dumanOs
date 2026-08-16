#!/bin/bash
# ==============================================================================
# dumanOS Ultra-Fast ARM64 ISO Generator (Complete UEFI Bootloader Support)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build-arm64"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "    dumanOS ARM64 Hızlı ISO Derleme Başlatılıyor (UEFI)   "
echo "=========================================================="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

KEYRING_ARG=""
if [ -f "/usr/share/keyrings/debian-archive-keyring.gpg" ]; then
    KEYRING_ARG="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
fi

# 1. Base system creation with mmdebstrap
echo "[1/6] mmdebstrap ile temel Debian 12 ARM64 sistemi kuruluyor..."
mmdebstrap \
    --arch=arm64 \
    --variant=minbase \
    $KEYRING_ARG \
    --components="main,contrib,non-free,non-free-firmware" \
    --include="ca-certificates,curl,gnupg,eatmydata,linux-image-arm64,grub-efi-arm64,grub-efi-arm64-bin,grub-common,mtools,dosfstools,live-boot,live-config" \
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

# Copy qemu emulator
cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true

# Mount virtual filesystems
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
apt-get clean
rm -rf /tmp/packages.list /var/lib/apt/lists/* /var/cache/apt/* /usr/share/doc/* /usr/share/man/*
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

# Copy Kernel & Initrd
echo "[*] Çekirdek ve Initrd kopyalanıyor..."
mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/grub" "$ISO_DIR/EFI/BOOT"
KERNEL_IMAGE=$(ls "$ROOTFS/boot" | grep -E 'vmlinuz|vmlinux' | head -n 1)
INITRD_IMAGE=$(ls "$ROOTFS/boot" | grep initrd | head -n 1)
cp "$ROOTFS/boot/$KERNEL_IMAGE" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/$INITRD_IMAGE" "$ISO_DIR/live/initrd"

# 6. Generate Standalone UEFI GRUB Binary (BOOTAA64.EFI)
echo "[*] Standalone ARM64 UEFI Bootloader (BOOTAA64.EFI) oluşturuluyor..."
cat << 'EOF' > "$BUILD_DIR/embedded_grub.cfg"
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

# Copy grub.cfg to ISO boot dir as well
cp "$BUILD_DIR/embedded_grub.cfg" "$ISO_DIR/boot/grub/grub.cfg"

# Create BOOTAA64.EFI standalone inside chroot or host
chroot "$ROOTFS" grub-mkstandalone \
    --format=arm64-efi \
    --output=/tmp/BOOTAA64.EFI \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/boot/grub/grub.cfg"

cp "$ROOTFS/tmp/BOOTAA64.EFI" "$ISO_DIR/EFI/BOOT/BOOTAA64.EFI"

# Create embedded FAT16 EFI Boot Image (efiboot.img)
echo "[*] EFI Boot İmajı (efiboot.img) hazırlanıyor..."
dd if=/dev/zero of="$BUILD_DIR/efiboot.img" bs=1M count=20
mkfs.vfat "$BUILD_DIR/efiboot.img"
mmd -i "$BUILD_DIR/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$BUILD_DIR/efiboot.img" "$ISO_DIR/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
cp "$BUILD_DIR/efiboot.img" "$ISO_DIR/boot/grub/efiboot.img"

# Remove qemu static binary
rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"

# Cleanly UNMOUNT before squashfs
echo "[*] Sanal dosya sistemleri ayrılıyor (Unmount)..."
umount -lf "$ROOTFS/dev" 2>/dev/null || true
umount -lf "$ROOTFS/run" 2>/dev/null || true
umount -lf "$ROOTFS/proc" 2>/dev/null || true
umount -lf "$ROOTFS/sys" 2>/dev/null || true
rm -rf "$ROOTFS/proc/"* "$ROOTFS/sys/"* "$ROOTFS/dev/"* "$ROOTFS/run/"*

# SquashFS compression
echo "[*] SquashFS sıkıştırması başlatılıyor..."
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp gzip \
    -processors $(nproc) \
    -e proc sys dev run tmp \
    -noappend

# Build Standard UEFI Hybrid ISO Image with xorriso
echo "[*] Bootable ARM64 UEFI ISO oluşturuluyor..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "DUMANOS_ARM64" \
    -eltorito-alt-boot \
    -e boot/grub/efiboot.img \
    -no-emul-boot \
    -append_partition 2 0xef "$BUILD_DIR/efiboot.img" \
    -output "$OUTPUT_DIR/dumanOS-arm64.iso" \
    "$ISO_DIR"

echo "=========================================================="
echo " [✓] dumanOS ARM64 ISO başarıyla oluşturuldu:"
echo "     $OUTPUT_DIR/dumanOS-arm64.iso"
echo "=========================================================="
