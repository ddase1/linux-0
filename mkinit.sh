#!/bin/bash
set -e

rm -rf initramfs
mkdir -p initramfs/{bin,sbin,dev,proc,sys,tmp,root}

# 复制静态busybox
cp /bin/busybox initramfs/bin/
chmod +x initramfs/bin/busybox

# 基础链接
cd initramfs
ln -s bin/busybox init
ln -s bin/busybox sbin/init
for cmd in sh mount umount ls cat echo test mkdir rm cp sleep poweroff reboot; do
    ln -s busybox bin/$cmd
done
cd ..

# 打包
cd initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..
rm -rf initramfs

echo "✅ initramfs.cpio.gz done"
