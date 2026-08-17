#!/bin/bash
# ==============================================================================
# dumanOS Ultra-Fast ARM64 ISO Generator (Bulletproof Direct Auto-Desktop Engine)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build-arm64"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "    dumanOS ARM64 Hızlı ISO Derleme Başlatılıyor (Direct) "
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
    --include="ca-certificates,curl,gnupg,eatmydata,linux-image-arm64,initramfs-tools,live-boot,live-boot-initramfs-tools,live-config,live-config-systemd,grub-efi-arm64,grub-efi-arm64-bin,grub-common,mtools,dosfstools,busybox" \
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

# 3. Force MODULES=most in initramfs
mkdir -p "$ROOTFS/etc/initramfs-tools"
sed -i 's/MODULES=dep/MODULES=most/g' "$ROOTFS/etc/initramfs-tools/initramfs.conf" 2>/dev/null || true
echo "MODULES=most" >> "$ROOTFS/etc/initramfs-tools/initramfs.conf"
echo "BUSYBOX=y" >> "$ROOTFS/etc/initramfs-tools/initramfs.conf"

cat << 'EOF' >> "$ROOTFS/etc/initramfs-tools/modules"
squashfs
overlay
isofs
loop
cdrom
sr_mod
sd_mod
virtio_scsi
virtio_blk
virtio_pci
virtio_gpu
virtio_ring
usb_storage
uas
EOF

# Install custom packages
echo "[3/6] Masaüstü ve sistem bileşenleri kuruluyor..."
cp "$SCRIPT_DIR/packages.list" "$ROOTFS/tmp/packages.list"

chroot "$ROOTFS" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
apt-get update
eatmydata apt-get install -y --no-install-recommends \$(grep -v '^#' /tmp/packages.list | tr '\n' ' ')

# Generate fresh universal live-boot initramfs
update-initramfs -c -k all

apt-get clean
rm -rf /tmp/packages.list /var/lib/apt/lists/* /var/cache/apt/* /usr/share/doc/* /usr/share/man/*
"

# 4. Copy Overlays (Custom scripts, services, configs)
echo "[4/6] dumanOS özel ayarları ve scriptleri kopyalanıyor..."
cp -r "$PROJECT_ROOT/overlay/"* "$ROOTFS/"
chmod +x "$ROOTFS/usr/local/bin/"* 2>/dev/null || true

# 5. User Creation & Hostname with Direct Auto-Login
echo "[5/6] Canlı kullanıcı (duman) ve otomatik masaüstü yapılandırılıyor..."
chroot "$ROOTFS" /bin/bash -c "
echo 'dumanos' > /etc/hostname
echo '127.0.0.1 localhost dumanos' > /etc/hosts

groupadd -r autologin 2>/dev/null || true
useradd -m -s /bin/bash -G sudo,audio,video,render,plugdev,autologin duman || true
usermod -aG autologin duman || true
echo 'duman:duman' | chpasswd
echo 'root:duman' | chpasswd
echo 'duman ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Ensure user directory ownership
cp /etc/skel/.bash_profile /home/duman/.bash_profile 2>/dev/null || true
chown -R duman:duman /home/duman

systemctl set-default graphical.target
systemctl enable lightdm.service || true
systemctl enable NetworkManager.service || true
systemctl enable dumanos-firstboot.service || true
"

# Copy Kernel & Initrd
echo "[*] Çekirdek ve Initrd kopyalanıyor..."
mkdir -p "$ISO_DIR/live" "$ISO_DIR/boot/grub/arm64-efi" "$ISO_DIR/EFI/BOOT"
KERNEL_IMAGE=$(ls "$ROOTFS/boot" | grep -E 'vmlinuz|vmlinux' | head -n 1)
INITRD_IMAGE=$(ls "$ROOTFS/boot" | grep initrd | head -n 1)
cp "$ROOTFS/boot/$KERNEL_IMAGE" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/$INITRD_IMAGE" "$ISO_DIR/live/initrd"

# Copy ALL GRUB EFI modules to ISO boot dir
cp -r "$ROOTFS/usr/lib/grub/arm64-efi/"* "$ISO_DIR/boot/grub/arm64-efi/" 2>/dev/null || true

# Create universal grub.cfg
cat << 'EOF' > "$BUILD_DIR/grub.cfg"
set default=0
set timeout=2

search --file --set=root /live/vmlinuz

menuentry "dumanOS Live ARM64 (KDE Plasma Desktop)" {
    linux /live/vmlinuz boot=live components username=duman autologin quiet splash
    initrd /live/initrd
}

menuentry "dumanOS (Güvenli Mod - Nomodeset)" {
    linux /live/vmlinuz boot=live components username=duman autologin nomodeset
    initrd /live/initrd
}
EOF

# Place grub.cfg in all standard locations
cp "$BUILD_DIR/grub.cfg" "$ISO_DIR/boot/grub/grub.cfg"
cp "$BUILD_DIR/grub.cfg" "$ISO_DIR/EFI/BOOT/grub.cfg"

# Create standalone ARM64 EFI binary
cp "$BUILD_DIR/grub.cfg" "$ROOTFS/tmp/grub.cfg"
chroot "$ROOTFS" grub-mkstandalone \
    --format=arm64-efi \
    --output=/tmp/BOOTAA64.EFI \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=/tmp/grub.cfg"

cp "$ROOTFS/tmp/BOOTAA64.EFI" "$ISO_DIR/EFI/BOOT/BOOTAA64.EFI"

# Create embedded FAT16 EFI Boot Image (efiboot.img)
echo "[*] EFI Boot İmajı (efiboot.img) hazırlanıyor..."
dd if=/dev/zero of="$BUILD_DIR/efiboot.img" bs=1M count=30
mkfs.vfat "$BUILD_DIR/efiboot.img"
mmd -i "$BUILD_DIR/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$BUILD_DIR/efiboot.img" "$ISO_DIR/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "$BUILD_DIR/efiboot.img" "$BUILD_DIR/grub.cfg" ::/EFI/BOOT/grub.cfg
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
