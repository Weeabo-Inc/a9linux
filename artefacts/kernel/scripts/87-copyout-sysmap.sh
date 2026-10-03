#!/bin/bash
# Runs on the podman-main VM HOST.
# Copies BOTH System.map files out so the PL011 A/B is citable from E: alone.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

DEST=/mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel
SHIP=/build/linux-a9/System.map
VAR=/build/linux-a9-qemu/System.map

echo "=== source ==="
ls -la "$SHIP" "$VAR"

echo
echo "=== source SHA-256 ==="
sha256sum "$SHIP" "$VAR" | tee /tmp/sysmap-src.txt

echo
echo "=== copy out ==="
cp -f "$SHIP" "$DEST/System.map"
cp -f "$VAR"  "$DEST/System.map-qemu-pl011"

echo
echo "=== destination SHA-256 (after the copy) ==="
sha256sum "$DEST/System.map" "$DEST/System.map-qemu-pl011" | tee /tmp/sysmap-dst.txt

echo
echo "=== integrity ==="
if diff <(awk '{print $1}' /tmp/sysmap-src.txt) <(awk '{print $1}' /tmp/sysmap-dst.txt) > /dev/null; then
  echo ">>> PASS: both System.map files survived the copy byte-identically"
else
  echo ">>> FAIL: hash mismatch"; diff <(awk '{print $1}' /tmp/sysmap-src.txt) <(awk '{print $1}' /tmp/sysmap-dst.txt)
fi

echo
echo "=== the A/B, now reproducible from E: alone ==="
printf 'shipping System.map pl011 : %s\n' "$(grep -c -i pl011 "$DEST/System.map")"
printf 'variant  System.map pl011 : %s\n' "$(grep -c -i pl011 "$DEST/System.map-qemu-pl011")"
echo
echo "=== E: artefact directory ==="
ls -la "$DEST"
