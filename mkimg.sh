#!/bin/bash
set -euo pipefail

IMG="bootable-disk.img"
IMG_SIZE=$((512 * 1024 * 1024)) # 512MB

# 清理
rm -f "$IMG"
rm -rf efi_root mnt

# 空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$IMG_SIZE" status=none

# GPT分区：p1=ESP EFI系统分区，p2=Linux根分区
sfdisk "$IMG" <<EOF
label: gpt
,32M,ef00
,+,L
EOF

# loop挂载，退出自动清理
LOOP=$(sudo losetup --find --show -P "$IMG")
trap 'sudo umount efi_root mnt 2>/dev/null; sudo losetup -d "$LOOP"' EXIT

ESP_DEV="${LOOP}p1"
ROOT_DEV="${LOOP}p2"

# 格式化ESP，标准参数
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

# ========== 关键修复：手动创建UEFI标准可移动介质引导路径 ==========
sudo mkdir -p efi_root/EFI/BOOT
# 把grub的efi文件复制成UEFI默认引导文件名
sudo cp efi_root/EFI/grub/grubx64.efi efi_root/EFI/BOOT/BOOTX64.EFI

# 复制内核+initrd
sudo cp bzImage efi_root/boot/vmlinuz
sudo cp initramfs.cpio.gz efi_root/boot/initrd

# 写入grub配置，根分区是第2分区 sda2
cat > grub.cfg <<'EOF'
menuentry "Minimal Linux" {
    linux /boot/vmlinuz root=/dev/sda2 rw console=tty0
    initrd /boot/initrd
}
EOF
sudo mkdir -p efi_root/boot/grub
sudo cp grub.cfg efi_root/boot/grub/grub.cfg
rm grub.cfg

echo "✅ UEFI镜像构建完成，标准BOOTX64.EFI已放置"
