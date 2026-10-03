#!/usr/bin/env bash
# a9linux/qemu/diag-arlo-kernel.sh — why does OUR 16K kernel stop early on QEMU?
# It has no console driver for QEMU virt, so we use QEMU's exception log and a
# disassembly of the PC it is stuck at.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
LOGD="$STAGE/logs/09-exceptions.log"
IMG="$STAGE/inputs/arlo-Image"
DTB="$STAGE/inputs/n69-arlo-qemu-virt.dtb"

echo "=== booting with -d int,guest_errors (45s) ==="
timeout -k 5 45 qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 1024 \
  -display none -serial file:"$STAGE/logs/09-arlo-kernel-exc.log" -no-reboot -monitor none \
  -d int,guest_errors -D "$LOGD" \
  -dtb "$DTB" \
  -device loader,file="$IMG",addr=0x40080000,force-raw=on \
  -device loader,file="$DTB",addr=0x44100000,force-raw=on \
  -device loader,file="$STAGE/inputs/arlo-initramfs-min.cpio.gz",addr=0x44200000,force-raw=on \
  -device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=0 \
  > /dev/null 2>&1
echo "qemu rc=$?"
echo
echo "=== exception log: counts by type ==="
grep -oE 'Taking exception [0-9]+ \[[^]]*\]' "$LOGD" 2>/dev/null | sort | uniq -c | sort -rn | head
echo
echo "=== first 3 exceptions in full ==="
grep -n -A6 'Taking exception' "$LOGD" 2>/dev/null | head -40
echo
echo "=== any unassigned/abort memory access QEMU noticed ==="
grep -iE 'unassigned|abort|translation|invalid' "$LOGD" 2>/dev/null | head -8 || echo "(none)"

echo
echo "=== disassembly around the PC run 08 was stuck at (0x41055590) ==="
OFF=$((0x41055590 - 0x40080000))
START=$((OFF - 0x40))
dd if="$IMG" of=/tmp/stuck.bin bs=1 skip=$START count=160 status=none
aarch64-linux-gnu-objdump -D -b binary -m aarch64 --adjust-vma=$((0x40080000 + START)) /tmp/stuck.bin | tail -32
