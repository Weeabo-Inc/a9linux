#!/bin/bash
# Runs on the podman-main VM HOST.
# Copies the QEMU-only variant OUT to E: under a name that cannot be mistaken
# for the shipping kernel.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

W=/build/linux-a9-qemu
DEST=/mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel

echo "=== source (VM ext4) ==="
ls -la "$W/arch/arm64/boot/Image" "$W/.config"
df -T "$W" | tail -n 1

echo
echo "=== source SHA-256 ==="
sha256sum "$W/arch/arm64/boot/Image" "$W/.config" | tee /tmp/qemu-src.txt

echo
echo "=== copy out under an unambiguous name ==="
cp -f "$W/arch/arm64/boot/Image"  "$DEST/Image-16k-qemu-pl011"
cp -f "$W/.config"                "$DEST/config-qemu-pl011.used"
cp -f /build/kbuild-qemu-pl011.log "$DEST/kbuild-qemu-pl011.log"

echo
echo "=== destination SHA-256 (recomputed AFTER the copy, over drvfs) ==="
sha256sum "$DEST/Image-16k-qemu-pl011" "$DEST/config-qemu-pl011.used" | tee /tmp/qemu-dst.txt

echo
echo "=== copy integrity (hash field only) ==="
if diff <(awk '{print $1}' /tmp/qemu-src.txt) <(awk '{print $1}' /tmp/qemu-dst.txt) > /dev/null; then
  echo ">>> PASS: variant artefacts survived the copy byte-identically"
else
  echo ">>> FAIL: hash mismatch across the copy"
  diff <(awk '{print $1}' /tmp/qemu-src.txt) <(awk '{print $1}' /tmp/qemu-dst.txt)
fi

echo
echo "=== the THREE kernels must all have distinct hashes ==="
sha256sum "$DEST/Image" "$DEST/Image-16k-qemu-pl011" 2>&1
echo
echo "=== E: artefact directory now ==="
ls -la "$DEST"
