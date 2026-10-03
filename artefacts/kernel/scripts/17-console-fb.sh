#!/bin/bash
# Runs INSIDE the a9build container. Precise console + framebuffer binding audit.
set -u
cd /build/linux-a9 || exit 9

echo "=== A. what compatible does serial@20a0c0000 have? ==="
dtc -I dtb -O dts arch/arm64/boot/dts/apple/s8003-n69.dtb 2>/dev/null > /tmp/n69.dts
awk '/serial@20a0c0000/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts | sed -n '1,20p'

echo ""
echo "=== B. which driver claims apple,s5l-uart ? ==="
grep -rn "apple,s5l-uart" drivers/tty/serial/*.c drivers/tty/serial/*.h 2>/dev/null | sed -n '1,10p'
echo "--- samsung_tty Kconfig ---"
grep -n -A8 "^config SERIAL_SAMSUNG$" drivers/tty/serial/Kconfig
echo "--- relevant .config lines ---"
grep -n -E "SERIAL_SAMSUNG|SERIAL_S5L|SERIAL_APPLE" .config || echo "NONE OF SERIAL_SAMSUNG / SERIAL_S5L / SERIAL_APPLE IN .config"
echo "--- is samsung_tty built? ---"
grep -n -i "samsung" drivers/tty/serial/Makefile

echo ""
echo "=== C. framebuffer: can ANY enabled driver bind simple-framebuffer? ==="
echo "--- simpledrm of_match_table ---"
grep -n -B2 -A12 "of_match_table\|static const struct platform_device_id\|\.name.*simpledrm" drivers/gpu/drm/tiny/simpledrm.c | sed -n '1,40p'
echo "--- sysfb: does it consider DT /chosen nodes? ---"
grep -n -E "of_|OF_|simple-framebuffer|screen_info|sysfb_create_simplefb|platform_device_register" drivers/firmware/sysfb.c | sed -n '1,40p'
echo "--- FB_SIMPLE Kconfig dependency ---"
grep -n -A10 "^config FB_SIMPLE" drivers/video/fbdev/Kconfig
echo "--- SYSFB_SIMPLEFB Kconfig ---"
grep -n -A12 "^config SYSFB_SIMPLEFB" drivers/firmware/Kconfig
echo "--- all framebuffer-capable symbols in .config ---"
grep -n -E "^CONFIG_(FB|FB_SIMPLE|DRM|DRM_SIMPLEDRM|SYSFB|SYSFB_SIMPLEFB|DRM_SYSFB_HELPER)" .config | sed -n '1,30p'
echo "--- of_platform populate of /chosen children? ---"
grep -rn "of_platform_default_populate\|of_platform_populate" drivers/of/platform.c | sed -n '1,10p'
grep -n "chosen" drivers/of/platform.c | sed -n '1,10p'

echo ""
echo "=== D. VA_BITS default block ==="
sed -n '1582,1600p' arch/arm64/Kconfig
echo "=== END ==="
