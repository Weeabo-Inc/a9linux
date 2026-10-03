#!/usr/bin/env bash
# a9linux/qemu/observe-mailbox.sh — boot the hand-off and watch, from OUTSIDE the
# guest, whether the kernel writes the secondary CPU's entry address into the
# cpu-release-addr our device tree names.
#
# This is the one part of the spin-table contract QEMU can still show us: QEMU
# `virt` holds secondary cores powered off (only PSCI releases them), so the
# parked core itself cannot be emulated -- but the kernel's *write* is a real
# memory store to an address we chose, and QEMU's monitor can read it.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
MAILBOX=0x44004000
DTB="$STAGE/inputs/n69-qemu-stub.dtb"
INITRD="$STAGE/inputs/harness-selfinit.cpio.gz"
SOCK="$STAGE/work/mon.sock"
LOG="$STAGE/logs/06-mailbox-observe.log"

rm -f "$SOCK"
echo "=== booting with the monitor on $SOCK (60s cap) ==="
timeout -k 5 60 qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 1024 \
  -display none -serial file:"$LOG" -no-reboot \
  -monitor unix:"$SOCK",server,nowait \
  -dtb "$DTB" \
  -device loader,file="$STAGE/inputs/stock-Image",addr=0x40080000,force-raw=on \
  -device loader,file="$DTB",addr=0x44100000,force-raw=on \
  -device loader,file="$INITRD",addr=0x44200000,force-raw=on \
  -device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=0 \
  -device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=1 &
QPID=$!

# the kernel reaches SMP bring-up ~6s in (measured from run 05)
for t in 8 12 16; do
  sleep 4
  if [ -S "$SOCK" ]; then
    echo "--- t~${t}s: mailbox $MAILBOX ---"
    python3 "$Q/mon-read.py" "$SOCK" "$MAILBOX" || echo "(monitor read failed)"
  fi
done

# also read the DT's own copy of the property, straight out of guest RAM:
# /chosen is inside the DTB we placed at 0x44100000
echo "--- /proc/iomem-equivalent sanity: read 64-bit words at the DTB base ---"
python3 "$Q/mon-read.py" "$SOCK" 0x44100000 || true

kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo
echo "=== guest log: SMP lines ==="
grep -E 'CPU1|Brought up|Total of' "$LOG" 2>/dev/null | sed 's/^/  /'
echo "log -> $LOG"
