#!/bin/bash
set -e

IMG="bootable-disk.img"
rm -f $IMG

# 64M镜像，足够当前系统
truncate -s 64M $IMG

# GPT分区表：ESP(32M) + EXT4根
parted $IMG --script mklabel gpt
parted $IMG --script mkpart ESP fat32 1MiB 33MiB
parted $IMG --script set 1 esp on
parted $IMG --script mkpart root ext4 33MiB 100%

# 回环挂载
LOOP=$(losetup --find --show $IMG)
partprobe $LOOP

# 格式化ESP
mkfs.fat -F32 ${LOOP}p1
# 格式化EXT4根
mkfs.ext4 ${LOOP}p2

# 挂载ESP
mkdir -p mnt_esp
mount ${LOOP}p1 mnt_esp

# 放入systemd-boot
mkdir -p mnt_esp/EFI/BOOT
cp /usr/lib/systemd/boot/efi/systemd-bootx64.efi mnt_esp/EFI/BOOT/BOOTX64.EFI
mkdir -p mnt_esp/loader/entries

# 引导配置
cat > mnt_esp/loader/loader.conf <<EOF
default  minimal
timeout  2
console-mode max
EOF

cp out/bzImage mnt_esp/
cp out/initramfs.cpio.gz mnt_esp/

cat > mnt_esp/loader/entries/minimal.conf <<EOF
title Minimal x86_64 EXT4 Builtin
linux /bzImage
initrd /initramfs.cpio.gz
options quiet loglevel=3
EOF

umount mnt_esp

# 挂载EXT4根分区
mkdir -p mnt_root
mount ${LOOP}p2 mnt_root

# 拷贝系统文件
cp out/busybox-full mnt_root/
cp out/minimal-drivers.tar.gz mnt_root/
cp out/full-drivers.tar.gz mnt_root/

cat > mnt_root/init <<'EOF'
#!/bin/sh
set -e

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

/busybox-full --install -s
echo "==== DIY OS | All Drivers Dynamic ===="

# 切换 full-drivers / minimal-drivers
# DRV_PACK="/minimal-drivers.tar.gz"
DRV_PACK="/full-drivers.tar.gz"

if [ -f "$DRV_PACK" ]; then
    echo "[DRIVER] Extract driver bundle"
    tar -zxf "$DRV_PACK" -C /
    depmod -a
else
    echo "[WARN] Driver package missing, limited hardware support"
fi

echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s &

echo "[INFO] Dynamic driver manager running"

TARGET=""
for name in boot run main start app; do
    if [ -x "/$name" ]; then
        TARGET="/$name"
        break
    fi
done

if [ -n "$TARGET" ]; then
    echo "[RUN] Launch user program: $TARGET"
    exec "$TARGET"
else
    echo "[SHELL] No boot entry found"
    exec /bin/sh
fi
EOF
chmod +x mnt_root/init

umount mnt_root
losetup -d $LOOP

echo "Done: $IMG"
