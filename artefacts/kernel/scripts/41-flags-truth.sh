#!/bin/bash
# Runs INSIDE the a9build container.
# Establishes the AUTHORITATIVE meaning of the Image flags field from the tree's
# own documentation and source, instead of a recalled constant.
set -u
cd /build/linux-a9 || exit 9

echo "############ 1. The Image header described by THIS tree's own doc ############"
awk '/^3\. Decompress the kernel image/,/^4\. Call the kernel image/' Documentation/arch/arm64/booting.rst | sed -n '1,80p'

echo ""
echo "############ 2. Search the whole doc for the flags bit definitions ############"
grep -n -A30 "flags.*Kernel flags" Documentation/arch/arm64/booting.rst | sed -n '1,60p'

echo ""
echo "############ 3. How the kernel actually COMPUTES _kernel_flags_le ############"
grep -rn "_kernel_flags_le\|KERNEL_FLAGS\|IMAGE_FLAGS" arch/arm64/kernel/head.S arch/arm64/kernel/image.h 2>/dev/null | sed -n '1,20p'
echo "--- the definition in image.h ---"
sed -n '1,120p' arch/arm64/kernel/image.h | grep -n -B4 -A22 "FLAGS"

echo ""
echo "############ 4. ARM64_IMAGE_MAGIC + how flags are emitted (head.S) ############"
grep -n -B12 -A6 "ARM64_IMAGE_MAGIC" arch/arm64/kernel/head.S

echo ""
echo "############ 5. CONFIG_ARM64_PAGE_SHIFT (the value PAGE_SHIFT actually gets) ############"
grep -n "ARM64_PAGE_SHIFT\|ARM64_16K_PAGES\|PAGE_SIZE_16KB" include/generated/autoconf.h
echo "--- page-def.h / page.h wiring ---"
grep -rn "PAGE_SHIFT" arch/arm64/include/asm/page-def.h
echo "--- Kconfig derivation of ARM64_PAGE_SHIFT ---"
grep -n -B2 -A18 "^config ARM64_PAGE_SHIFT" arch/arm64/Kconfig

echo ""
echo "############ 6. Linker max-page-size (arm64 Makefile) ############"
grep -n "max-page-size\|PAGE_SHIFT\|KBUILD_LDFLAGS" arch/arm64/Makefile | sed -n '1,20p'

echo ""
echo "############ 7. Binary-level probe: is 16K baked into the code? ############"
echo "(PAGE_SHIFT=14 => 0x4000;  a 4K kernel would use 0x1000 throughout)"
echo "--- SWAPPER_DIR_SIZE / early page table constants via System.map ---"
grep -E " (swapper_pg_dir|idmap_pg_dir|reserved_pg_dir|init_pg_dir|_end|__bss_stop)$" System.map | sed -n '1,12p'
echo "--- alignment of swapper_pg_dir (must be a full page = 0x4000 for 16K) ---"
python3 - <<'PY'
import subprocess, re
out = subprocess.run(['llvm-nm','--numeric-sort','vmlinux'],capture_output=True,text=True).stdout
want = {'swapper_pg_dir':'swapper page tables',
        'init_pg_dir':'init page tables',
        'idmap_pg_dir':'idmap page tables',
        'reserved_pg_dir':'reserved page tables'}
for line in out.splitlines():
    parts = line.split()
    if len(parts) >= 3 and parts[2] in want:
        a = int(parts[0],16)
        print(f"{parts[2]:<18} @ 0x{a:x}  low12=0x{a & 0xfff:x}  low14=0x{a & 0x3fff:x}  {'PAGE-ALIGNED to 16K' if a % 0x4000 == 0 else ('aligned 4K only' if a % 0x1000==0 else 'not page aligned')}")
PY
echo "=== END ==="
