#!/bin/bash
# ==============================================================================
# dumanOS Multi-Arch ISO Image Generator (Supports arm64 & amd64)
# ==============================================================================

set -e

ARCH="${ARCH:-arm64}" # Default to arm64 (Apple Silicon / Raspberry Pi / ARM)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="/tmp/dumanos-build-$ARCH"
ROOTFS="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
OUTPUT_DIR="$PROJECT_ROOT/output"

echo "=========================================================="
echo "      dumanOS ISO Derleme Süreci Başlatılıyor ($ARCH)     "
echo "=========================================================="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -rf "$ROOTFS" "$ISO_DIR"
mkdir -p "$ROOTFS" "$ISO_DIR"

# 1. Debootstrap Debian 12 Bookworm for selected architecture
echo "[1/7] Debootstrap ile temel Debian 12 ($ARCH) kuruluyor..."
if [ "$ARCH" = "arm64" ] && [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
    # Cross-building arm64 on x86 runner using QEMU
    debootstrap --arch=arm64 --foreign --variant=minbase bookworm "$ROOTFS" http://deb.debian.org/debian/
    cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/" 2>/dev/null || true
    chroot "$ROOTFS" /debootstrap/debootstrap --second-stage
else
    debootstrap --arch="$ARCH" --variant=minbase bookworm "$ROOTFS" http://deb.debian.org/debian/
fi

# 2. Configure Repositories & Keyrings
echo "[2/7] Paket depoları yapılandırılıyor..."
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
echo "[3/7] Temel paketler, Çekirdek ($ARCH), Wayland ve KDE kuruluyor..."
cp "$SCRIPT_DIR/packages.list" "$ROOTFS/tmp/packages.list"

KERNEL_PKG="linux-image-$ARCH"
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    KERNEL_PKG="linux-image-amd64"
fi

chroot "$ROOTFS" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends $KERNEL_PKG grub-efi-$ARCH-bin live-boot live-config
apt-get install -y --no-install-recommends \$(grep -v '^#' /tmp/packages.list | tr '\n' ' ')
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

useradd -m -s /bin/bash -G sudo,audio,video,render,plugdev duman || true
echo 'duman:duman' | chpasswd
echo 'root:duman' | chpasswd
echo 'duman ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

systemctl enable sddm.service || true
systemctl enable NetworkManager.service || true
systemctl enable dumanos-firstboot.service || true
"

# 6. Compress RootFS (SquashFS)
echo "[6/7] RootFS SquashFS ile sıkıştırılıyor..."
mkdir -p "$ISO_DIR/live"
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp zstd -Xcompression-level 15 -noappend

# Copy Kernel and Initrd to ISO
KERNEL_IMAGE=$(ls "$ROOTFS/boot" | grep -E 'vmlinuz|vmlinux' | head -n 1)
INITRD_IMAGE=$(ls "$ROOTFS/boot" | grep initrd | head -n 1)
cp "$ROOTFS/boot/$KERNEL_IMAGE" "$ISO_DIR/live/vmlinuz"
cp "$ROOTFS/boot/$INITRD_IMAGE" "$ISO_DIR/live/initrd"

# 7. Create Bootloader (GRUB EFI)
echo "[7/7] EFI Bootloader yapılandırılıyor ve ISO oluşturuluyor..."
mkdir -p "$ISO_DIR/boot/grub"
cat << 'EOF' > "$ISO_DIR/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "dumanOS Live ARM64 (KDE Wayland + Native Android Engine)" {
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
    -volid "DUMANOS_ARM64" \
    -output "$OUTPUT_DIR/dumanOS-$ARCH.iso" \
    "$ISO_DIR"

echo "=========================================================="
echo " [✓] TEBRİKLER! dumanOS ($ARCH) ISO başarıyla oluşturuldu:"
echo "     $OUTPUT_DIR/dumanOS-$ARCH.iso"
echo "=========================================================="
