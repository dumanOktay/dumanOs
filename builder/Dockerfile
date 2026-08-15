FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    debootstrap \
    xorriso \
    isolinux \
    syslinux-efi \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    squashfs-tools \
    dosfstools \
    libarchive-tools \
    curl \
    git \
    sudo

WORKDIR /workspace

CMD ["bash", "builder/build.sh"]
