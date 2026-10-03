#!/bin/bash
# Runs INSIDE the a9build container. Decodes the built DTB and reports the
# boot-critical nodes the loader must populate.
set -u
cd /build/linux-a9 || exit 9
DTB=arch/arm64/boot/dts/apple/s8003-n69.dtb

echo "=== DTB file ==="
ls -la "$DTB"
sha256sum "$DTB"

echo "=== DTB decode -> /memory, /chosen, cpus, framebuffer ==="
dtc -I dtb -O dts "$DTB" 2>/dev/null > /tmp/n69.dts
echo "decoded lines: $(wc -l < /tmp/n69.dts)"

echo "--- root compatible/model ---"
grep -n -E 'compatible = |model = ' /tmp/n69.dts | sed -n '1,6p'

echo "--- memory node ---"
if grep -q 'memory@' /tmp/n69.dts; then
  awk '/memory@/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts
else
  echo "NO /memory NODE IN DTB"
fi

echo "--- chosen node ---"
if grep -q 'chosen {' /tmp/n69.dts; then
  awk '/chosen \{/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts
else
  echo "NO /chosen NODE IN DTB"
fi

echo "--- framebuffer ---"
grep -n 'framebuffer' /tmp/n69.dts | sed -n '1,10p'

echo "--- cpu-release-addr ---"
grep -n 'cpu-release-addr' /tmp/n69.dts | sed -n '1,10p'

echo "--- cpus: first cpu node ---"
awk '/cpus \{/{f=1} f{print} f&&/};/{exit}' /tmp/n69.dts | sed -n '1,25p'

echo "--- interrupt-controller / timer present? ---"
grep -n -E 'interrupt-controller@|timer \{|a9-timer|arm,armv8-timer' /tmp/n69.dts | sed -n '1,12p'

echo "=== s8003.dtsi / s800x-se.dtsi placeholder markers ==="
grep -n 'To be filled' arch/arm64/boot/dts/apple/s8003.dtsi \
  arch/arm64/boot/dts/apple/s800x-se.dtsi \
  arch/arm64/boot/dts/apple/s800x.dtsi 2>/dev/null || echo "(none found in those files)"

echo "=== which dtsi files does s8003.dtsi include ==="
grep -n '#include' arch/arm64/boot/dts/apple/s8003.dtsi | sed -n '1,20p'
echo "=== END ==="
