#!/usr/bin/env bash
# a9linux/qemu/run-arlo-kernel.sh — boot OUR kernel (16K pages) on QEMU virt.
#
# Two flips this harness had to make, both MEASURED, both in CANNOT-PROVE.md:
#   1. -cpu max. Our kernel is built for the 16K granule; cortex-a57/a53/a72 all
#      park in __no_granule_support with CPU_STUCK_IN_KERNEL (0x202) because their
#      ID_AA64MMFR0_EL1.TGran16 says "not implemented". Only `max` advertises it.
#      QEMU's TCG itself does 16K translation fine -- it was the CPU model.
#   2. Our kernel has no PL011 driver, so it cannot print on QEMU virt at all.
#      Console output is therefore replaced by two host-side observations: the
#      PC via QEMU's monitor, and a marker /init writes into the framebuffer,
#      which the monitor can read out of guest RAM.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
K="$STAGE/inputs/arlo-Image"
INITRD="$STAGE/inputs/harness-selfinit.cpio.gz"
CPU="${CPU:-max}"
SOCK="$STAGE/work/mon2.sock"
MAILBOX=0x44004000
FB_ADDR=0x7c000000
DTB_ADDR=0x44100000
INITRD_ADDR=0x44200000
ISIZE=$(stat -c%s "$INITRD")
BOOTARGS="console=ttyAMA0 earlycon=s5l,0x20a0c000 rdinit=/init panic=-1 loglevel=7 mailbox=$MAILBOX"

mon() { # socket, commands...
  python3 - "$@" <<'PY'
import socket, sys, time
sock = sys.argv[1]
cmds = sys.argv[2:]
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock); s.settimeout(1.5); time.sleep(0.3)
    try: s.recv(65536)
    except Exception: pass
    for c in cmds:
        s.sendall((c + "\n").encode()); time.sleep(0.7)
    out = b""
    try:
        while True:
            ch = s.recv(65536)
            if not ch: break
            out += ch
    except Exception: pass
    txt = out.decode(errors="replace")
    for line in txt.splitlines():
        if any(k in line for k in ("PC=", "=>", ":")) and "xp" not in line and len(line) < 200:
            print("   ", line.strip()[:150])
except Exception as e:
    print("    (monitor unavailable:", e, ")")
PY
}

probe() { # label
  echo "--- $1 ---"
  echo "  registers:"; mon "$SOCK" "info registers" | head -6
  echo "  framebuffer @ $FB_ADDR (host-side read of guest RAM):"
  # Keep the read-back: the verdict below greps THIS file. Before, the dump
  # only went to stdout and the verdict looked for a file nothing wrote, so
  # it always answered "NOT PROVEN" whatever the guest actually did.
  mon "$SOCK" "xp /64bx $FB_ADDR" | tee -a "$STAGE/logs/${RUN_NAME:-$1}$LOG_TAG-fb.txt"
}

boot() { # name dtb-or-empty
  local name="$1" dtb="$2"
  RUN_NAME="$name"   # probe() names its read-back file after the run, not the tick
  rm -f "$SOCK"
  local LOG="$STAGE/logs/$name$LOG_TAG.log"
  local args=(-M virt -cpu "$CPU" -smp 2 -m 1024 -display none -serial file:"$LOG"
              -no-reboot -monitor unix:"$SOCK",server,nowait)
  if [ -n "$dtb" ]; then
    args+=(-dtb "$dtb")
    args+=(-device loader,file="$K",addr=0x40080000,force-raw=on)
    args+=(-device loader,file="$dtb",addr=$DTB_ADDR,force-raw=on)
    args+=(-device loader,file="$INITRD",addr=$INITRD_ADDR,force-raw=on)
    args+=(-device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=0)
  else
    args+=(-kernel "$K" -initrd "$INITRD" -append "$BOOTARGS")
  fi
  echo
  echo "############################################################"
  echo "### $name   (-cpu $CPU)"
  echo "############################################################"
  echo "exact_command: timeout -k 5 45 qemu-system-aarch64 ${args[*]}"
  timeout -k 5 45 qemu-system-aarch64 "${args[@]}" >/dev/null 2>&1 &
  local pid=$!
  sleep 12;  probe "$name t=12s"
  sleep 12;  probe "$name t=24s"
  if kill -0 $pid 2>/dev/null; then
    echo "guest still running at t=36s (no guest-initiated reset)"
    kill $pid 2>/dev/null
  else
    wait $pid; echo "QEMU exited early (rc=$?) -> guest reset itself"
  fi
  wait $pid 2>/dev/null
  echo "console bytes: $(stat -c%s "$LOG" 2>/dev/null || echo 0)"
  if grep -qa 'A9QEMU-USERLAND-MARKER' "$LOG" 2>/dev/null; then :; fi
  # Tagged copy-back: two hosts sharing one log name is a collision, and the
  # first Linux re-run of this script overwrote the WSL 07/08 console logs
  # because this line had no tag. A9QEMU_LOG_TAG (see qemu-env.sh) fixes it.
  cp "$LOG" "$LOG_SCOPE/$name$LOG_TAG.log" 2>/dev/null || true
  cp "$STAGE/logs/$name$LOG_TAG-fb.txt" "$LOG_SCOPE/$name$LOG_TAG-fb.txt" 2>/dev/null || true
}

echo "=== our kernel ==="
file -b "$K"
echo "sha256: $(sha256sum "$K" | cut -d' ' -f1)"
echo "initramfs: $INITRD ($ISIZE bytes)"
echo "cpu model: $CPU   (see granule-sweep.sh: only 'max' advertises TGran16)"

grep -c . /dev/null
python3 "$Q/adapt-dtb.py" "$STAGE/inputs/n69-loader-target.dtb" \
    "$STAGE/inputs/n69-arlo-qemu-virt.dtb" --mode virt \
    --cpu-release-addr "$MAILBOX" \
    --bootargs "$BOOTARGS" \
    --initrd-addr "$INITRD_ADDR" --initrd-size "$ISIZE" > "$STAGE/logs/08-adapt.log" 2>&1
echo "adapted DTB: $(sha256sum "$STAGE/inputs/n69-arlo-qemu-virt.dtb" | cut -c1-16) (transforms in $STAGE/logs/08-adapt.log)"
python3 "$Q/check-dtb.py" "$STAGE/inputs/n69-arlo-qemu-virt.dtb" | tail -12

boot 07-arlo-kernel-virt-dt ""
boot 08-arlo-kernel-our-dtb "$STAGE/inputs/n69-arlo-qemu-virt.dtb"

echo
echo "=== verdict for 08: did userland run without a console? ==="
# The marker is the ASCII string A9QEMU-USERLAND-MARKER written by /init into
# the framebuffer; its first six bytes are 41 39 51 45 4d 55.
FBLOG="$STAGE/logs/08-arlo-kernel-our-dtb$LOG_TAG-fb.txt"
if grep -qa '41 39 51 45 4d 55' "$FBLOG" 2>/dev/null; then
  echo "YES - framebuffer marker read back from guest RAM ($FBLOG)"
elif [ -s "$FBLOG" ]; then
  echo "NO - the read-back happened ($FBLOG) and the marker is absent."
  echo "     An absent marker proves nothing about WHY userland did not run."
else
  echo "NOT PROVEN - no framebuffer read-back was captured (monitor unavailable?)"
fi
