#!/usr/bin/env bash
# a9linux/qemu/run-qemu.sh — the Arlo arm64 boot-contract harness.
#
# Boots an arm64 Image (+ optional DTB, + optional initramfs) under QEMU `virt`,
# captures the full console, and records the exact command + input hashes.
#
# HARD RULE: QEMU ONLY. This script never touches the iPhone and never invokes
# a9pwn / a9drv / irecovery. A green run here is NOT evidence about the phone.
#
# Run it (either host, any cwd):
#   bash a9linux/qemu/run-qemu.sh --name baseline-virt
# WSL, from Windows:
#   wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/run-qemu.sh --name baseline-virt
#
# Scratch/staging lives in $A9QEMU_STAGE (default /opt/a9qemu; a per-user state
# directory when /opt is not writable). Logs are copied back to $A9QEMU_LOG_SCOPE
# (default: this directory), with $A9QEMU_LOG_TAG appended to the name if set.
# See qemu-env.sh — this is the only place those paths are decided.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
QEMU=${QEMU:-qemu-system-aarch64}

NAME=""
KERNEL="$STAGE/inputs/stock-Image"
DTB=""
INITRD=""
APPEND=""
TIMEOUT=300
CPU="cortex-a57"
SMP=2
MEM=1024
MACHINE="virt"
EXTRA=""
LOADER_STUB=""
NO_DTB=0

usage() { sed -n '2,20p' "$0"; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name)        NAME="$2"; shift 2 ;;
    --kernel)      KERNEL="$2"; shift 2 ;;
    --dtb)         DTB="$2"; shift 2 ;;
    --no-dtb)      NO_DTB=1; shift ;;
    --initrd)      INITRD="$2"; shift 2 ;;
    --append)      APPEND="$2"; shift 2 ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    --cpu)         CPU="$2"; shift 2 ;;
    --smp)         SMP="$2"; shift 2 ;;
    --mem)         MEM="$2"; shift 2 ;;
    --machine)     MACHINE="$2"; shift 2 ;;
    --extra)       EXTRA="$2"; shift 2 ;;
    --loader-stub) LOADER_STUB="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$NAME" ] || { echo "FATAL: --name is required" >&2; usage; }
mkdir -p "$STAGE/logs" "$STAGE/work" "$WIN_SCOPE/logs"

LOG="$STAGE/logs/$NAME.log"
META="$STAGE/logs/$NAME.meta.txt"

for f in "$KERNEL" "$DTB" "$INITRD" "$LOADER_STUB"; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || { echo "FATAL: input not found: $f" >&2; exit 1; }
done

ARGS=(-M "$MACHINE" -cpu "$CPU" -smp "$SMP" -m "$MEM"
      -display none -serial stdio -no-reboot -monitor none)

IMAGE_ADDR=${IMAGE_ADDR:-0x40080000}
DTB_ADDR=${DTB_ADDR:-0x44100000}
INITRD_ADDR=${INITRD_ADDR:-0x44200000}
STUB_ADDR=${STUB_ADDR:-0x44000000}

if [ -n "$LOADER_STUB" ]; then
  # Boot the way a loader boots a kernel, not the way QEMU boots one:
  # every blob is placed by an explicit -device loader at a physical address we
  # chose, and the stub at the RAM base is CPU0's entry point. Nothing is
  # passed in registers by QEMU except the reset vector, so the stub must set
  # x0 = DTB (and x1..x3 = 0) itself. The DTB carries bootargs and
  # initrd-start/end, because on arm64 those have no other channel.
  # No -bios: 'none' is not a valid value in QEMU 8.2, and with every blob
  # placed by an explicit loader device the guest never executes firmware.
  #
  # -dtb IS passed, for a QEMU bookkeeping reason only: with no -dtb, `virt`
  # builds its own DTB and registers a 1MB ROM region at 0x40000000, which
  # collides with the Image at 0x40080000 and makes QEMU abort. Passing a DTB
  # shrinks that region to its real size. The guest never reads QEMU's copy:
  # the stub hands the kernel the loader-placed DTB at $DTB_ADDR instead.
  ARGS+=(-dtb "$DTB")
  ARGS+=(-device "loader,file=$KERNEL,addr=$IMAGE_ADDR,force-raw=on")
  [ -n "$DTB" ]    && ARGS+=(-device "loader,file=$DTB,addr=$DTB_ADDR,force-raw=on")
  [ -n "$INITRD" ] && ARGS+=(-device "loader,file=$INITRD,addr=$INITRD_ADDR,force-raw=on")
  ARGS+=(-device "loader,file=$LOADER_STUB,addr=$STUB_ADDR,force-raw=on,cpu-num=0")
  ARGS+=(-device "loader,file=$LOADER_STUB,addr=$STUB_ADDR,force-raw=on,cpu-num=1")
  # deliberately NOT passed: -kernel, -dtb, -initrd, -append. Passing any of
  # them would put QEMU back in charge of an obligation a9boot owns.
