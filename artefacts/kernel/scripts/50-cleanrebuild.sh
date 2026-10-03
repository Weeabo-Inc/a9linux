#!/bin/bash
# Runs INSIDE the a9build container.
# CLEAN rebuild, so the delivered artefact is provably from a single coherent
# compile of this exact .config -- not a chimera of reused objects from an
# earlier session's partial build.
#
# Keeps the previous (incremental) artefacts aside purely to cross-check that
# the incremental build was coherent.
set -u
cd /build/linux-a9 || exit 9

KEEP=/build/kb-incremental
mkdir -p "$KEEP"

echo "=== stashing the incremental-build artefacts for comparison ==="
cp -f arch/arm64/boot/Image    "$KEEP/Image.incr"
cp -f arch/arm64/boot/Image.gz "$KEEP/Image.incr.gz"
cp -f System.map               "$KEEP/System.map.incr"
cp -f .config                  "$KEEP/config.incr"
cp -f vmlinux                  "$KEEP/vmlinux.incr"
sha256sum "$KEEP/Image.incr" "$KEEP/Image.incr.gz" "$KEEP/System.map.incr" | tee "$KEEP/hashes.txt"
echo "incr System.map symbols : $(wc -l < $KEEP/System.map.incr)"

echo ""
echo "=== mtime sanity (objects newer than the config that governs them?) ==="
echo ".config mtime      : $(stat -c %y .config)"
echo "autoconf.h mtime   : $(stat -c %y include/generated/autoconf.h)"
echo "newest .o mtime    : $(find . -name '*.o' -printf '%T+ %p\n' | sort | tail -n 1)"
echo "oldest .o mtime    : $(find . -name '*.o' -printf '%T+ %p\n' | sort | head -n 1)"
echo "objects with mtime in the FUTURE (clock skew => make may skip work):"
find . -name '*.o' -newermt '+1 minute' 2>/dev/null | wc -l

echo ""
echo "=== object census BEFORE clean ==="
find . -name '*.o' | wc -l

echo ""
echo "=== make LLVM=1 ARCH=arm64 clean ==="
make LLVM=1 ARCH=arm64 clean 2>&1 | tail -n 5

echo ""
echo "=== object census AFTER clean (expect ~0) ==="
find . -name '*.o' | wc -l

echo ""
echo "=== .config survived clean? (must be byte-identical) ==="
sha256sum .config

LOG=/build/kbuild-clean.log
EXITF=/build/kbuild-clean.exit
rm -f "$EXITF"

{
  echo "===================== CLEAN KERNEL BUILD ====================="
  echo "START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "CLEAN=yes (make clean immediately before)"
  echo "NPROC=$(nproc)"
  echo "CC=$(clang --version | head -n 1)"
  echo "LD=$(ld.lld --version | head -n 1)"
  echo "AR=$(llvm-ar --version | head -n 1)"
  echo "CMD=make -j$(nproc) LLVM=1 ARCH=arm64 Image.gz dtbs"
  echo "============================================================="
} > "$LOG" 2>&1

START=$SECONDS
make -j"$(nproc)" LLVM=1 ARCH=arm64 Image.gz dtbs >> "$LOG" 2>&1
RC=$?
END=$SECONDS

{
  echo "============================================================="
  echo "EXIT=$RC"
  echo "END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ELAPSED_SECONDS=$((END-START))"
  echo "CC invocations: $(grep -c '^  CC' "$LOG")"
  echo "--- artefacts ---"
  ls -la arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/apple/s8003-n69.dtb 2>&1
  sha256sum arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/apple/s8003-n69.dtb 2>&1
  echo "--- clean vs incremental cross-check ---"
  echo "clean System.map symbols: $(wc -l < System.map)"
  echo "incr  System.map symbols: $(wc -l < $KEEP/System.map.incr)"
  echo "symbol set diff (empty == structurally identical build):"
  diff <(awk '{print $3}' System.map | sort) <(awk '{print $3}' "$KEEP/System.map.incr" | sort) | head -n 20
  echo "symbol diff line count: $(diff <(awk '{print $3}' System.map | sort) <(awk '{print $3}' "$KEEP/System.map.incr" | sort) | wc -l)"
} >> "$LOG" 2>&1

echo "$RC" > "$EXITF"
