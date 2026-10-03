#!/bin/bash
# Runs INSIDE the a9build container, DETACHED via `podman exec -d`.
# Full kernel build. Restartable: `make` is incremental, just re-run this.
set -u
cd /build/linux-a9 || exit 9

LOG=/build/kbuild.log
EXITF=/build/kbuild.exit
rm -f "$EXITF"

{
  echo "===================== KERNEL BUILD ====================="
  echo "START_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "PWD=$(pwd)"
  echo "HEAD=$(cat .git/HEAD 2>/dev/null)"
  echo "NPROC=$(nproc)"
  echo "HOSTNAME=$(hostname)"
  echo "CC=$(clang --version | head -n 1)"
  echo "LD=$(ld.lld --version | head -n 1)"
  echo "AR=$(llvm-ar --version | head -n 1)"
  echo "MAKE=$(make --version | head -n 1)"
  echo "CMD=make -j$(nproc) LLVM=1 ARCH=arm64 Image.gz dtbs"
  echo "======================================================="
} > "$LOG" 2>&1

START=$SECONDS
make -j"$(nproc)" LLVM=1 ARCH=arm64 Image.gz dtbs >> "$LOG" 2>&1
RC=$?
END=$SECONDS

{
  echo "======================================================="
  echo "EXIT=$RC"
  echo "END_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "ELAPSED_SECONDS=$((END-START))"
  echo "--- artefacts ---"
  ls -la arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/apple/s8003-n69.dtb 2>&1
  sha256sum arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/apple/s8003-n69.dtb 2>&1
} >> "$LOG" 2>&1

echo "$RC" > "$EXITF"
