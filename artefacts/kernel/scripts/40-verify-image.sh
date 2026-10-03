#!/bin/bash
# Runs INSIDE the a9build container.
# FINAL ARTEFACT VERIFICATION.
#
# Design rule: this script does not hardcode any magic constant it could read.
# The expected Image `flags` value is DERIVED from the tree's own
# arch/arm64/kernel/image.h macros, and cross-checked at three independent
# levels (config -> generated header -> linked binary layout).
set -u
cd /build/linux-a9 || exit 9

IMG=arch/arm64/boot/Image
IMGZ=arch/arm64/boot/Image.gz
DTB=arch/arm64/boot/dts/apple/s8003-n69.dtb

echo "########################################################################"
echo "# 1. AUTHORITATIVE definition of the Image flags field (tree source)   #"
echo "########################################################################"
sed -n '30,70p' arch/arm64/kernel/image.h

echo ""
echo "########################################################################"
echo "# 2. Decode the produced Image header against that definition          #"
echo "########################################################################"
python3 - "$IMG" <<'PY'
import struct, sys, os, re

# --- derive expectations from the tree instead of assuming them ---
cfg = open('.config').read()
def cfgval(name):
    m = re.search(r'^%s=(.*)$' % re.escape(name), cfg, re.M)
    return m.group(1).strip('"') if m else None
psym = {n: cfgval(n) for n in
        ('CONFIG_ARM64_4K_PAGES','CONFIG_ARM64_16K_PAGES','CONFIG_ARM64_64K_PAGES')}
PAGE_SHIFT = {'CONFIG_ARM64_4K_PAGES':12,'CONFIG_ARM64_16K_PAGES':14,
              'CONFIG_ARM64_64K_PAGES':16}
enabled = [k for k,v in psym.items() if v == 'y']
assert len(enabled) == 1, f"expected exactly one page-size option, got {psym}"
PAGE_SHIFT = PAGE_SHIFT[enabled[0]]
PAGE_SIZE  = 1 << PAGE_SHIFT

# image.h:  #define __HEAD_FLAG_PAGE_SIZE  ((PAGE_SHIFT - 10) / 2)
# image.h:  #define __HEAD_FLAG_BE / _PHYS_BASE  -> shifts 0 and 3 (read below)
shifts = {}
for line in open('arch/arm64/kernel/image.h'):
    m = re.match(r'#define\s+(__HEAD_FLAG_\w+)_SHIFT\s+(\d+)', line.strip())
    if m: shifts[m.group(1)] = int(m.group(2))
vals = {}
for line in open('arch/arm64/kernel/image.h'):
    m = re.match(r'#define\s+(__HEAD_FLAG_\w+)\s+(.+)', line.strip())
    if m and not m.group(1).endswith('_SHIFT'):
        expr = m.group(2).split('/*')[0].strip()
        try: vals[m.group(1)] = int(eval(expr, {'PAGE_SHIFT': PAGE_SHIFT}, {}))
        except Exception: pass

print(f"from .config : {enabled[0]}=y  ->  PAGE_SHIFT={PAGE_SHIFT}  PAGE_SIZE={PAGE_SIZE} (0x{PAGE_SIZE:x})")
print(f"image.h shifts: {shifts}")
print(f"image.h field values: {vals}")
exp_flags = 0
if '__HEAD_FLAG_BE' in vals:        exp_flags |= vals['__HEAD_FLAG_BE'] << shifts.get('__HEAD_FLAG_BE',0)
if '__HEAD_FLAG_PAGE_SIZE' in vals: exp_flags |= vals['__HEAD_FLAG_PAGE_SIZE'] << shifts.get('__HEAD_FLAG_PAGE_SIZE',1)
if '__HEAD_FLAG_PHYS_BASE' in vals: exp_flags |= vals['__HEAD_FLAG_PHYS_BASE'] << shifts.get('__HEAD_FLAG_PHYS_BASE',3)
print(f"EXPECTED flags = 0x{exp_flags:x}  (bit0 BE=0, bits1-2 page field={vals.get('__HEAD_FLAG_PAGE_SIZE')}, bit3 phys_base={vals.get('__HEAD_FLAG_PHYS_BASE')})")

d = open(sys.argv[1],'rb').read(4096)
size = os.path.getsize(sys.argv[1])
code0, code1 = struct.unpack_from('<II', d, 0)
text_offset, image_size, flags = struct.unpack_from('<QQQ', d, 8)
magic, = struct.unpack_from('<I', d, 56)
print()
print(f"file         : {sys.argv[1]}")
print(f"file size    : {size} bytes (0x{size:x})")
print(f"code0        : 0x{code0:08x}")
print(f"code1        : 0x{code1:08x}")
print(f"text_offset  : 0x{text_offset:x} ({text_offset})")
print(f"image_size   : 0x{image_size:x} ({image_size})")
print(f"flags        : 0x{flags:x}")
print(f"magic        : 0x{magic:08x}  {'OK (\"ARM\\\\x64\")' if magic==0x644d5241 else '*** BAD MAGIC ***'}")
print()
print(f"observed bits1-2 page field : {(flags >> 1) & 3}")
print(f"expected bits1-2 page field : {vals.get('__HEAD_FLAG_PAGE_SIZE')}")
ok_page  = ((flags >> 1) & 3) == vals.get('__HEAD_FLAG_PAGE_SIZE')
ok_be    = (flags & 1) == 0
ok_magic = magic == 0x644d5241
# _kernel_size_le = _end - _text, and .bss is NOBITS so NOT in the file:
# image_size >= file size is the correct relationship, not equality.
ok_size  = image_size >= size
print()
print(f">>> [A] header page field matches image.h  : {'PASS' if ok_page else 'FAIL'}")
print(f">>> [B] little-endian (bit0 == 0)          : {'PASS' if ok_be else 'FAIL'}")
print(f">>> [C] ARM64 magic                        : {'PASS' if ok_magic else 'FAIL'}")
print(f">>> [D] image_size >= file size (.bss)      : {'PASS' if ok_size else 'FAIL'}"
      f"   (image_size - file = {image_size-size} bytes of NOBITS)")
