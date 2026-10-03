#!/usr/bin/env bash
# a9linux/qemu/run-console-variant.sh — boot kernel-engineer's QEMU-console test
# variant (PL011 added; 16K granule kept) with OUR device tree and OUR initramfs.
#
# This is the run that was impossible before: our shipping kernel has no PL011
# driver, so QEMU could not show us a single byte of its boot. The variant is a
# TEST INSTRUMENT with exactly two config symbols different, and it must never
# reach the phone. The shipping kernel stays a9linux/artefacts/kernel/Image.
#
#   RUNS=14,15 bash run-console-variant.sh     # skip the slow baseline run 13
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
RUNS="${RUNS:-13,14,15}"
K="$STAGE/inputs/arlo-Image-qemu-pl011"
MIN="$STAGE/inputs/arlo-initramfs-min.cpio.gz"
DEB="$STAGE/inputs/arlo-initramfs-debian.cpio.gz"
SHIP="$STAGE/inputs/arlo-Image"
MAILBOX=0x44004000
INITRD_ADDR=0x44200000
DTB_ADDR=0x44100000
BOOTARGS_COMMON="console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1 loglevel=7"

echo "=== [A/B] 'pl011' literal count in each Image (independent of any System.map) ==="
for img in "$SHIP" "$K"; do
  printf '  %-46s pl011=%-5s s5l=%-5s %s\n' "$(basename "$img")" \
    "$(strings -a "$img" | grep -c -i pl011)" \
    "$(strings -a "$img" | grep -c -i 's5l')" \
    "$(file -b "$img" | sed 's/.*, //')"
done
echo "  (the variant must ADD pl011 without losing the s5l/device console)"

if [[ "$RUNS" == *13* && "${SUMMARY_ONLY:-0}" != 1 ]]; then
  echo
  echo "########## 13: variant + QEMU's own virt DT + min initramfs ##########"
  bash "$Q/run-qemu.sh" --name 13-variant-virt-dt --kernel "$K" --cpu max \
    --initrd "$MIN" --append "$BOOTARGS_COMMON" --smp 2 --mem 1024 --timeout 180 || true
fi

if [[ "$RUNS" == *14* && "${SUMMARY_ONLY:-0}" != 1 ]]; then
  ISIZE=$(stat -c%s "$MIN")
  BOOTARGS="$BOOTARGS_COMMON mailbox=$MAILBOX"
  echo
  echo "########## 14: variant + OUR DT (adapted) + stub hand-off + min initramfs ##########"
  echo "building adapted DTB (bootargs + linux,initrd-* for the stub path; initrd $ISIZE bytes)"
  python3 "$Q/adapt-dtb.py" "$STAGE/inputs/n69-loader-target.dtb" \
    "$STAGE/inputs/n69-variant-stub.dtb" --mode virt \
    --cpu-release-addr "$MAILBOX" --bootargs "$BOOTARGS" \
    --initrd-addr "$INITRD_ADDR" --initrd-size "$ISIZE" > "$STAGE/logs/14-adapt.log" 2>&1
  python3 "$Q/check-dtb.py" "$STAGE/inputs/n69-variant-stub.dtb" | tail -4

  IMAGE_ADDR=0x40080000 DTB_ADDR=$DTB_ADDR INITRD_ADDR=$INITRD_ADDR \
  bash "$Q/run-qemu.sh" --name 14-variant-our-dtb-stub --kernel "$K" --cpu max \
    --dtb "$STAGE/inputs/n69-variant-stub.dtb" --initrd "$MIN" \
    --loader-stub "$STAGE/inputs/handoff-stub.bin" \
    --smp 2 --mem 1024 --timeout 180 || true
fi

if [[ "$RUNS" == *15* && "${SUMMARY_ONLY:-0}" != 1 ]]; then
  ISIZE2=$(stat -c%s "$DEB")
  echo
  echo "########## 15: variant + QEMU DT + the full debian initramfs ##########"
  echo "(kernel-engineer's sizing warning: the DTB *template* window is 2,670,592 B;"
  echo " this file is $ISIZE2 B. This run does not use that window: it passes"
  echo " -initrd to QEMU, so QEMU writes /chosen on its own generated DT.)"
  bash "$Q/run-qemu.sh" --name 15-variant-debian-initrd --kernel "$K" --cpu max \
    --initrd "$DEB" --append "$BOOTARGS_COMMON" --smp 2 --mem 1024 --timeout 240 || true
fi

echo
echo "=== summary of markers ==="
# Marker detection is deliberately loose. An earlier version matched only
# 'arlo:/#' and therefore reported dash and debian as "no userland marker" when
# both had in fact reached a shell with the prompt 'arlo:\w#' (an unexpanded PS1
# escape). That is the same class of error this project keeps paying for: a
# too-specific match producing a confident wrong answer.
for n in 13-variant-virt-dt 14-variant-our-dtb-stub 16-variant-dash 15-variant-debian-initrd; do
  L="$STAGE/logs/$n.log"
  printf '%-30s %8s bytes  ' "$n" "$(stat -c%s "$L" 2>/dev/null || echo 0)"
  if grep -qaE 'arlo:|A9QEMU-SELFTEST: REACHED-USERLAND|login:' "$L" 2>/dev/null; then
    echo "USERLAND (shell reached: $(grep -aoE 'arlo:[^ ]*' "$L" | head -1))"
  elif grep -qa 'Kernel panic' "$L" 2>/dev/null; then
    echo "PANIC: $(grep -a -m1 -o 'Kernel panic.*' "$L" | cut -c1-70)"
  else
    echo "no userland marker (see log)"
  fi
done