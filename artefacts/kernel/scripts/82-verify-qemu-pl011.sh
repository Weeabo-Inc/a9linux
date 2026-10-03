#!/bin/bash
# Runs INSIDE the a9build container.
# Verifies the QEMU-only PL011 variant: exact delta, 16K preservation, header,
# and that the SHIPPING tree was not touched.
set -u
W=/build/linux-a9-qemu
SRC=/build/linux-a9
cd "$W" || exit 9

echo "########################################################################"
echo "# A. THE EXACT CONFIG DELTA vs the shipping config.used               #"
echo "########################################################################"
echo "shipping config.used sha256 : $(sha256sum $SRC/.config | cut -d' ' -f1)"
echo "base copy in variant tree   : $(sha256sum .config.base | cut -d' ' -f1)"
echo "variant config sha256       : $(sha256sum .config | cut -d' ' -f1)"
echo
echo "--- full diff (config.base  ->  variant .config) ---"
diff .config.base .config || true
echo
echo "--- symbols changed, counted by direction ---"
echo "  only in shipping (<) : $(diff .config.base .config | grep -c '^<')"
echo "  only in variant  (>) : $(diff .config.base .config | grep -c '^>')"
echo
echo "--- PL011-related symbols in the variant ---"
grep -n -E 'SERIAL_AMBA_PL011|SERIAL_CORE_CONSOLE|SERIAL_EARLYCON=|ARM_AMBA' .config

echo
echo "########################################################################"
echo "# B. 16K GRANULE PRESERVED IN THE VARIANT?                             #"
echo "########################################################################"
grep -n -E '^CONFIG_ARM64_(4K|16K|64K)_PAGES|^# CONFIG_ARM64_(4K|16K|64K)_PAGES|^CONFIG_PAGE_SIZE_' .config
echo "  16K=y count      : $(grep -c '^CONFIG_ARM64_16K_PAGES=y$' .config)   (expect 1)"
echo "  4K=y count       : $(grep -c '^CONFIG_ARM64_4K_PAGES=y$' .config)   (expect 0)"
echo "  64K=y count      : $(grep -c '^CONFIG_ARM64_64K_PAGES=y$' .config)   (expect 0)"
echo "  VA_BITS          : $(grep -E '^CONFIG_ARM64_VA_BITS=' .config)"

echo
echo "########################################################################"
echo "# C. THE VARIANT ARTEFACT'S OWN IMAGE HEADER                           #"
echo "########################################################################"
python3 - <<'PY'
import struct, os, re
p = 'arch/arm64/boot/Image'
d = open(p,'rb').read(4096)
size = os.path.getsize(p)
code0, code1 = struct.unpack_from('<II', d, 0)
text_offset, image_size, flags = struct.unpack_from('<QQQ', d, 8)
magic, = struct.unpack_from('<I', d, 56)
# expected, derived from the tree's own macros
exp = (0 << 0) | (2 << 1) | (1 << 3)   # LE, PAGE_SIZE_16K==2 at shift 1, PHYS_BASE==1 at shift 3
print(f"file        : {p}")
print(f"file size   : {size} bytes")
print(f"text_offset : 0x{text_offset:x}   image_size: 0x{image_size:x} ({image_size})")
print(f"flags       : 0x{flags:x}")
print(f"magic       : 0x{magic:08x}  {'OK (ARM\\\\x64)' if magic==0x644d5241 else 'BAD'}")
print(f"bits[2:1]   : {(flags >> 1) & 3}   (2 == ARM64_IMAGE_FLAG_PAGE_SIZE_16K)")
print(f"expected    : 0x{exp:x}")
print()
print(">>> PAGE SIZE:", "16K CONFIRMED (flags == 0xc)" if flags == exp else f"*** NOT 16K (flags=0x{flags:x}) ***")
print(">>> image_size >= file size (.bss NOBITS):", "PASS" if image_size >= size else "FAIL")
PY

echo
echo "--- page-table stride, header-independent 16K check ---"
python3 - <<'PY'
import subprocess
out = subprocess.run(['llvm-nm','--numeric-sort','vmlinux'],capture_output=True,text=True).stdout
sym = {p[2]: int(p[0],16) for p in (l.split() for l in out.splitlines()) if len(p) >= 3}
for w in ('reserved_pg_dir','swapper_pg_dir'):
    if w in sym: print(f"  {w:<16} @ 0x{sym[w]:x}  16K-aligned={'YES' if sym[w] % 0x4000 == 0 else 'NO'}")
if 'reserved_pg_dir' in sym and 'swapper_pg_dir' in sym:
    print(f"  stride = 0x{sym['swapper_pg_dir']-sym['reserved_pg_dir']:x} ({'== 16K PAGE_SIZE' if sym['swapper_pg_dir']-sym['reserved_pg_dir']==0x4000 else 'NOT 16K'})")
PY

echo
echo "########################################################################"
echo "# D. BUILD IDENTITY + HASHES                                          #"
echo "########################################################################"
cat include/generated/utsversion.h
echo "kernelrelease: $(cat include/config/kernel.release)"
echo
echo "--- variant artefact ---"
ls -la arch/arm64/boot/Image
sha256sum arch/arm64/boot/Image
echo "--- variant config ---"
sha256sum .config

echo
echo "########################################################################"
echo "# E. THE SHIPPING TREE MUST BE UNTOUCHED                              #"
echo "########################################################################"
echo "shipping .config sha256 : $(sha256sum $SRC/.config | cut -d' ' -f1)"
echo "  expected              : eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041"
echo "shipping Image  sha256 : $(sha256sum $SRC/arch/arm64/boot/Image | cut -d' ' -f1)"
echo "  expected              : 39a270676141f42575cbadffbac085cc120aa1e0f6e61af0b6db8ad5b0c7e228"
echo "shipping Image  size   : $(stat -c %s $SRC/arch/arm64/boot/Image)"
echo
echo "--- do the two kernels differ? (they MUST) ---"
if cmp -s $SRC/arch/arm64/boot/Image arch/arm64/boot/Image; then
  echo ">>> PROBLEM: variant Image is identical to the shipping Image"
else
  echo ">>> OK: variant and shipping Images are different files (different hashes)"
fi
echo "=== END ==="
