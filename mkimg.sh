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

sudo mkfs.fat -F32 -S 512 -s 1 "$EFI_DEV"
sudo mkfs.ext4 "$ROOT_DEV"

mkdir -p efi mnt
sudo mount "$EFI_DEV" efi
sudo mount "$ROOT_DEV" mnt

# --------------------------
# EFI分区：手动放systemd-boot，不用bootctl install
# --------------------------
sudo mkdir -p efi/EFI/BOOT
# 复制 systemd-boot 的EFI引导文件
sudo cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi efi/EFI/BOOT/BOOTX64.EFI

# 内核+initramfs
sudo cp bzImage efi/EFI/BOOT/vmlinuz
sudo cp initramfs.cpio.gz efi/EFI/BOOT/initrd

# loader配置
sudo mkdir -p efi/loader/entries
cat > entry.conf <<EOF
title My Min Linux
linux /EFI/BOOT/vmlinuz
initrd /EFI/BOOT/initrd
options root=/dev/vda2 rw quiet
EOF
sudo cp entry.conf efi/loader/entries/default.conf
rm entry.conf

# loader.conf 默认
cat > loader.conf <<EOF
default default
timeout 3
EOF
sudo cp loader.conf efi/loader/loader.conf
rm loader.conf

# --------------------------
# 拷贝rootfs
# --------------------------
sudo cp -r rootfs/* mnt/

# 【顺序：先卸载，再释放loop！】
sudo umount efi
sudo umount mnt
sudo losetup -d "$LOOP"

echo "✅ $IMG build finished"
