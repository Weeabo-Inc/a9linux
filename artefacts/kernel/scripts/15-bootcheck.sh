#!/bin/bash
# Runs INSIDE the a9build container. Boot-readiness audit of the built DTB
# against what the kernel actually supports.
#
# NOTE ON SYMBOL NAMES (corrected 2026-10-03): an earlier revision of this
# script grepped for CONFIG_SERIAL_APPLE / CONFIG_SERIAL_8250_APPLE /
# CONFIG_DRM_SIMPLE. NONE OF THOSE SYMBOLS EXIST in this tree, so the check
# could report a confident false "no console support". The Apple s5l-uart is
# driven by the Samsung-derived driver:
#     drivers/tty/serial/samsung_tty.c  .compatible = "apple,s5l-uart"
#     CONFIG_SERIAL_SAMSUNG / CONFIG_SERIAL_SAMSUNG_CONSOLE
# Every symbol below is checked against the tree's Kconfig, and the script
# reports MISSING-SYMBOL explicitly rather than printing an empty string.
set -u
cd /build/linux-a9 || exit 9
DTB=arch/arm64/boot/dts/apple/s8003-n69.dtb
dtc -I dtb -O dts "$DTB" 2>/dev/null > /tmp/n69.dts

# Report a symbol's state, distinguishing "not in .config at all" from "=n".
# A symbol absent from .config entirely means it does not exist in this tree
# (or its dependency is unmet) -- never treat that as "=n".
probe() {
  local k="$1" line
  line=$(grep -E "^$k=|^# $k is not set" .config | head -n 1)
  if [ -n "$line" ]; then
    printf '  %-42s %s\n' "$k" "$line"
  else
    if grep -rq "^config ${k#CONFIG_}" --include=Kconfig* . 2>/dev/null; then
      printf '  %-42s [absent from .config; symbol EXISTS in Kconfig - dependency unmet]\n' "$k"
    else
      printf '  %-42s [SYMBOL DOES NOT EXIST in this tree]\n' "$k"
    fi
  fi
}

echo "=== aliases (chosen stdout-path = serial0 needs this) ==="
awk '/aliases \{/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts

echo ""
echo "=== serial@20a0c0000 - the console the DT points at ==="
awk '/serial@20a0c0000/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts | sed -n '1,20p'

echo ""
echo "=== CONSOLE driver support (corrected symbol names) ==="
for k in CONFIG_SERIAL_SAMSUNG CONFIG_SERIAL_SAMSUNG_CONSOLE CONFIG_SERIAL_SAMSUNG_UARTS \
         CONFIG_SERIAL_APPLE CONFIG_SERIAL_8250 CONFIG_SERIAL_8250_APPLE; do probe "$k"; done
echo "  --- evidence the s5l-uart is really handled by samsung_tty ---"
grep -n 'apple,s5l-uart' drivers/tty/serial/samsung_tty.c
grep -n 'OF_EARLYCON_DECLARE' drivers/tty/serial/samsung_tty.c
echo "  --- driver object registered by the Makefile ---"
grep -n 'samsung_tty' drivers/tty/serial/Makefile

echo ""
echo "=== cpus: enable-method ==="
grep -n -E 'enable-method|cpu-release-addr|compatible = "apple,twister"' /tmp/n69.dts

echo ""
echo "=== /chosen bootargs present? ==="
grep -n 'bootargs' /tmp/n69.dts || echo "NO /chosen/bootargs -> kernel gets an EMPTY command line"

echo ""
echo "=== /memory size (decoded) ==="
awk '/memory@/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts

echo ""
echo "=== framebuffer node full ==="
awk '/framebuffer@0/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts

echo ""
echo "=== FRAMEBUFFER driver support (corrected symbol names) ==="
for k in CONFIG_DRM_SIMPLEDRM CONFIG_DRM_SYSFB_HELPER CONFIG_FB_SIMPLE CONFIG_SYSFB_SIMPLEFB \
         CONFIG_DRM_SIMPLE CONFIG_FB CONFIG_DRM; do probe "$k"; done
echo "  --- simpledrm DOES match the DT node (it moved to drivers/gpu/drm/sysfb/) ---"
grep -n 'of_device_id\|compatible = "simple-framebuffer"\|\.name.*=.*"simple-framebuffer"' \
     drivers/gpu/drm/sysfb/simpledrm.c | sed -n '1,10p'
echo "  --- and drivers/of/platform.c creates the device from /chosen ---"
grep -n 'of_get_compatible_child(of_chosen, "simple-framebuffer")' drivers/of/platform.c
echo "  --- FB_SIMPLE is force-hidden because DRM_SIMPLEDRM=y ---"
grep -n -A3 '^config FB_SIMPLE' drivers/video/fbdev/Kconfig

echo ""
echo "=== kernel-side support checks ==="
echo "--- apple DTS Makefile entry for n69 ---"
grep -n 's8003-n69' arch/arm64/boot/dts/apple/Makefile
echo "--- ARCH_APPLE Kconfig ---"
grep -n -A10 '^config ARCH_APPLE' arch/arm64/Kconfig.platforms
echo "=== END ==="
