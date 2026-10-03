#!/bin/bash
# Runs on the podman-main VM HOST (not in the container).
# Copies FINISHED artefacts OUT of the VM's ext4 onto E:.
# This is the only permitted direction: build inside ext4, copy results out.
# Never builds or runs make over /mnt/*.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

SRC=/build/linux-a9/arch/arm64/boot
DTBSRC=/build/linux-a9/arch/arm64/boot/dts/apple
DEST=/mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel

echo "=== source (inside VM ext4) ==="
ls -la "$SRC/Image" "$SRC/Image.gz" "$DTBSRC/s8003-n69.dtb"
echo "--- filesystem backing the source (MUST be ext4, NOT 9p/drvfs) ---"
df -T /build/linux-a9 | tail -n 1
findmnt -no FSTYPE,SOURCE,TARGET /build 2>/dev/null || true

echo ""
echo "=== source SHA-256 ==="
sha256sum "$SRC/Image" "$SRC/Image.gz" "$DTBSRC/s8003-n69.dtb" | tee /tmp/src-hashes.txt

echo ""
echo "=== destination ==="
mkdir -p "$DEST"
cp -f "$SRC/Image"      "$DEST/Image"
cp -f "$SRC/Image.gz"   "$DEST/Image.gz"
cp -f "$DTBSRC/s8003-n69.dtb" "$DEST/s8003-n69.dtb"
cp -f /build/linux-a9/.config "$DEST/config.used"
cp -f /build/kbuild-clean.log "$DEST/kbuild-clean.log"

echo ""
echo "=== destination SHA-256 (recomputed AFTER the copy, over drvfs) ==="
sha256sum "$DEST/Image" "$DEST/Image.gz" "$DEST/s8003-n69.dtb" "$DEST/config.used" | tee /tmp/dst-hashes.txt

echo ""
echo "=== copy integrity: source hash == destination hash? ==="
# Compare the HASH FIELD ONLY -- the paths legitimately differ (that is the point
# of a copy), so including them in the diff would always produce a false failure.
if diff <(awk '{print $1}' /tmp/src-hashes.txt) <(awk '{print $1}' /tmp/dst-hashes.txt | head -n 3) > /dev/null; then
  echo ">>> PASS: all three artefacts survived the copy byte-identically (hashes match)"
else
  echo ">>> FAIL: hash mismatch across the copy -- the E: copy is NOT trustworthy"
  diff <(awk '{print $1}' /tmp/src-hashes.txt) <(awk '{print $1}' /tmp/dst-hashes.txt | head -n 3)
fi

echo ""
echo "=== listing on E: ==="
ls -la "$DEST"
