#!/bin/bash
# Runs INSIDE the a9build container.
# Re-derives .config deterministically from /build/config_16k and PROVES the
# 16K page size survived config resolution.
set -u
cd /build/linux-a9 || exit 9

echo "=== before ==="
ls -la .config
sha256sum .config

cp -a .config /build/config.before-derive

echo ""
echo "=== apply /build/config_16k verbatim ==="
cp -f /build/config_16k .config
sha256sum .config

echo ""
echo "=== make LLVM=1 ARCH=arm64 olddefconfig ==="
make LLVM=1 ARCH=arm64 olddefconfig 2>&1 | tail -n 40
echo "olddefconfig exit=$?"

echo ""
echo "=== derived .config ==="
ls -la .config
sha256sum .config

echo ""
echo "===== PAGE-SIZE PROOF (post-resolution) ====="
echo "CONFIG_ARM64_16K_PAGES=y       -> $(grep -c '^CONFIG_ARM64_16K_PAGES=y$' .config)"
echo "CONFIG_ARM64_4K_PAGES=y        -> $(grep -c '^CONFIG_ARM64_4K_PAGES=y$' .config)   (MUST be 0)"
echo "CONFIG_ARM64_64K_PAGES=y       -> $(grep -c '^CONFIG_ARM64_64K_PAGES=y$' .config)  (MUST be 0)"
echo "CONFIG_PAGE_SIZE_16KB=y        -> $(grep -c '^CONFIG_PAGE_SIZE_16KB=y$' .config)"
echo "CONFIG_PAGE_SIZE_4KB=y         -> $(grep -c '^CONFIG_PAGE_SIZE_4KB=y$' .config)   (MUST be 0)"
echo "--- the raw lines ---"
grep -n -E '^CONFIG_ARM64_(4K|16K|64K)_PAGES|^# CONFIG_ARM64_(4K|16K|64K)_PAGES|^CONFIG_PAGE_SIZE_(4KB|16KB|64KB)|^# CONFIG_PAGE_SIZE_' .config
echo "--- resolved PAGE_SHIFT / page size macros ---"
make LLVM=1 ARCH=arm64 --no-print-directory -s kernelversion 2>/dev/null

echo ""
echo "=== boot-critical resolved values ==="
for k in CONFIG_ARCH_APPLE CONFIG_ARM64_VA_BITS CONFIG_ARM64_PA_BITS CONFIG_RELOCATABLE \
         CONFIG_ARM64_ERRATUM_APPLE_FUSION CONFIG_CMDLINE CONFIG_INITRAMFS_SOURCE \
         CONFIG_EFI CONFIG_EFI_STUB CONFIG_MODULES CONFIG_DEBUG_INFO CONFIG_DEBUG_INFO_BTF \
         CONFIG_KERNEL_GZIP CONFIG_SMP CONFIG_ARM64_ACPI_PARKING_PROTOCOL \
         CONFIG_ARM_ARCH_TIMER CONFIG_APPLE_AIC CONFIG_SERIAL_APPLE_CONSOLE \
         CONFIG_ARM_APPLE_SOC_CPUFREQ CONFIG_ARM64_SW_TTBR0_PAN CONFIG_ARM64_PAN \
         CONFIG_ARM64_TLB_RANGE CONFIG_HARDEN_BRANCH_PREDICTOR CONFIG_WERROR; do
  printf '%-42s %s\n' "$k" "$(grep -E "^$k=|^# $k is not set" .config | head -n 1)"
done

echo ""
echo "=== diff: previous .config -> newly derived .config ==="
diff /build/config.before-derive .config && echo "(identical)"
echo "(diff exit=$?)"
echo "=== END ==="
