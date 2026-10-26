#!/bin/bash
set -e
OUT=out
rm -rf $OUT/initramfs
mkdir -p $OUT/initramfs/{bin,dev,proc,sys,mnt}

cp $OUT/busybox-mini $OUT/initramfs/bin/busybox
chmod +x $OUT/initramfs/bin/busybox
cd $OUT/initramfs/bin
./busybox --install -s
cd -

cat > $OUT/initramfs/init <<'EOF'
#!/bin/sh
set -e

mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t sysfs none /sys

echo "==== Minimal Bootstrap | EXT4 Builtin ===="

echo "[BOOT] Scanning EXT4 system partition..."
EXT4_DEV=""
TIMEOUT=15
while [ $TIMEOUT -gt 0 ]; do
    EXT4_DEV=$(blkid -o device -t TYPE=ext4 2>/dev/null | head -n1)
    if [ -n "$EXT4_DEV" ]; then
        break
    fi
    sleep 1
    TIMEOUT=$((TIMEOUT - 1))
done

if [ -z "$EXT4_DEV" ]; then
    echo "[FAIL] EXT4 partition not found, drop debug shell"
    exec /bin/sh
fi

echo "[OK] Mount $EXT4_DEV -> /mnt"
mount -t ext4 "$EXT4_DEV" /mnt

echo "[HANDOVER] switch_root to DIY OS"
exec switch_root /mnt /mnt/init
EOF
chmod +x $OUT/initramfs/init

cd $OUT/initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../initramfs.cpio.gz
cd -
