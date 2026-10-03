#!/bin/bash
# Runs INSIDE the a9build container, DETACHED.
# Builds the QEMU-ONLY test instrument: the shipping config + PL011 console,
# and nothing else. Deliberately built in a PRISTINE CLONE so the shipping
# tree's .config and Image are never touched.
set -u
SRC=/build/linux-a9
W=/build/linux-a9-qemu
cd "$W" || exit 9

LOG=/build/kbuild-qemu-pl011.log
EXITF=/build/kbuild-qemu-pl011.exit
BASE_EXPECT=eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041
rm -f "$EXITF"

{
  echo "=============== QEMU-ONLY PL011 TEST INSTRUMENT ==============="
  echo "START_UTC   = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "SOURCE      = $SRC  (shipping tree -- read only)"
  echo "BUILD TREE  = $W  (pristine clone)"
  echo "HEAD        = $(cat .git/HEAD 2>/dev/null)"
  echo "NPROC       = $(nproc)"
  echo "CC          = $(clang --version | head -n 1)"
  echo "PURPOSE     = let qemu-validator distinguish 'stuck' from 'idle with nowhere to print'"
  echo "NOT FOR DEVICE. Never flash this Image to the iPhone."
  echo "================================================================="
} > "$LOG" 2>&1

echo "" >> "$LOG"
echo "--- base config: must be byte-identical to the shipping config.used ---" >> "$LOG"
cp -f "$SRC/.config" .config
cp -f "$SRC/.config" .config.base
BASE_HASH=$(sha256sum .config | cut -d' ' -f1)
{
  echo "base .config sha256 = $BASE_HASH"
  echo "expected            = $BASE_EXPECT"
} >> "$LOG"
if [ "$BASE_HASH" != "$BASE_EXPECT" ]; then
  echo "FATAL: base config is NOT the shipping config.used -- refusing to build" >> "$LOG"
  echo 1 > "$EXITF"
  exit 1
fi
echo "OK: base config matches the shipping config exactly" >> "$LOG"

echo "" >> "$LOG"
echo "--- THE ENTIRE DELTA (2 symbols) ---" >> "$LOG"
./scripts/config --file .config -e SERIAL_AMBA_PL011           >> "$LOG" 2>&1
./scripts/config --file .config -e SERIAL_AMBA_PL011_CONSOLE   >> "$LOG" 2>&1
make LLVM=1 ARCH=arm64 olddefconfig                            >> "$LOG" 2>&1

# The console symbol depends on SERIAL_AMBA_PL011=y, and was absent from the base
# config entirely. If resolution dropped it, re-apply and resolve once more.
if ! grep -q '^CONFIG_SERIAL_AMBA_PL011_CONSOLE=y' .config; then
  echo "(console symbol dropped by first resolution - re-applying and re-resolving)" >> "$LOG"
  ./scripts/config --file .config -e SERIAL_AMBA_PL011_CONSOLE >> "$LOG" 2>&1
  make LLVM=1 ARCH=arm64 olddefconfig                          >> "$LOG" 2>&1
fi

echo "" >> "$LOG"
echo "=============== CONFIG DELTA vs the shipping config ===============" >> "$LOG"
diff .config.base .config >> "$LOG" 2>&1
echo "delta line count: $(diff .config.base .config | grep -c '^[<>]')" >> "$LOG"
echo "" >> "$LOG"
echo "--- PL011 symbols after resolution ---" >> "$LOG"
grep -n -E 'SERIAL_AMBA_PL011|SERIAL_CORE_CONSOLE|SERIAL_EARLYCON|ARM_AMBA' .config >> "$LOG" 2>&1
echo "" >> "$LOG"
echo "--- 16K granule preserved? ---" >> "$LOG"
grep -n -E '^CONFIG_ARM64_(4K|16K|64K)_PAGES|^# CONFIG_ARM64_(4K|16K|64K)_PAGES|^CONFIG_PAGE_SIZE_' .config >> "$LOG" 2>&1
echo "" >> "$LOG"
echo "--- variant config sha256 ---" >> "$LOG"
sha256sum .config >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "=============== BUILD ===============" >> "$LOG"
START=$SECONDS
make -j"$(nproc)" LLVM=1 ARCH=arm64 Image >> "$LOG" 2>&1
RC=$?
END=$SECONDS

{
  echo "================================================"
  echo "EXIT=$RC"
  echo "END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ELAPSED_SECONDS=$((END-START))"
  echo "CC invocations: $(grep -c '^  CC' "$LOG")"
  echo "warnings: $(grep -c -i 'warning:' "$LOG")   errors: $(grep -c -i 'error:' "$LOG")"
  echo "--- artefact ---"
  ls -la arch/arm64/boot/Image 2>&1
  sha256sum arch/arm64/boot/Image 2>&1
} >> "$LOG" 2>&1

echo "$RC" > "$EXITF"
