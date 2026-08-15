#!/bin/bash
# ==============================================================================
# dumanOS ISO Image Generator (Debian 12 Bookworm Minimal + Wayland + Android)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "          dumanOS ISO Derleme Süreci Başlatılıyor         "
echo "=========================================================="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

# 1. Debootstrap Debian 12 Bookworm
echo "[1/7] Debootstrap ile temel Debian 12 sistemi kuruluyor..."
debootstrap --arch=amd64 --variant=minbase bookworm "$ROOTFS" http://deb.debian.org/debian/

# 2. Configure Repositories & Keyrings
echo "[2/7] Paket depoları ve Waydroid kaynakları yapılandırılıyor..."
cat << 'EOF' > "$ROOTFS/etc/apt/sources.list"
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

# Mount necessary virtual filesystems for chroot
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

# 3. Chroot & Install Packages
echo "[3/7] Temel paketler, Çekirdek, Wayland ve KDE kuruluyor..."
cp "$SCRIPT_DIR/packages.list" "$ROOTFS/tmp/packages.list"

chroot "$ROOTFS" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \$(grep -v '^#' /tmp/packages.list | tr '\n' ' ')
apt-get install -y live-boot live-config
apt-get clean
rm -rf /tmp/packages.list /var/lib/apt/lists/*
"

# 4. Copy Overlays (Custom scripts, services, configs)
echo "[4/7] dumanOS özel ayarları ve scriptleri kopyalanıyor..."
cp -r "$PROJECT_ROOT/overlay/"* "$ROOTFS/"

# Make scripts executable
chmod +x "$ROOTFS/usr/local/bin/"* 2>/dev/null || true

# 5. User Creation & Hostname
echo "[5/7] Kullanıcı ve sistem ayarları yapılıyor..."
chroot "$ROOTFS" /bin/bash -c "
echo 'dumanos' > /etc/hostname
echo '127.0.0.1 localhost dumanos' > /etc/hosts

# Create user 'duman'
useradd -m -s /bin/bash -G sudo,audio,video,render,plugdev duman || true
echo 'duman:duman' | chpasswd
echo 'root:duman' | chpasswd

# Passwordless sudo for live environment
echo 'duman ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Enable services
systemctl enable sddm.service || true
systemctl enable NetworkManager.service || true
systemctl enable dumanos-firstboot.service || true
"

# 6. Compress RootFS (SquashFS)
echo "[6/7] RootFS SquashFS ile sıkıştırılıyor..."
mkdir -p "$ISO_DIR/live"
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp zstd -Xcompression-level 15 -noappend

# Copy Kernel and Initrd to ISO
KERNEL_VERSION=$(ls "$ROOTFS/boot" | grep vmlinuz | head -n 1 | sed 's/vmlinuz-//')
cp "$ROOTFS/boot/vmlinuz-$KERNEL_VERSION" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/initrd.img-$KERNEL_VERSION" "$ISO_DIR/live/initrd"

# 7. Create Bootloader (GRUB EFI + BIOS Hybrid)
echo "[7/7] EFI ve BIOS Bootloader yapılandırılıyor ve ISO oluşturuluyor..."
mkdir -p "$ISO_DIR/boot/grub"
cat << 'EOF' > "$ISO_DIR/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "dumanOS Live x86_64 (KDE Wayland + Android Engine)" {
    linux /live/vmlinuz boot=live quiet splash components username=duman hostname=dumanos
    initrd /live/initrd
}

menuentry "dumanOS (Güvenli Grafik Modu - Nomodeset)" {
    linux /live/vmlinuz boot=live nomodeset components username=duman hostname=dumanos
    initrd /live/initrd
}
EOF

# Generate Hybrid ISO Image using xorriso
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "DUMANOS_LIVE" \
    -eltorito-boot boot/grub/grub.cfg \
    -eltorito-catalog boot/grub/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -output "$OUTPUT_DIR/dumanOS-x86_64.iso" \
    "$ISO_DIR"

echo "=========================================================="
echo " [✓] TEBRİKLER! dumanOS ISO başarıyla oluşturuldu:"
echo "     $OUTPUT_DIR/dumanOS-x86_64.iso"
echo "=========================================================="
