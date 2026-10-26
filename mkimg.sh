#!/bin/bash
set -euo pipefail

IMG="bootable-disk.img"
IMG_SIZE=$((512 * 1024 * 1024)) # 512MB

# 清理
rm -f "$IMG"
rm -rf efi_root mnt

# 空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$IMG_SIZE" status=none

# GPT：p1=ESP 32M，p2=Linux root
# 不再保留BIOS Boot分区，只做UEFI
sfdisk "$IMG" <<EOF
label: gpt
,32M,C12A7328-F81F-11D2-BA4B-00A0C93EC93B
,+,L
EOF

# loop挂载，退出自动清理
LOOP=$(sudo losetup --find --show -P "$IMG")
trap 'sudo umount efi_root mnt 2>/dev/null; sudo losetup -d "$LOOP"' EXIT

ESP_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

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

# grub.cfg，注意 root 变成 /dev/sda2
cat > grub.cfg <<'EOF'
menuentry "Minimal Linux" {
    linux /boot/vmlinuz root=/dev/sda2 rw console=tty0
    initrd /boot/initrd
}
EOF
sudo mkdir -p efi_root/boot/grub
sudo cp grub.cfg efi_root/boot/grub/grub.cfg
rm grub.cfg

echo "✅ UEFI-only 镜像构建完成: $IMG"
