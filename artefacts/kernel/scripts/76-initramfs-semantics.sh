#!/bin/bash
# Runs INSIDE the a9build container. Source-level check of how an EMBEDDED
# initramfs interacts with an EXTERNAL one, and whether a .gz source can be baked.
set -u
cd /build/linux-a9-qemu || exit 9

echo "############ 1. populate_rootfs(): embedded vs external initrd ############"
grep -n -A45 'static int __init populate_rootfs' init/initramfs.c | sed -n '1,70p'

echo
echo "############ 2. how the DT initrd is picked up (arch/arm64) ############"
grep -n -B3 -A12 'linux,initrd-start\|initrd_start\|initrd_end' arch/arm64/mm/init.c | sed -n '1,55p'

echo
echo "############ 3. can a COMPRESSED initramfs source be baked in? ############"
echo "--- usr/Makefile ---"
sed -n '1,45p' usr/Makefile
echo "--- gen_initramfs.sh: recognised compression ---"
grep -n -E 'gzip|\.gz|lzma|lz4|xz|zstd|bzip2|SUPPORTED' usr/gen_initramfs.sh | sed -n '1,40p'
echo "--- initramfs_data.S: does it decompress? ---"
sed -n '1,40p' usr/initramfs_data.S

echo
echo "############ 4. the config symbol that bakes it in ############"
grep -n -A12 '^config INITRAMFS_SOURCE' usr/Kconfig
echo "--- current value in BOTH configs ---"
echo "shipping config.used : $(grep -E '^CONFIG_INITRAMFS_SOURCE=' /build/linux-a9/.config)"
echo "qemu variant .config : $(grep -E '^CONFIG_INITRAMFS_SOURCE=' .config)"
echo "=== END ==="
