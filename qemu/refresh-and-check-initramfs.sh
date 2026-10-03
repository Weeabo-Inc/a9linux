#!/usr/bin/env bash
# a9linux/qemu/refresh-and-check-initramfs.sh
#
# 1. re-point the harness at rootfs-engineer's CURRENT initramfs artefacts and
#    verify them against their own SHA256SUMS (their files moved twice today:
#    the size must be taken from the file at run time, never from a note),
# 2. cross-check the loader-window question with THEIR guard script,
# 3. run the two larger variants through the same kernel/DT path as the min one,
#    so a failure can be attributed to the initramfs rather than to the kernel.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
DIST="$W/debian-ios/dist"
K="$STAGE/inputs/arlo-Image-qemu-pl011"
BOOTARGS="console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1 loglevel=7"

echo "=== [1] refresh + verify rootfs-engineer's artefacts ==="
for f in arlo-initramfs-min.cpio.gz arlo-initramfs-dash.cpio.gz arlo-initramfs-debian.cpio.gz \
         arlo-initramfs-debian.cpio SHA256SUMS; do
  if [ -f "$DIST/$f" ]; then
    cp -f "$DIST/$f" "$STAGE/inputs/$f"
    printf '  %-34s %10s B  sha256=%s\n' "$f" "$(stat -c%s "$DIST/$f")" "$(sha256sum "$DIST/$f" | cut -c1-32)"
  else
    printf '  %-34s MISSING\n' "$f"
  fi
done
if [ -f "$DIST/SHA256SUMS" ]; then
  ( cd "$STAGE/inputs" && grep -E 'arlo-initramfs-(min|dash|debian)' "$DIST/SHA256SUMS" \
      | sha256sum -c --quiet - 2>&1 | sed 's/^/  verify: /' ; echo "  (verify exit=$?)" )
fi

echo
echo "=== [2] their loader-window guard, pointed at dt-engineer's DTB ==="
if [ -x "$DIST/../scripts/check-loader-window.sh" ] || [ -f "$DIST/../scripts/check-loader-window.sh" ]; then
  bash "$DIST/../scripts/check-loader-window.sh" --dtb "$STAGE/inputs/n69-loader-target.dtb" 2>&1 | sed 's/^/  /'
  echo "  (guard exit=$?)"
else
  echo "  (their guard script not found; the window fact is already reported)"
fi

echo
echo "=== [3] key evidence from run 14 (our kernel + OUR DT + our stub) ==="
grep -a -m1 'Machine model' "$STAGE/logs/14-variant-our-dtb-stub.log" 2>/dev/null | sed 's/^/  /'
grep -a -m1 'Kernel command line' "$STAGE/logs/14-variant-our-dtb-stub.log" 2>/dev/null | sed 's/^/  /'
grep -a -m1 'pl011' "$STAGE/logs/14-variant-our-dtb-stub.log" 2>/dev/null | sed 's/^/  /'
grep -a -m2 'arlo\|login' "$STAGE/logs/14-variant-our-dtb-stub.log" 2>/dev/null | sed 's/^/  /'
grep -a 'CPU1\|Brought up' "$STAGE/logs/14-variant-our-dtb-stub.log" 2>/dev/null | sed 's/^/  /'

echo
echo "=== [4] the larger initramfs variants, same kernel and path as run 13 ==="
for pair in "16-variant-dash:arlo-initramfs-dash.cpio.gz" \
            "15-variant-debian-initrd:arlo-initramfs-debian.cpio.gz"; do
  name="${pair%%:*}"; file="${pair##*:}"
  [ -f "$STAGE/inputs/$file" ] || { echo "  skip $name ($file missing)"; continue; }
  echo
  echo "--- $name  ($file, $(stat -c%s "$STAGE/inputs/$file") B) ---"
  bash "$Q/run-qemu.sh" --name "$name" --kernel "$K" --cpu max \
    --initrd "$STAGE/inputs/$file" --append "$BOOTARGS" --smp 2 --mem 1024 --timeout 150 2>&1 \
    | grep -E 'console_bytes|console_lines|exit |initrd_size|initrd_sha' | sed 's/^/  /'
  L="$STAGE/logs/$name.log"
  printf '  markers: '
  if grep -qa 'arlo:/#\|login:' "$L" 2>/dev/null; then echo "USERLAND (shell reached)"
  elif grep -qa 'Kernel panic' "$L" 2>/dev/null; then echo "PANIC: $(grep -a -m1 -o 'Kernel panic.*' "$L" | cut -c1-70)"
  else echo "no shell and no panic; last kernel line: $(grep -a '^\[ ' "$L" | tail -1 | cut -c1-90)"; fi
done