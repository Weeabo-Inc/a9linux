#!/usr/bin/env bash
# a9linux/qemu/run-stub.sh — the hand-off run: QEMU places every blob the way a
# loader would, our stub does the arm64 hand-off, and the DTB (not a bootloader
# API) carries the command line and the initramfs placement.
#
# What this can catch that `-kernel` cannot:
#   * x0 = DTB / x1..x3 = 0 expressed by OUR code rather than QEMU's
#   * /chosen/bootargs as the only cmdline channel
#   * /chosen/initrd-start/end as the only initramfs channel
#   * the spin-table contract: a core parked on cpu-release-addr that the kernel
#     can actually release (compare with run 04, where nothing was parked and
#     CPU1 timed out after ~7.5s)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
INITRD="$STAGE/inputs/harness-selfinit.cpio.gz"
# Load map — must match mk-handoff-stub.sh. Everything the loader owns must sit
# ABOVE the kernel's image+bss (this Image clears .bss in __primary_switched,
# before it reads the DTB — placing the DTB inside the image silently zeroes it).
INITRD_ADDR=0x44200000
IMAGE_ADDR=0x40080000
DTB_ADDR=0x44100000
MAILBOX=0x44004000
ADAPTED="$STAGE/inputs/n69-qemu-stub.dtb"

ISIZE=$(stat -c%s "$INITRD")
BOOTARGS="console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1 loglevel=7 mailbox=$MAILBOX"

echo "== building the stub-mode DTB (virt substitutions + DT-delivered bootargs/initrd) =="
python3 "$Q/adapt-dtb.py" "$STAGE/inputs/source-n69.dtb" "$ADAPTED" --mode virt \
    --cpu-release-addr "$MAILBOX" \
    --bootargs "$BOOTARGS" \
    --initrd-addr "$INITRD_ADDR" --initrd-size "$ISIZE"
python3 "$Q/check-dtb.py" "$ADAPTED" || echo "(audit had findings)"

echo
echo "== booting: no -kernel, no -dtb, no -initrd, no -append =="
IMAGE_ADDR=$IMAGE_ADDR DTB_ADDR=$DTB_ADDR INITRD_ADDR=$INITRD_ADDR \
bash "$Q/run-qemu.sh" --name 05-loader-stub-handoff \
     --kernel "$STAGE/inputs/stock-Image" \
     --dtb "$ADAPTED" \
     --initrd "$INITRD" \
     --loader-stub "$STAGE/inputs/handoff-stub.bin" \
     --smp 2 --mem 1024 --timeout 240

L="$STAGE/logs/05-loader-stub-handoff.log"
echo
echo "--- verdict ---"
grep -m2 '\[stub\]' "$L" 2>/dev/null || echo "(no stub banner: the stub never ran)"
if grep -q 'A9QEMU-SELFTEST: REACHED-USERLAND' "$L"; then
  echo "RESULT: REACHED USERLAND through the stub hand-off"
else
  echo "RESULT: did NOT reach userland"
fi
grep -E 'Brought up|CPU1|Total of .* processors' "$L" 2>/dev/null | sed 's/^/  /'
