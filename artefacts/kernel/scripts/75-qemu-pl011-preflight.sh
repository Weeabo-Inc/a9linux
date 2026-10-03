#!/bin/bash
# Runs INSIDE the a9build container. Pre-flight for the QEMU-only PL011 variant.
# Answers: is PL011 already on? what does enabling it actually pull in?
set -u
cd /build/linux-a9 || exit 9

echo "############ 1. PL011 / AMBA state in the SHIPPING config ############"
for k in CONFIG_ARM_AMBA CONFIG_SERIAL_AMBA_PL011 CONFIG_SERIAL_AMBA_PL011_CONSOLE \
         CONFIG_SERIAL_AMBA_PL010 CONFIG_SERIAL_AMBA_PL010_CONSOLE \
         CONFIG_ARM_GIC CONFIG_ARM_GIC_V3 CONFIG_ARM_GIC_V3_ITS \
         CONFIG_ARM_ARCH_TIMER CONFIG_ARM_PSCI_FW CONFIG_SERIAL_EARLYCON \
         CONFIG_SERIAL_EARLYCON_ARM_SEMIHOST CONFIG_TTY CONFIG_VT CONFIG_VT_CONSOLE; do
  line=$(grep -E "^$k=|^# $k is not set" .config | head -n 1)
  if [ -n "$line" ]; then
    printf '  %-42s %s\n' "$k" "$line"
  else
    printf '  %-42s [ABSENT from .config]\n' "$k"
  fi
done

echo
echo "############ 2. What does the Kconfig say drives PL011? ############"
grep -n -B4 -A14 '^config SERIAL_AMBA_PL011$' drivers/tty/serial/Kconfig
echo "  --- console option ---"
grep -n -A10 '^config SERIAL_AMBA_PL011_CONSOLE$' drivers/tty/serial/Kconfig
echo "  --- ARM_AMBA symbol ---"
grep -rn -A6 '^config ARM_AMBA$' drivers/amba/Kconfig

echo
echo "############ 3. Is ARM_AMBA selected by anything already enabled? ############"
grep -rn 'select ARM_AMBA' arch/arm64/Kconfig.platforms drivers/ 2>/dev/null | head -n 12
echo "  --- which of those platform symbols are on? ---"
for k in CONFIG_ARCH_VEXPRESS CONFIG_ARCH_QCOM CONFIG_ARCH_BCM CONFIG_ARCH_MXC CONFIG_ARCH_HISI CONFIG_ARCH_SYNQUACER CONFIG_ARCH_SPARX5 CONFIG_ARCH_APPLE; do
  line=$(grep -E "^$k=|^# $k is not set" .config | head -n 1)
  printf '  %-24s %s\n' "$k" "${line:-[ABSENT]}"
done

echo
echo "############ 4. Does scripts/config exist (for a precise, auditable delta)? ############"
ls -la scripts/config
echo "  --- its --help, to confirm the flags I intend to use ---"
scripts/config --help 2>&1 | grep -E '^\s+-[a-zA-Z],' | head -n 20

echo
echo "############ 5. Out-of-tree support check: does kbuild allow O= here? ############"
echo "  (the shipping tree has in-tree build output, so this is expected to be refused)"
echo "  in-tree .config present      : $([ -f .config ] && echo yes || echo no)"
echo "  in-tree auto.conf present    : $([ -f include/config/auto.conf ] && echo yes || echo no)"
echo "  git status (should be clean) : $(git status --porcelain 2>/dev/null | wc -l) modified"

echo
echo "############ 6. QEMU virt device-tree serial node name (what console= expects) ############"
grep -rn 'pl011\|ttyAMA' arch/arm64/boot/dts/arm/ 2>/dev/null | head -n 6
echo "=== END ==="
