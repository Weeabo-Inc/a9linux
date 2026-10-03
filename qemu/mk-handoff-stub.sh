#!/usr/bin/env bash
# a9linux/qemu/mk-handoff-stub.sh — assemble handoff-stub.S into a raw binary.
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
mkdir -p "$STAGE/inputs" "$STAGE/work"
cd "$STAGE/work"
AS=aarch64-linux-gnu-as
LD=aarch64-linux-gnu-ld
OC=aarch64-linux-gnu-objcopy
command -v "$AS" >/dev/null || { echo "FATAL: $AS missing (apt install binutils-aarch64-linux-gnu)" >&2; exit 1; }

# Load map — keep in step with run-stub.sh.
#
# The hard constraint is NOT the address of the Image but the address of
# everything else: the arm64 kernel clears its own .bss in __primary_switched,
# BEFORE setup_arch reads the DTB. This Ubuntu Image reports 23104K code +
# 16036K rodata + 12224K init + 5192K rwdata + 1233K bss, i.e. ~59MB from
# 0x40080000 -> bss runs to about 0x438e8000. An earlier version of this map put
# the DTB at 0x43900000 and the initramfs at 0x43a00000: the kernel zeroed both
# and hung with no console output whatsoever. Everything the loader owns now
# sits at 0x44000000 or above, clear of the image.
STUB_BASE=0x44000000
MAILBOX=0x44004000
STACK=0x44008000
DTB=0x44100000
IMAGE=0x40080000

"$AS" --defsym STUB_BASE=$STUB_BASE --defsym MAILBOX=$MAILBOX --defsym STACK=$STACK \
      --defsym DTB=$DTB --defsym IMAGE=$IMAGE -o handoff-stub.o "$SCOPE/handoff-stub.S"
"$LD" -Ttext=$STUB_BASE -e _start -o handoff-stub.elf handoff-stub.o
"$OC" -O binary handoff-stub.elf handoff-stub.bin
cp -f handoff-stub.bin "$STAGE/inputs/handoff-stub.bin"
cp -f "$SCOPE/handoff-stub.S" "$STAGE/inputs/handoff-stub.S"

echo "load map  : stub=$STUB_BASE mailbox=$MAILBOX stack=$STACK dtb=$DTB image=$IMAGE"
echo "stub size : $(stat -c%s handoff-stub.bin) bytes (must fit below the mailbox)"
echo "stub sha256: $(sha256sum handoff-stub.bin | cut -d' ' -f1)"
echo "--- disassembly of the hand-off tail (registers set immediately before the jump) ---"
aarch64-linux-gnu-objdump -d handoff-stub.elf | sed -n '/<primary>:/,/^$/p' | tail -12
echo "--- mailbox spin loop ---"
aarch64-linux-gnu-objdump -d handoff-stub.elf | sed -n '/<parked_cpu>:/,/^$/p' | tail -14
