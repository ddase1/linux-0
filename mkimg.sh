#!/bin/bash
set -euo pipefail

IMG="bootable-disk.img"
IMG_SIZE=$((512 * 1024 * 1024)) # 512MB

# 清理
rm -f "$IMG"
rm -rf efi_root mnt

# 空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$IMG_SIZE" status=none

# GPT分区表
# p1: BIOS Boot 1M
# p2: ESP 32M EF00
# p3: Linux rootfs
sfdisk "$IMG" <<EOF
label: gpt
,1M,21686148-6449-6E6F-744E-6F6544454649
,32M,C12A7328-F81F-11D2-BA4B-00A0C93EC93B
,+,L
EOF

# loop挂载，退出自动清理
LOOP=$(sudo losetup --find --show -P "$IMG")
trap 'sudo umount efi_root mnt 2>/dev/null; sudo losetup -d "$LOOP"' EXIT

BIOSBOOT_DEV="${LOOP}p1"
ESP_DEV="${LOOP}p2"
ROOT_DEV="${LOOP}p3"

# 格式化
sudo mkfs.fat -F32 -n EFI "$ESP_DEV"
sudo mkfs.ext4 "$ROOT_DEV"

mkdir -p efi_root mnt
sudo mount "$ESP_DEV" efi_root
sudo mount "$ROOT_DEV" mnt

# 安装GRUB EFI（可移动介质模式，BOOTX64.EFI）
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="$PWD/efi_root" \
    --boot-directory="$PWD/efi_root/boot" \
    --removable \
    "$LOOP"

# 复制内核+initrd
sudo cp bzImage efi_root/boot/vmlinuz
sudo cp initramfs.cpio.gz efi_root/boot/initrd

# grub.cfg，加console=tty0 屏幕输出
cat > grub.cfg <<'EOF'
menuentry "Minimal Linux" {
    linux /boot/vmlinuz root=/dev/sda3 rw console=tty0
    initrd /boot/initrd
}
EOF
sudo mkdir -p efi_root/boot/grub
sudo cp grub.cfg efi_root/boot/grub/grub.cfg
rm grub.cfg

# 安装BIOS GRUB
sudo grub-install \
    --target=i386-pc \
    --boot-directory="$PWD/efi_root/boot" \
    "$LOOP"

# rootfs 这里我们暂时留空，如果你后面要放文件，丢进rootfs目录即可
# sudo cp -r rootfs/* mnt/

echo "✅ 镜像构建完成: $IMG"
