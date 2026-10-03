#!/usr/bin/env bash
# a9linux/qemu/locate-arlo-hang.sh — name the exact place OUR kernel stops on QEMU.
#
# Our kernel takes no exceptions and has no console on QEMU virt, so the only way
# to say where it is stuck is to read the PC and map it back to a symbol. KASLR
# randomises the mapping, so this boot passes `nokaslr`; after that the PC minus
# the link base is an exact offset into System.map.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
SOCK="$STAGE/work/mon5.sock"
DTB="$STAGE/inputs/n69-arlo-nokaslr.dtb"
BOOTARGS="console=ttyAMA0 rdinit=/init panic=-1 loglevel=7 nokaslr"
ISIZE=$(stat -c%s "$STAGE/inputs/harness-selfinit.cpio.gz")

rm -f "$SOCK"
python3 "$Q/adapt-dtb.py" "$STAGE/inputs/n69-loader-target.dtb" "$DTB" --mode virt \
    --cpu-release-addr 0x44004000 --bootargs "$BOOTARGS" \
    --initrd-addr 0x44200000 --initrd-size "$ISIZE" > "$STAGE/logs/12-adapt.log" 2>&1

timeout -k 5 40 qemu-system-aarch64 -M virt -cpu max -smp 2 -m 1024 \
  -display none -serial file:"$STAGE/logs/12-nokaslr$LOG_TAG.log" -no-reboot \
  -monitor unix:"$SOCK",server,nowait -dtb "$DTB" \
  -device loader,file="$STAGE/inputs/arlo-Image",addr=0x40080000,force-raw=on \
  -device loader,file="$DTB",addr=0x44100000,force-raw=on \
  -device loader,file="$STAGE/inputs/harness-selfinit.cpio.gz",addr=0x44200000,force-raw=on \
  -device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=0 \
  > /dev/null 2>&1 &
QPID=$!
sleep 14
echo "=== PC and key registers at t=14s (nokaslr, -cpu max) ==="
python3 "$Q/mon-cmd.py" "$SOCK" "info registers" | grep -E 'PC=|X00=|SP=|PSTATE' | head -6
echo "=== early_cpu_boot_status at 0x41356800 (0 = did not park on an error) ==="
python3 "$Q/mon-cmd.py" "$SOCK" "xp /1wx 0x41356800" | head -3
echo "=== framebuffer marker (userland ran?) ==="
python3 "$Q/mon-cmd.py" "$SOCK" "xp /32bx 0x7c000000" | head -5
# Read the PC BEFORE killing the guest. The socket is the guest's; the old order
# queried the monitor after `kill`, so the PC was always empty and this script
# printed "PC=0xunknown" -- the symbol resolution below had never run.
PC=$(python3 "$Q/mon-cmd.py" "$SOCK" "info registers" 2>/dev/null | grep -oE 'PC=[0-9a-f]{16}' | head -1 | cut -d= -f2)
cp "$STAGE/logs/12-nokaslr$LOG_TAG.log" "$LOG_SCOPE/12-nokaslr$LOG_TAG.log" 2>/dev/null || true
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
echo
echo "=== symbol resolution for PC=0x${PC:-unknown} (link base 0xffff800080000000, image base 0x40080000) ==="
if [ -n "${PC:-}" ]; then
  # nokaslr: kernel VA == link VA, and image offset == VA - link base
  PY=$(printf '0x%x' $(( 0x${PC} - 0xffff800080000000 )))
  PHYS=$(printf '0x%x' $(( 0x40080000 + 0x${PC} - 0xffff800080000000 )))
  echo "  offset into Image = $PY   implied physical = $PHYS"
  if command -v wsl.exe >/dev/null 2>&1 && [ ! -f "$W/a9linux/artefacts/kernel/System.map" ]; then
    wsl.exe -d podman-main -u root -- bash "$Q/resolve-pc.sh" "$PHYS" 0x40080000 2>/dev/null \
      || echo "  (resolve-pc.sh needs the Podman VM's System.map; run it there by hand)"
  else
    # Bare-metal Linux (or a checkout that has the maps): resolve here.
    bash "$Q/resolve-pc.sh" "$PHYS" 0x40080000 \
      || echo "  (resolve-pc.sh failed; pass a System.map as its third argument)"
  fi
fi
