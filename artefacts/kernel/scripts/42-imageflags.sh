#!/bin/bash
# Runs INSIDE the a9build container.
# Confirms the ACTUAL shift constants behind the Image flags field, so the
# 16K proof does not rest on a script default.
set -u
cd /build/linux-a9 || exit 9

echo "=== arch/arm64/include/asm/image.h ==="
cat arch/arm64/include/asm/image.h

echo ""
echo "=== the ARM64_IMAGE_FLAG_*_SHIFT constants ==="
grep -rn "ARM64_IMAGE_FLAG" arch/arm64/include/asm/image.h include/linux/ 2>/dev/null | sed -n '1,30p'

echo ""
echo "=== recompute the expected flags with the REAL shift names ==="
python3 - <<'PY'
import re
defs = {}
for path in ('arch/arm64/include/asm/image.h',):
    for line in open(path):
        m = re.match(r'#define\s+(ARM64_IMAGE_FLAG_\w+)\s+(0x[0-9a-fA-F]+|\d+)', line.strip())
        if m: defs[m.group(1)] = int(m.group(2), 0)
print("constants found:", {k: hex(v) for k, v in defs.items()})
PAGE_SHIFT = 14                      # from CONFIG_ARM64_16K_PAGES=y
page_field = (PAGE_SHIFT - 10) // 2  # image.h: __HEAD_FLAG_PAGE_SIZE
print(f"PAGE_SHIFT={PAGE_SHIFT} -> __HEAD_FLAG_PAGE_SIZE={page_field}")
be_shift  = defs.get('ARM64_IMAGE_FLAG_BE_SHIFT')
ps_shift  = defs.get('ARM64_IMAGE_FLAG_PAGE_SIZE_SHIFT')
pb_shift  = defs.get('ARM64_IMAGE_FLAG_PHYS_BASE_SHIFT')
print(f"shifts: BE={be_shift} PAGE_SIZE={ps_shift} PHYS_BASE={pb_shift}")
be_val = defs.get('ARM64_IMAGE_FLAG_LE', 0)   # !CONFIG_CPU_BIG_ENDIAN -> LE value
exp = (be_val << be_shift) | (page_field << ps_shift) | (1 << pb_shift)
print(f"expected flags = 0x{exp:x}")
print(f"observed flags = 0xc")
print("MATCH" if exp == 0xc else "*** MISMATCH - investigate ***")
print()
print("sanity: what a 4K kernel would emit = 0x%x ; 64K = 0x%x" % (
    (be_val << be_shift) | (((12-10)//2) << ps_shift) | (1 << pb_shift),
    (be_val << be_shift) | (((16-10)//2) << ps_shift) | (1 << pb_shift)))
PY
echo "=== END ==="
