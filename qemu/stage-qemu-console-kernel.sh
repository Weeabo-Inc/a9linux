#!/usr/bin/env bash
# a9linux/qemu/stage-qemu-console-kernel.sh — take kernel-engineer's QEMU-console
# test variant and verify its claims before trusting it.
#
# The variant is a TEST INSTRUMENT: two config symbols different from the shipping
# kernel so that QEMU virt's PL011 has a driver behind it. It must never reach the
# device; the shipping Image stays the one with sha256 39a27067...
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
V="$W/a9linux/artefacts/kernel/Image-16k-qemu-pl011"
CFG="$W/a9linux/artefacts/kernel/config-qemu-pl011.used"
SHIP="$STAGE/inputs/arlo-Image"

echo "=== [1] artefact identity ==="
if [ ! -f "$V" ]; then echo "FATAL: $V missing" >&2; exit 1; fi
printf '  variant : %s bytes  sha256=%s\n' "$(stat -c%s "$V")" "$(sha256sum "$V" | cut -d' ' -f1)"
printf '  shipping: %s bytes  sha256=%s\n' "$(stat -c%s "$SHIP")" "$(sha256sum "$SHIP" | cut -d' ' -f1)"
echo "  variant file(1): $(file -b "$V")"

echo
echo "=== [2] config delta vs the shipping config (claim: exactly two symbols) ==="
SHIPCFG="$W/a9linux/artefacts/kernel/config.used"
if [ -f "$SHIPCFG" ] && [ -f "$CFG" ]; then
  diff <(grep -E '^(CONFIG|# CONFIG)' "$SHIPCFG" | sort) \
       <(grep -E '^(CONFIG|# CONFIG)' "$CFG" | sort) | sed 's/^/  /' || true
  echo "  (above = the whole delta; anything beyond the two PL011 symbols is a surprise)"
else
  echo "  (one of the configs is missing; cannot diff)"
fi

echo
echo "=== [3] A/B: is the PL011 driver really in the binary? ==="
# The maps live in the repository (kernel-engineer copied both out), so this is a
# local read on either host. The old path reached them through the Podman VM's
# build tree, which only exists on the WSL host; if wsl.exe is present AND the
# local copies are missing, fall back to it rather than silently reporting zero.
MAPS=("$W/a9linux/artefacts/kernel/System.map-qemu-pl011" "$W/a9linux/artefacts/kernel/System.map")
have_local=0
for f in "${MAPS[@]}"; do [ -f "$f" ] && have_local=1; done
if [ "$have_local" -eq 1 ]; then
  echo "  source: repository copies under a9linux/artefacts/kernel/"
  for f in "${MAPS[@]}"; do
    [ -f "$f" ] || { printf '  %-42s MISSING\n' "$f"; continue; }
    n=$(grep -c 'pl011' "$f" || true)
    s=$(grep -c 's5l\|samsung' "$f" || true)
    printf '  %-42s pl011 symbols=%-4s samsung/s5l symbols=%s\n' "$(basename "$f")" "$n" "$s"
  done
elif command -v wsl.exe >/dev/null 2>&1; then
  echo "  source: Podman VM build tree (no repository copies found)"
  VSM=$(wsl.exe -d podman-main -u root -- bash -lc "ls /build/linux-a9/System.map* 2>/dev/null" | tr -d '\r')
  for f in $VSM; do
    n=$(wsl.exe -d podman-main -u root -- bash -lc "grep -c 'pl011' $f" | tr -d '\r')
    s=$(wsl.exe -d podman-main -u root -- bash -lc "grep -c 's5l\|samsung' $f" | tr -d '\r')
    printf '  %-42s pl011 symbols=%-4s samsung/s5l symbols=%s\n' "$f" "$n" "$s"
  done
else
  echo "  (no System.map copies found and wsl.exe is unavailable on this host)"
fi

echo
echo "=== [4] image header flags (bits[2:1] should be 2 = 16K granule) ==="
python3 - "$V" <<'PY'
import struct, sys
b = open(sys.argv[1], 'rb').read(0x100)
code0, code1, text_off, img_size, flags = struct.unpack_from('<IIQQQ', b, 0)
magic = struct.unpack_from('<I', b, 56)[0]
print(f"  code0=0x{code0:08x} code1=0x{code1:08x} text_offset=0x{text_off:x} image_size=0x{img_size:x}")
print(f"  flags=0x{flags:x} -> bits[2:1]={(flags >> 1) & 3} (2 = ARM64_IMAGE_FLAG_PAGE_SIZE_16K)")
print(f"  magic@56=0x{magic:08x} (want 0x644d5241 'ARM\\x64')")
PY

echo
echo "=== [5] staging (test instrument only -- never for the device) ==="
cp -f "$V" "$STAGE/inputs/arlo-Image-qemu-pl011"
cp -f "$CFG" "$STAGE/inputs/config-qemu-pl011.used" 2>/dev/null || true
printf 'staged: %s bytes sha256=%s\n' "$(stat -c%s "$STAGE/inputs/arlo-Image-qemu-pl011")" \
  "$(sha256sum "$STAGE/inputs/arlo-Image-qemu-pl011" | cut -d' ' -f1)"

echo
echo "=== [6] refresh the rootfs-engineer inputs (their images were rebuilt at 13:00) ==="
for f in arlo-initramfs-min.cpio.gz arlo-initramfs-debian.cpio.gz; do
  src="$W/debian-ios/dist/$f"
  if [ -f "$src" ]; then
    cp -f "$src" "$STAGE/inputs/$f"
    printf '  %-34s %10s bytes  sha256=%s\n' "$f" "$(stat -c%s "$src")" "$(sha256sum "$src" | cut -c1-32)"
    [ -f "$src.sha256" ] && printf '    (their own .sha256: %s)\n' "$(cut -c1-32 "$src.sha256")"
  fi
done