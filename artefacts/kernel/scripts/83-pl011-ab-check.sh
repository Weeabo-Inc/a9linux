#!/bin/bash
# Runs INSIDE the a9build container.
# A/B check: is the PL011 console actually LINKED INTO the variant binary, and
# genuinely absent from the shipping binary? Config symbols alone are not proof.
set -u

check() {
  local tree="$1" label="$2"
  echo "===== $label ====="
  echo "tree: $tree"
  cd "$tree" || return 9
  echo "--- PL011 symbols in System.map ---"
  local n
  n=$(grep -c -i 'pl011' System.map 2>/dev/null || echo 0)
  echo "count: $n"
  grep -i 'pl011' System.map 2>/dev/null | awk '{print "   ", $2, $3}' | head -n 14
  echo "--- console registration symbols ---"
  grep -E ' (pl011_console|pl011_console_ops|amba_pl011_driver|pl011_probe|pl011_early_console_setup)$' System.map 2>/dev/null | awk '{print "   ", $2, $3}'
  echo "--- the console string the kernel will offer ---"
  if grep -q -i 'pl011' System.map 2>/dev/null; then echo "   PL011 PRESENT"; else echo "   PL011 ABSENT"; fi
  echo
}

check /build/linux-a9-qemu "QEMU VARIANT (expect PL011 PRESENT)"
check /build/linux-a9      "SHIPPING DEVICE KERNEL (expect PL011 ABSENT)"

echo "===== A/B summary ====="
# NB: `grep -c` prints "0" AND exits 1 when there are no matches, so `|| echo 0`
# would append a second line and corrupt the comparison. Capture the count only.
A=$(grep -c -i pl011 /build/linux-a9-qemu/System.map 2>/dev/null)
B=$(grep -c -i pl011 /build/linux-a9/System.map 2>/dev/null)
A=${A:-0}; B=${B:-0}
echo "variant  pl011 symbols: $A"
echo "shipping pl011 symbols: $B"
if [ "$A" -gt 0 ] && [ "$B" -eq 0 ]; then
  echo ">>> PASS: the delta is real in the binaries, not just in the config"
else
  echo ">>> UNEXPECTED: variant=$A shipping=$B -- investigate"
fi
echo
echo "--- also confirm the shipping kernel still has its OWN console (samsung/s5l) ---"
S=$(grep -c -i 's5l\|samsung' /build/linux-a9/System.map 2>/dev/null); S=${S:-0}
V=$(grep -c -i 's5l\|samsung' /build/linux-a9-qemu/System.map 2>/dev/null); V=${V:-0}
echo "shipping samsung-tty symbols: $S"
echo "variant  samsung-tty symbols: $V"
if [ "$S" -gt 0 ] && [ "$V" -gt 0 ]; then
  echo ">>> PASS: the variant ADDS a console and does not remove the device one"
else
  echo ">>> UNEXPECTED: samsung console missing somewhere (shipping=$S variant=$V)"
fi
echo "=== END ==="
