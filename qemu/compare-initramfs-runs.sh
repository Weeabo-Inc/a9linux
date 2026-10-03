#!/usr/bin/env bash
# a9linux/qemu/compare-initramfs-runs.sh — why did min reach a shell while dash and
# debian stopped? Same kernel, same console, same command line: the variable is the
# initramfs, so compare the three logs at the point they diverge.
set -uo pipefail
L=/opt/a9qemu/logs
for n in 13-variant-virt-dt 16-variant-dash 15-variant-debian-initrd; do
  echo "=============================================================================="
  echo "$n   bytes=$(stat -c%s "$L/$n.log")  sha=$(grep -a initrd_sha256 "$L/$n.meta.txt" 2>/dev/null | cut -c1-60)"
  echo "  --- last 8 non-empty lines ---"
  tr -d '\r' < "$L/$n.log" | grep -a . | tail -8 | sed 's/^/  | /'
  echo "  --- first userland-ish line, if any ---"
  tr -d '\r' < "$L/$n.log" | grep -a -m3 -E 'arlo|registering|Run /init|No working init|panic|getty|login|Shell' | sed 's/^/  > /'
  echo "  --- any tty/console device that got a driver ---"
  tr -d '\r' < "$L/$n.log" | grep -a -E 'ttyAMA|pl011|console \[|printk: console' | head -4 | sed 's/^/  * /'
done