else
  ARGS+=(-kernel "$KERNEL")
  [ -n "$DTB" ] && ARGS+=(-dtb "$DTB")
  [ -n "$INITRD" ] && ARGS+=(-initrd "$INITRD")
  [ -n "$APPEND" ] && ARGS+=(-append "$APPEND")
fi
[ -n "$EXTRA" ] && ARGS+=($EXTRA)

{
  echo "=== a9linux/qemu harness run: $NAME ==="
  echo "utc_start      : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "qemu_version   : $($QEMU --version | head -1)"
  echo "machine        : $MACHINE  cpu=$CPU smp=$SMP mem=${MEM}M"
  echo "kernel         : $KERNEL"
  [ -n "$KERNEL" ] && echo "kernel_sha256  : $(sha256sum "$KERNEL" | cut -d' ' -f1)"
  [ -n "$KERNEL" ] && echo "kernel_pages   : $(file -b "$KERNEL" | sed -n 's/.*, \(.*\)$/\1/p')"
  if [ -n "$DTB" ]; then
    echo "dtb            : $DTB"
    echo "dtb_sha256     : $(sha256sum "$DTB" | cut -d' ' -f1)"
    echo "dtb_size       : $(stat -c%s "$DTB")"
  else
    echo "dtb            : (none — QEMU generates the virt DT)"
  fi
  if [ -n "$INITRD" ]; then
    echo "initrd         : $INITRD"
    echo "initrd_sha256  : $(sha256sum "$INITRD" | cut -d' ' -f1)"
    echo "initrd_size    : $(stat -c%s "$INITRD")"
  else
    echo "initrd         : (none)"
  fi
  [ -n "$LOADER_STUB" ] && echo "loader_stub    : $LOADER_STUB  (QEMU does NOT load the kernel; the stub does the hand-off)"
  [ -n "$LOADER_STUB" ] && echo "load_addrs     : image=$IMAGE_ADDR dtb=$DTB_ADDR initrd=$INITRD_ADDR stub=$STUB_ADDR (cpu0+cpu1)"
  echo "append         : $APPEND"
  echo "timeout_s      : $TIMEOUT"
  echo "exact_command  : timeout -k 5 $TIMEOUT $QEMU ${ARGS[*]}"
  echo "=========================================="
} | tee "$META"

timeout -k 5 "$TIMEOUT" "$QEMU" "${ARGS[@]}" < /dev/null > "$LOG" 2>&1
RC=$?

{
  echo "------------------------------------------"
  echo "utc_end        : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  case $RC in
    0)   echo "exit           : 0 (guest powered off / halted cleanly)" ;;
    124) echo "exit           : 124 (WALL-CLOCK TIMEOUT after ${TIMEOUT}s — did not finish)" ;;
    137) echo "exit           : 137 (SIGKILL after timeout)" ;;
    *)   echo "exit           : $RC" ;;
  esac
  echo "console_bytes  : $(stat -c%s "$LOG")"
  echo "console_lines  : $(wc -l < "$LOG")"
  echo "tail           :"
  tail -25 "$LOG" | sed 's/^/    | /'
} | tee -a "$META"

# Tagged so a run on a second host cannot overwrite the first host's capture
# (A9QEMU_LOG_TAG; see qemu-env.sh and README section 10.5).
cp "$LOG" "$WIN_SCOPE/logs/$NAME$LOG_TAG.log" 2>/dev/null || true
cp "$META" "$WIN_SCOPE/logs/$NAME$LOG_TAG.meta.txt" 2>/dev/null || true
echo
echo "log  -> $WIN_SCOPE/logs/$NAME$LOG_TAG.log"
echo "meta -> $WIN_SCOPE/logs/$NAME$LOG_TAG.meta.txt"
exit $RC
