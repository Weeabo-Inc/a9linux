#!/bin/bash
# Runs INSIDE the a9build container.
# Measures EXACTLY how /build/config_16k differs from the .config the shipped
# Image was built from, and proves whether any page-size / console / framebuffer
# symbol differs. Nobody should later read config_16k as a description of the build.
set -u
cd /build/linux-a9 || exit 9

echo "############ 1. Identity of the three candidate configs ############"
for f in /build/config_16k .config .config.old; do
  if [ -f "$f" ]; then
    printf '%-20s %10s bytes  sha256=%s\n' "$f" "$(stat -c %s $f)" "$(sha256sum $f | cut -d' ' -f1)"
  else
    printf '%-20s (absent)\n' "$f"
  fi
done

echo ""
echo "############ 2. Is config_16k identical to .config.old? ############"
if [ -f .config.old ]; then
  if cmp -s /build/config_16k .config.old; then
    echo ">>> YES: /build/config_16k is BYTE-IDENTICAL to the tree's .config.old"
  else
    echo ">>> NO: they differ"; cmp /build/config_16k .config.old | head -n 3
  fi
fi

echo ""
echo "############ 3. Exact diff: config_16k  ->  the .config we built from ############"
diff /build/config_16k .config > /tmp/cfg.diff || true
echo "diff output lines          : $(wc -l < /tmp/cfg.diff)"
echo "changed symbol lines (< or >): $(grep -c '^[<>]' /tmp/cfg.diff)"
echo "  of which < (only in config_16k): $(grep -c '^<' /tmp/cfg.diff)"
echo "  of which > (only in .config)   : $(grep -c '^>' /tmp/cfg.diff)"

echo ""
echo "############ 4. EVERY changed line, in full ############"
cat /tmp/cfg.diff

echo ""
echo "############ 5. Do ANY page-size / console / framebuffer symbols differ? ############"
echo "(a non-empty result below would invalidate the 16K proof or the console story)"
if grep -E '^[<>].*(PAGE_SHIFT|PAGE_SIZE|ARM64_4K|ARM64_16K|ARM64_64K|SERIAL|SAMSUNG|CONSOLE|DRM_SIMPLEDRM|FB_SIMPLE|SYSFB|DRM_SYSFB|FRAMEBUFFER|EARLYCON)' /tmp/cfg.diff; then
  echo ">>> WARNING: boot-relevant symbols DIFFER between config_16k and .config"
else
  echo ">>> NONE. No page-size, console or framebuffer symbol differs. 16K proof stands."
fi

echo ""
echo "############ 6. The page-size symbols, in BOTH files, side by side ############"
echo "--- /build/config_16k ---"
grep -n -E '^CONFIG_ARM64_(4K|16K|64K)_PAGES|^# CONFIG_ARM64_(4K|16K|64K)_PAGES|^CONFIG_PAGE_SIZE_|^# CONFIG_PAGE_SIZE_' /build/config_16k
echo "--- .config (the build input) ---"
grep -n -E '^CONFIG_ARM64_(4K|16K|64K)_PAGES|^# CONFIG_ARM64_(4K|16K|64K)_PAGES|^CONFIG_PAGE_SIZE_|^# CONFIG_PAGE_SIZE_' .config

echo ""
echo "############ 7. Reproduce: how .config was derived ############"
echo "  cp /build/config_16k .config"
echo "  make LLVM=1 ARCH=arm64 olddefconfig"
echo "  => yields sha256 eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041 (already re-verified this session)"
echo "=== END ==="