print(f">>> [E] flags == expected 0x{exp_flags:x}             : {'PASS' if flags==exp_flags else 'FAIL (got 0x%x)'%flags}")
print()
verdict = ok_page and ok_be and ok_magic and ok_size and flags==exp_flags
print(">>> PAGE-SIZE VERDICT:", "16K CONFIRMED IN THE ARTEFACT" if (ok_page and flags==exp_flags) else "*** NOT PROVEN ***")
PY

echo ""
echo "########################################################################"
echo "# 3. Independent check: page-table layout baked into the linked binary #"
echo "#    (SWAPPER_DIR_SIZE == PAGE_SIZE; 4K pages would give 0x1000 stride) #"
echo "########################################################################"
python3 - <<'PY'
import subprocess
out = subprocess.run(['llvm-nm','--numeric-sort','vmlinux'],capture_output=True,text=True).stdout
sym = {}
for line in out.splitlines():
    p = line.split()
    if len(p) >= 3: sym[p[2]] = int(p[0],16)
want = ['idmap_pg_dir','reserved_pg_dir','swapper_pg_dir','init_pg_dir']
for w in want:
    if w in sym:
        a = sym[w]
        print(f"{w:<16} @ 0x{a:x}  16K-aligned={'YES' if a % 0x4000 == 0 else 'NO'}"
              f"  4K-aligned={'YES' if a % 0x1000 == 0 else 'NO'}")
present = [w for w in want if w in sym]
if 'swapper_pg_dir' in sym and 'reserved_pg_dir' in sym:
    stride = sym['swapper_pg_dir'] - sym['reserved_pg_dir']
    print(f"stride reserved_pg_dir -> swapper_pg_dir = 0x{stride:x} "
          f"({'== 0x4000 == 16K PAGE_SIZE' if stride == 0x4000 else 'NOT 16K'})")
# _end alignment
if '_end' in sym:
    print(f"_end = 0x{sym['_end']:x}  (16K-aligned={'YES' if sym['_end'] % 0x4000==0 else 'NO'})")
PY

echo ""
echo "########################################################################"
echo "# 4. Generated header the C code actually compiled against             #"
echo "########################################################################"
grep -n "CONFIG_ARM64_16K_PAGES\|CONFIG_PAGE_SIZE_16KB\|CONFIG_ARM64_4K_PAGES\|CONFIG_PAGE_SIZE_4KB" include/generated/autoconf.h

echo ""
echo "########################################################################"
echo "# 5. Image.gz integrity                                                #"
echo "########################################################################"
gzip -dc "$IMGZ" > /tmp/Image.ungz
if cmp -s /tmp/Image.ungz "$IMG"; then
  echo ">>> PASS: Image.gz decompresses byte-identically to Image ($(stat -c %s /tmp/Image.ungz) bytes)"
else
  echo ">>> FAIL: Image.gz != Image"; cmp /tmp/Image.ungz "$IMG" | head -n 3
fi

echo ""
echo "########################################################################"
echo "# 6. Build identity embedded in the artefact                           #"
echo "########################################################################"
strings "$IMG" | grep -m1 -E "^Linux version " || echo "(no version string)"
echo "kernelrelease: $(cat include/config/kernel.release)"
echo "clang        : $(clang --version | head -n 1)"
echo "ld.lld       : $(ld.lld --version | head -n 1)"
echo "llvm-ar      : $(llvm-ar --version | head -n 1)"
echo "make         : $(make --version | head -n 1)"

echo ""
echo "########################################################################"
echo "# 7. Artefact sizes + hashes (final, post-clean-build)                 #"
echo "########################################################################"
ls -la "$IMG" "$IMGZ" "$DTB"
sha256sum "$IMG" "$IMGZ" "$DTB"
echo "--- governing .config ---"
sha256sum .config

echo ""
echo "########################################################################"
echo "# 8. Warning / error census                                            #"
echo "########################################################################"
LOG=${KBUILD_LOG:-/build/kbuild-clean.log}
echo "log: $LOG"
echo "lines=$(wc -l < $LOG)  CC=$(grep -c '^  CC' $LOG)  LD=$(grep -c '^  LD' $LOG)"
echo "warnings: $(grep -c -i 'warning:' $LOG)   errors: $(grep -c -i 'error:' $LOG)"
echo "--- any warning lines ---"
grep -n -i 'warning:' "$LOG" | head -n 40
echo "=== END ==="
