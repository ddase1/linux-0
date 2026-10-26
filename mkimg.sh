#!/bin/bash
set -e

IMG="bootable.img"
IMG_SIZE=$((512 * 1024 * 1024)) # 512M

rm -f "$IMG"
rm -rf mnt efi_root

# 1. 生成空白镜像
dd if=/dev/zero of="$IMG" bs=1 count="$IMG_SIZE" status=none

# 2. GPT分区：
# p1: BIOS Boot 1M （GRUB BIOS core）
# p2: ESP 32M, EF00 (EFI System)
# p3: Linux root，剩余空间
sfdisk "$IMG" <<EOF
label: gpt
,1M,21686148-6449-6E6F-744E-6F6544454649
,32M,C12A7328-F81F-11D2-BA4B-00A0C93EC93B
,+,L
EOF

# 3. 挂载loop
LOOP=$(sudo losetup --find --show -P "$IMG")
BIOSBOOT_DEV="${LOOP}p1"
ESP_DEV="${LOOP}p2"
ROOT_DEV="${LOOP}p3"

# ========== 格式化ESP（改用稳妥参数，加卷标EFI） ==========
sudo mkfs.fat -F32 -n EFI "$ESP_DEV"
sudo mkfs.ext4 "$ROOT_DEV"

mkdir -p efi_root mnt
sudo mount "$ESP_DEV" efi_root
sudo mount "$ROOT_DEV" mnt

# ========== 安装GRUB EFI（x86_64-efi） ==========
sudo grub-install \
    --target=x86_64-efi \
    --efi-directory="$PWD/efi_root" \
    --boot-directory="$PWD/efi_root/boot" \
    --removable \
    "$LOOP"

# 拷贝内核和initrd到ESP
sudo cp bzImage efi_root/boot/vmlinuz
sudo cp initramfs.cpio.gz efi_root/boot/initrd

# 写grub.cfg
cat > grub.cfg <<'EOF'
menuentry "MyOS" {
    linux /boot/vmlinuz root=/dev/sda3 rw console=tty0
    initrd /boot/initrd
}
EOF
sudo cp grub.cfg efi_root/boot/grub/grub.cfg
rm grub.cfg

# ========== 安装GRUB BIOS（传统BIOS引导） ==========
sudo grub-install \
    --target=i386-pc \
    --boot-directory="$PWD/efi_root/boot" \
    "$LOOP"

# rootfs
sudo cp -r rootfs/* mnt/

# 卸载、释放loop
sudo umount efi_root mnt
sudo losetup -d "$LOOP"

echo "✅ 双启动镜像完成：UEFI + BIOS"
