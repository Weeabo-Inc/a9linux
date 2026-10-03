#!/bin/bash
# Runs INSIDE the a9build container. Cross-checks claimed-symbol names against
# the tree's own Kconfig, so we never trust a grep for a symbol that may not exist.
set -u
cd /build/linux-a9 || exit 9

echo "=== 1. Apple UART: what is the REAL symbol? ==="
grep -rn "Apple on-chip serial\|apple-s5l-uart\|SERIAL_APPLE" drivers/tty/serial/Kconfig | sed -n '1,20p'
echo "--- the Kconfig block ---"
awk '/config SERIAL_APPLE$/{f=1} f{print} f&&/^$/{c++; if(c>1) exit}' drivers/tty/serial/Kconfig | sed -n '1,20p'
echo "--- driver file exists? ---"
ls -la drivers/tty/serial/apple-s5l-uart.c 2>&1
echo "--- is that symbol in .config AT ALL? ---"
grep -n "SERIAL_APPLE" .config || echo "NOT PRESENT IN .config"
echo "--- is the built-in object listed in the Makefile? ---"
grep -n "SERIAL_APPLE\|apple" drivers/tty/serial/Makefile

echo ""
echo "=== 2. Does anything bind 'simple-framebuffer'? ==="
grep -rn "simple-framebuffer" drivers/gpu/drm/tiny/simpledrm.c drivers/video/fbdev/simplefb.c drivers/firmware/sysfb.c 2>/dev/null | sed -n '1,20p'
echo "--- FB_SIMPLE / SYSFB_SIMPLEFB / DRM_SIMPLEDRM in .config ---"
grep -n -E "FB_SIMPLE|SYSFB|DRM_SIMPLEDRM|DRM_TINY" .config | sed -n '1,20p'

echo ""
echo "=== 3. spin-table with cpu-release-addr = 0 ==="
sed -n '1,120p' arch/arm64/kernel/cpu_ops.c | grep -n -A6 "spin_table" 
echo "--- spin_table release addr handling ---"
grep -n -B3 -A25 "spin_table_cpu_init" arch/arm64/kernel/smp_spin_table.c | sed -n '1,60p'

echo ""
echo "=== 4. VA_BITS options valid for 16K granule ==="
grep -n -A4 "config ARM64_VA_BITS" arch/arm64/Kconfig | sed -n '1,40p'
echo "--- choice entries ---"
awk '/choice$/{buf=""} {buf=buf"\n"$0} /endchoice/{if (buf ~ /ARM64_VA_BITS/) print buf}' arch/arm64/Kconfig | sed -n '1,60p'

echo ""
echo "=== 5. ARCH_APPLE Kconfig ==="
grep -n -A14 "^config ARCH_APPLE" arch/arm64/Kconfig.platforms

echo ""
echo "=== 6. Image header contract (what a9boot must honour) ==="
sed -n '1,60p' Documentation/arch/arm64/booting.rst | sed -n '1,60p'
echo "=== END ==="
