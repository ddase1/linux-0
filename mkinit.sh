#!/bin/bash
set -euo pipefail

# 清理旧文件
rm -rf initramfs
rm -f initramfs.cpio.gz

mkdir -p initramfs/{bin,sbin,dev,proc,sys,root,etc}
cd initramfs

# 修复：ubuntu24.04 busybox-static 在 /bin/busybox
cp /bin/busybox bin/busybox
chmod +x bin/busybox

# 创建常用软链接
ln -s busybox bin/sh
ln -s busybox bin/ls
ln -s busybox bin/cat
ln -s busybox bin/mount
ln -s busybox bin/echo

# init启动脚本
cat > init <<'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
echo "✅ Hello Minimal Linux!"
exec /bin/sh
EOF
chmod +x init

# 打包initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd ..
echo "✅ initramfs.cpio.gz 生成完成"
