#!/usr/bin/env bash
# a9linux/qemu/granule-sweep.sh — which QEMU CPU models will run our 16K-page kernel?
#
# Found the hard way: our kernel stopped at __no_granule_support with the status
# word 0x202 (CPU_STUCK_IN_KERNEL). That routine is reached when
# ID_AA64MMFR0_EL1.TGran16 says the CPU does not implement the 16K granule --
# which is true of QEMU's cortex-a57 model (and of the real Cortex-A57: 4K and
# 64K only). Apple's A9 does implement 16K, which is why the kernel is built
# that way.
#
# So the harness CPU model decides whether this kernel boots, and a sweep is the
# only honest way to show that. `info registers` gives us the PC: parked in the
# low physical range with the MMU off = refused; running in the kernel's high
# virtual range = the granule was accepted and the MMU is on.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
IMG="$STAGE/inputs/arlo-Image"
DTB="$STAGE/inputs/n69-arlo-qemu-virt.dtb"
INITRD="$STAGE/inputs/arlo-initramfs-min.cpio.gz"
SOCK="$STAGE/work/mon3.sock"
STATUS_ADDR=0x41356800        # early_cpu_boot_status in THIS build (from the disassembly)

probe() {
  python3 - "$SOCK" "$STATUS_ADDR" <<'PY'
import socket, sys, time
sock, status = sys.argv[1], sys.argv[2]
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock); s.settimeout(1.5); time.sleep(0.3)
    try: s.recv(65536)
    except Exception: pass
    s.sendall(b"info registers\n")
    time.sleep(0.6)
    s.sendall(f"xp /1wx {status}\n".encode())
    time.sleep(0.6)
    out = b""
    try:
        while True:
            c = s.recv(65536)
            if not c: break
            out += c
    except Exception: pass
    txt = out.decode(errors="replace")
    pc = ""
    for line in txt.splitlines():
        if "PC=" in line and not pc:
            pc = line.strip()
        if status.lower().lstrip("0x").lstrip("0") in line.lower() and ":" in line:
            print("    status word:", line.strip()[:80])
    print("   ", pc[:110])
    import re
    m = re.search(r'PC=([0-9a-fA-F]{16})', pc)
    if m:
        v = int(m.group(1), 16)
        if v >= 0xffff000000000000:
            print("    => PC in kernel HIGH virtual range: MMU ON, granule ACCEPTED")
        elif 0x40000000 <= v < 0x80000000:
            print("    => PC in low PHYSICAL range: MMU still off (refused or very early)")
        else:
            print(f"    => PC 0x{v:x}: neither; inspect by hand")
except Exception as e:
    print("    (monitor unavailable:", e, ")")
PY
}

for CPU in cortex-a57 cortex-a53 cortex-a72 max; do
  echo
  echo "############ -cpu $CPU ############"
  rm -f "$SOCK"
  LOG="$STAGE/logs/10-granule-$CPU$LOG_TAG.log"
  # Copy into the repo under the SAME tag. Without a tag, a re-run on a second
  # host silently overwrites the first host's capture -- which is exactly what
  # happened to 07/08 and 10-granule-* on 2026-10-03 (README section 10).
  timeout -k 5 40 qemu-system-aarch64 -M virt -cpu "$CPU" -smp 2 -m 1024 \
    -display none -serial file:"$LOG" -no-reboot -monitor unix:"$SOCK",server,nowait \
    -dtb "$DTB" \
    -device loader,file="$IMG",addr=0x40080000,force-raw=on \
    -device loader,file="$DTB",addr=0x44100000,force-raw=on \
    -device loader,file="$INITRD",addr=0x44200000,force-raw=on \
    -device loader,file="$STAGE/inputs/handoff-stub.bin",addr=0x44000000,force-raw=on,cpu-num=0 \
    >/dev/null 2>&1 &
  PID=$!
  sleep 12
  probe
  wait $PID 2>/dev/null
  echo "  console bytes: $(stat -c%s "$LOG" 2>/dev/null || echo 0)"
  cp "$LOG" "$LOG_SCOPE/$(basename "$LOG")" 2>/dev/null || true
done
