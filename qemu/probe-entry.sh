#!/usr/bin/env bash
# a9linux/qemu/probe-entry.sh — work out how the kernel Image must be loaded.
#
# The Ubuntu arm64 Image begins with a PE/COFF (EFI-stub) header, so "put the
# file at RAM base + text_offset and jump to the start" is not obviously right.
# This probe reads the header fields and watches QEMU's own loader succeed, so
# the stub uses measured numbers instead of folklore.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
IMG="$STAGE/inputs/stock-Image"
DTB="$STAGE/inputs/n69-qemu-virt.dtb"
LOG="$STAGE/logs/probe-entry"

echo "=== [1] first 0x60 bytes of the Image ==="
xxd -l 96 "$IMG"
echo
echo "=== [2] arm64 image header fields (per booting.rst, 64 bytes at offset 0) ==="
python3 - "$IMG" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read(0x1000)
code0, code1, text_offset, image_size, flags = struct.unpack_from('<IIQQQ', b, 0)
print(f"  code0       = 0x{code0:08x}   ('MZ' magic is 0x5a4d)")
print(f"  code1       = 0x{code1:08x}")
print(f"  text_offset = 0x{text_offset:x}")
print(f"  image_size  = 0x{image_size:x}")
print(f"  flags       = 0x{flags:x}")
magic = struct.unpack_from('<I', b, 56)[0]
print(f"  magic@56    = 0x{magic:08x}  (want 0x644d5241 'ARM\\x64')")
pe = struct.unpack_from('<I', b, 0x3c)[0]
print(f"  e_lfanew    = 0x{pe:x}")
if pe and pe < 0x1000:
    sig = b[pe:pe+4]
    machine, nsec, _, _, _, optsz, chars = struct.unpack_from('<HHIIIHH', b, pe+4)
    entry = struct.unpack_from('<I', b, pe+0x28)[0]
    print(f"  PE sig      = {sig!r}  machine=0x{machine:04x} (0xaa64 = arm64) sections={nsec} optsize=0x{optsz:x}")
    print(f"  PE AddressOfEntryPoint = 0x{entry:x}")
    print(f"  => file offset of entry = 0x{optsz+0x18+0x28+pe-0x18-0x28+entry:x} (relative to image start, addr-form)")
PY
echo
echo "=== [3] what PC does QEMU hand control to? (its own -kernel loader) ==="
timeout -k 5 30 qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 1024 \
  -kernel "$IMG" -dtb "$DTB" -initrd "$STAGE/inputs/harness-selfinit.cpio.gz" \
  -append "console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1" \
  -display none -serial null -no-reboot -monitor none \
  -d cpu_reset,guest_errors -D "$LOG.int.log" > "$LOG.out.log" 2>&1
echo "exit=$? (124 = timed out, which is fine: we only want the reset record)"
echo "--- first CPU reset state lines ---"
grep -m3 -A3 'CPU Reset' "$LOG.int.log" 2>/dev/null | head -20
grep -m4 -E 'PC=|R15=' "$LOG.int.log" 2>/dev/null | head -4
echo "--- any guest errors ---"
grep -m5 -iE 'error|abort|unimp' "$LOG.int.log" 2>/dev/null | head -5 || echo "(none)"
