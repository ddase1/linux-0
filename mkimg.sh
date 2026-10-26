#!/bin/bash
set -euo pipefail

IMG="bootable-disk.img"
IMG_SIZE=$((512 * 1024 * 1024)) # 512MB

# 清理旧文件
rm -f "$IMG"
rm -rf efi_root mnt

# 生成空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$IMG_SIZE" status=none

# GPT分区：使用 sfdisk GPT 兼容的类型简写
# U = EFI System Partition
# L = Linux filesystem
sfdisk "$IMG" <<EOF
label: gpt
,32M,U
,+,L
EOF

# 绑定loop设备，退出自动清理
LOOP=$(sudo losetup --find --show -P "$IMG")
trap 'sudo umount efi_root mnt 2>/dev/null; sudo losetup -d "$LOOP"' EXIT

ESP_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

# 格式化ESP，UEFI标准参数
sudo mkfs.fat -F32 -S 512 -s 1 -n EFI "$ESP_DEV"
sudo mkfs.ext4 "$ROOT_DEV"

mkdir -p efi_root mnt
sudo mount "$ESP_DEV" efi_root
sudo mount "$ROOT_DEV" mnt

# 安装GRUB EFI
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="$PWD/efi_root" \
    --boot-directory="$PWD/efi_root/boot" \
    --no-nvram \
    "$LOOP"

# 手动放置UEFI标准默认引导文件，保证OVMF自动识别
sudo mkdir -p efi_root/EFI/BOOT
sudo cp efi_root/EFI/grub/grubx64.efi efi_root/EFI/BOOT/BOOTX64.EFI

# 复制内核与initramfs
sudo cp bzImage efi_root/boot/vmlinuz
sudo cp initramfs.cpio.gz efi_root/boot/initrd

# 写入GRUB配置，根分区为第2分区
cat > grub.cfg <<'EOF'
menuentry "Minimal Linux" {
    linux /boot/vmlinuz root=/dev/sda2 rw console=tty0
    initrd /boot/initrd
}
EOF
sudo mkdir -p efi_root/boot/grub
sudo cp grub.cfg efi_root/boot/grub/grub.cfg
rm grub.cfg

echo "✅ UEFI 镜像构建完成: $IMG"
