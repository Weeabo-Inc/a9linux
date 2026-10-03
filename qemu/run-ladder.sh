#!/usr/bin/env bash
# a9linux/qemu/run-ladder.sh — the QEMU boot ladder for the n69ap device tree.
#
# Three runs, in increasing distance from "the real board", each one isolating a
# different loader obligation. This is the negative-evidence product: it gives
# each failure its own signature, so that a silent hang on the phone can be
# matched against a known cause instead of guessed at.
#
#   02  console-only DTB  : /memory STILL UNFILLED. Expect: the kernel is told it
#                           has no RAM. Captures that signature.
#   03  fill DTB          : /memory filled, A9 interrupt controller left in place.
#                           Expect: no usable interrupt controller on QEMU virt.
#                           Captures that signature.
#   04  virt DTB          : memory filled + QEMU devices substituted + framebuffer0
#                           filled. Expect: reaches userland, simpledrm binds.
#
# Usage (either host): bash a9linux/qemu/run-ladder.sh
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
APPEND="console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1 loglevel=7"

run() {
  local name="$1" dtb="$2"
  echo
  echo "############################################################"
  echo "### $name"
  echo "############################################################"
  bash "$Q/run-qemu.sh" --name "$name" \
       --kernel "$STAGE/inputs/stock-Image" \
       --dtb "$dtb" \
       --initrd "$STAGE/inputs/harness-selfinit.cpio.gz" \
       --append "$APPEND" \
       --smp 2 --mem 1024 --timeout "${3:-120}" || true
  echo "--- verdict ---"
  local log="$STAGE/logs/$name.log"
  if grep -q 'A9QEMU-SELFTEST: REACHED-USERLAND' "$log"; then
    echo "RESULT: REACHED USERLAND via our initramfs"
  elif grep -q 'Kernel panic' "$log"; then
    echo "RESULT: KERNEL PANIC -> $(grep -m1 -o 'Kernel panic.*' "$log")"
  elif [ ! -s "$log" ]; then
    echo "RESULT: NO CONSOLE OUTPUT AT ALL (0 bytes)"
  else
    echo "RESULT: stopped without userland; last line: $(tail -1 "$log")"
  fi
  echo "markers: $(grep -c 'A9QEMU-SELFTEST' "$log" 2>/dev/null || echo 0)"
}

run 02-dtb-unfilled-memory "$STAGE/inputs/n69-qemu-console.dtb" 90
run 03-dtb-memory-filled-aic "$STAGE/inputs/n69-qemu-fill.dtb"   90
run 04-dtb-qemu-virt          "$STAGE/inputs/n69-qemu-virt.dtb"  180

echo
echo "############ ladder summary ############"
for n in 02-dtb-unfilled-memory 03-dtb-memory-filled-aic 04-dtb-qemu-virt; do
  L="$STAGE/logs/$n.log"
  printf '%-28s %8s bytes  %s\n' "$n" "$(stat -c%s "$L" 2>/dev/null || echo 0)" \
    "$(grep -q 'REACHED-USERLAND' "$L" 2>/dev/null && echo 'USERLAND' || (grep -q 'Kernel panic' "$L" 2>/dev/null && echo "PANIC: $(grep -m1 -o 'Kernel panic.*' "$L" | cut -c1-60)" || echo 'stopped/timeout'))"
done
