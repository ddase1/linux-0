#!/bin/bash
set -euo pipefail

# 清理旧文件
rm -rf initramfs
rm -f initramfs.cpio.gz

mkdir -p initramfs/{bin,sbin,dev,proc,sys,root,etc}
cd initramfs

# 复制busybox静态二进制
cp /usr/bin/busybox-static bin/busybox
chmod +x bin/busybox

# 创建符号链接
ln -s busybox bin/sh
ln -s busybox bin/ls
ln -s busybox bin/cat
ln -s busybox bin/mount
ln -s busybox bin/echo

# 写init脚本
cat > init <<'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "Hello Minimal Linux!"
exec /bin/sh
EOF
chmod +x init

# 打包cpio
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..
echo "✅ initramfs.cpio.gz 生成完成"
