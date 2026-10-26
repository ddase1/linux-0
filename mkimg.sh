#!/bin/bash
set -e

IMG="bootable-disk.img"
SIZE=$(( 1024 * 1024 * 512 )) # 512MB

# 清理旧文件
rm -f "$IMG"
rm -rf mnt efi

# 新建空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$SIZE" status=none

# GPT分区：EFI 32M + 根分区
sfdisk "$IMG" <<EOF
label: gpt
,32M,U
,+,L
EOF

# loop挂载（sudo）
LOOP=$(sudo losetup --find --show -P "$IMG")
EFI_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

sudo mkfs.fat -F32 "$EFI_DEV"
sudo mkfs.ext4 "$ROOT_DEV"

mkdir -p efi mnt
sudo mount "$EFI_DEV" efi
sudo mount "$ROOT_DEV" mnt

# EFI / systemd-boot
sudo mkdir -p efi/EFI/BOOT
sudo cp bzImage efi/EFI/BOOT/vmlinuz
sudo cp initramfs.cpio.gz efi/EFI/BOOT/initrd

sudo mkdir -p efi/loader/entries
cat > entry.conf <<EOF
title My Min Linux
linux /EFI/BOOT/vmlinuz
initrd /EFI/BOOT/initrd
options root=/dev/vda2 rw quiet
EOF
sudo cp entry.conf efi/loader/entries/default.conf
rm entry.conf

sudo bootctl --esp-path=efi install

# 拷贝rootfs
sudo cp -r rootfs/* mnt/

# 顺序：先卸载，再释放loop！
sudo umount efi
sudo umount mnt
sudo losetup -d "$LOOP"

echo "✅ $IMG build finished"
