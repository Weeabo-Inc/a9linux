#!/usr/bin/env bash
# a9linux/qemu/console-audit.sh [config] — which console can this kernel drive?
#
# Matters because a kernel with no console driver for the machine it is running
# on produces ZERO output: no boot log, no panic, nothing. On QEMU virt the only
# UART is a PL011 at 0x9000000; on A9 it is an apple,s5l-uart at 0x20A0C000.
# If neither driver is built in, the harness is blind and says so.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
CFG="${1:-$W/a9linux/artefacts/kernel/config.used}"
[ -f "$CFG" ] || { echo "no config at $CFG" >&2; exit 1; }
echo "config: $CFG"
echo
echo "=== enabled (y) options matching SERIAL/HVC/VIRTIO/TTY/PRINTK/EARLYCON ==="
grep -E '^CONFIG_(SERIAL|HVC|VIRTIO|TTY|PRINTK|EARLYCON|EARLY_PRINTK)[A-Z0-9_]*=y' "$CFG" | sort
echo
echo "=== anything mentioning uart / pl011 / s5l / 8250 (set or not) ==="
grep -iE '^#? ?CONFIG_[A-Z0-9_]*(UART|PL011|S5L|8250|SEMIHOST)[A-Z0-9_]*' "$CFG" | sort
echo
echo "=== verdict ==="
if grep -q '^CONFIG_SERIAL_AMBA_PL011_CONSOLE=y' "$CFG"; then
  echo "  QEMU virt console : YES (PL011 driver + console built in)"
else
  echo "  QEMU virt console : NO  -> this kernel cannot write to QEMU virt's PL011."
  echo "                      With no earlycon match either, a QEMU run of THIS kernel"
  echo "                      produces no console output whatsoever."
fi
if grep -qE '^CONFIG_SERIAL_SAMSUNG(_CONSOLE)?=y' "$CFG"; then
  echo "  A9 serial console : YES -- and note the option name: apple,s5l-uart is driven by"
  echo "                      CONFIG_SERIAL_SAMSUNG (drivers/tty/serial/samsung_tty.c match"
  echo "                      table), NOT by a CONFIG_SERIAL_APPLE. A grep for the latter"
  echo "                      finds nothing and proves nothing."
else
  echo "  A9 serial console : NO  -> CONFIG_SERIAL_SAMSUNG missing; apple,s5l-uart has no driver."
fi
