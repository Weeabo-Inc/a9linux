#!/usr/bin/env bash
# a9linux/qemu/dt-explore.sh <dtb> — dump the interesting parts of a DTB using
# fdtget (robust) rather than text-scraping dtc output.
# fdtget syntax: fdtget [opts] <dtfile> <node> [property]
set -uo pipefail
DTB="$1"
echo "=== root children ==="
fdtget -l "$DTB" / 2>&1
echo "=== model / compatible ==="
echo "  model      = $(fdtget -t s "$DTB" / model 2>&1)"
echo "  compatible = $(fdtget -t s "$DTB" / compatible 2>&1)"
echo "=== aliases ==="
for a in $(fdtget -l "$DTB" /aliases 2>/dev/null); do
  printf '  %-10s = %s\n' "$a" "$(fdtget -t s "$DTB" /aliases "$a" 2>/dev/null)"
done
echo "=== chosen ==="
for p in $(fdtget -p "$DTB" /chosen 2>/dev/null); do
  printf '  chosen/%-14s = %s\n' "$p" "$(fdtget -t s "$DTB" /chosen "$p" 2>/dev/null || fdtget "$DTB" /chosen "$p" 2>/dev/null)"
done
echo "=== chosen/framebuffer0 (child of chosen) ==="
for p in $(fdtget -p "$DTB" /chosen/framebuffer@0 2>/dev/null); do
  printf '  %-10s = %s\n' "$p" "$(fdtget -t s "$DTB" /chosen/framebuffer@0 "$p" 2>/dev/null || fdtget "$DTB" /chosen/framebuffer@0 "$p" 2>/dev/null)"
done
echo "=== memory nodes ==="
for m in $(fdtget -l "$DTB" / 2>/dev/null | grep '^memory'); do
  echo "  /$m : device_type=$(fdtget -t s "$DTB" "/$m" device_type 2>/dev/null) reg(hex)=[$(fdtget -t x "$DTB" "/$m" reg 2>/dev/null)]"
done
echo "=== cpus ==="
echo "  enable-method=$(fdtget -t s "$DTB" /cpus enable-method 2>/dev/null)"
for c in $(fdtget -l "$DTB" /cpus 2>/dev/null | grep '^cpu@'); do
  echo "  /cpus/$c compatible=[$(fdtget -t s "$DTB" "/cpus/$c" compatible 2>/dev/null)] reg=$(fdtget -t x "$DTB" "/cpus/$c" reg 2>/dev/null) release-addr=[$(fdtget -t x "$DTB" "/cpus/$c" cpu-release-addr 2>/dev/null)]"
done
echo "=== timer / gic / serial / fb node probes ==="
for n in /timer /interrupt-controller@20a10000 /soc/serial@20a0c0000 /serial@20a0c0000 /soc /chosen/framebuffer@0; do
  S=$(fdtget -t s "$DTB" "$n" status 2>/dev/null)
  C=$(fdtget -t s "$DTB" "$n" compatible 2>/dev/null)
  R=$(fdtget -t x "$DTB" "$n" reg 2>/dev/null)
  if [ -n "$S$C$R" ]; then
    printf '  %-32s status=[%s] compatible=[%s] reg=[%s]\n' "$n" "$S" "$C" "$R"
  fi
done
echo "=== nodes containing 'serial' or 'uart' anywhere ==="
fdtdump "$DTB" 2>/dev/null | grep -nE 'serial@|uart|s5l-uart' | head -20
