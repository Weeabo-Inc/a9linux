#!/usr/bin/env bash
# a9linux/qemu/fetch-inputs.sh
#
# Stage the QEMU harness inputs inside the Linux VM's ext4 (NEVER build or run
# QEMU over /mnt/* — drvfs/9p, see HANDOFF.md §9.3).
#
# This script fetches ONLY a stand-in "stock" arm64 kernel, so that the harness
# can be exercised before kernel-engineer's Image (task-6) exists. It is a
# STAND-IN, not our kernel. Everything it downloads is labelled as such in
# inputs/PROVENANCE.txt.
#
# Run (either host):  bash a9linux/qemu/fetch-inputs.sh
#   WSL: wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/fetch-inputs.sh
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
mkdir -p "$STAGE"/{inputs,logs,work,tools}

cd "$STAGE/inputs"

echo "== [1/4] scanning Ubuntu ports noble(+updates) for a generic arm64 kernel =="
: > /tmp/pkgindex.txt
for suite in noble noble-updates noble-security; do
  url="https://ports.ubuntu.com/ubuntu-ports/dists/${suite}/main/binary-arm64/Packages.gz"
  if curl -fsSL "$url" -o "/tmp/P-${suite}.gz" 2>/dev/null; then
    echo "   index ok: $suite ($(stat -c%s "/tmp/P-${suite}.gz") bytes)"
    zcat "/tmp/P-${suite}.gz" \
      | grep -E '^Filename: .*/linux-image-[0-9][^/]*generic_[^/]*_arm64\.deb$' \
      >> /tmp/pkgindex.txt || true
  else
    echo "   index MISSING: $suite"
  fi
done

# newest version first (path contains the version string)
SORTED=$(sort -u /tmp/pkgindex.txt | sed 's/^Filename: //' | sort -r)
echo "== [2/4] candidate arm64 kernel packages =="
echo "$SORTED" | head -5

DEB_PATH=$(echo "$SORTED" | head -1)
if [ -z "$DEB_PATH" ]; then
  echo "!! no arm64 generic kernel found in ports indexes; falling back to Debian trixie" >&2
  curl -fsSL https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.gz -o /tmp/PD.gz
  DEB_PATH=$(zcat /tmp/PD.gz | grep -E '^Filename: .*/linux-image-[0-9][^/]*arm64_[^/]*_arm64\.deb$' \
             | sed 's/^Filename: //' | sort -r | head -1)
fi
[ -n "$DEB_PATH" ] || { echo "FATAL: no stock arm64 kernel package located" >&2; exit 1; }

BASE=$(basename "$DEB_PATH")
if [ ! -f "$BASE" ]; then
  echo "== [3/4] downloading $BASE =="
  curl -fL --retry 3 -o "$BASE" "https://ports.ubuntu.com/ubuntu-ports/$DEB_PATH" \
    || curl -fL --retry 3 -o "$BASE" "https://deb.debian.org/debian/$DEB_PATH"
else
  echo "== [3/4] already present: $BASE =="
fi
echo "   sha256: $(sha256sum "$BASE" | cut -d' ' -f1)"

echo "== [4/4] extracting vmlinuz/Image =="
rm -rf /tmp/kdeb && mkdir -p /tmp/kdeb
dpkg-deb -x "$BASE" /tmp/kdeb
VM=$(find /tmp/kdeb/boot -maxdepth 1 -name 'vmlinuz-*' | head -1)
[ -n "$VM" ] || { echo "FATAL: no vmlinuz in $BASE" >&2; exit 1; }
FILE_DESC=$(file -b "$VM")
echo "   $VM"
echo "   file(1): $FILE_DESC"
case "$FILE_DESC" in
  *gzip*)    zcat "$VM" > stock-Image ;;
  *Zip*)     zcat "$VM" > stock-Image ;;
  *"Linux kernel ARM64 boot executable Image"*) cp "$VM" stock-Image ;;
  *PE32*)    echo "!! EFI zboot image — needs extraction, not supported here" >&2; exit 1 ;;
  *)         cp "$VM" stock-Image ;;
esac
ls -l stock-Image
echo "   stock-Image sha256: $(sha256sum stock-Image | cut -d' ' -f1)"
file -b stock-Image

{
  echo "# Inputs staged for the a9linux/qemu harness"
  echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ) by fetch-inputs.sh"
  echo "stock_kernel_deb      = $BASE"
  echo "stock_kernel_deb_url  = https://ports.ubuntu.com/ubuntu-ports/$DEB_PATH"
  echo "stock_kernel_sha256   = $(sha256sum stock-Image | cut -d' ' -f1)"
  echo "# stock-Image is a STAND-IN distro kernel (see README 'Provenance'), NOT our kernel."
} > PROVENANCE.txt
cat PROVENANCE.txt
echo "OK"
