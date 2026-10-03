#!/usr/bin/env bash
# a9linux/qemu/test-pairing-guard.sh — negative control for the pairing guard.
#
# kernel-engineer's 88-verify-artefact-pairing.ps1 now evaluates all four
# Image x map combinations on every run and claims it "cannot rot silently"
# because the off-diagonal must be rejected. That claim is checkable: build a
# scratch directory whose artefacts are deliberately mis-paired (contents
# swapped between the two pairs) and run THEIR script, unmodified, against it
# with its -Dir parameter. A guard that still passes is a guard with no teeth.
#
# The scratch directory lives inside our own scope and is removed afterwards;
# nothing of theirs is written to.
#
# Usage:  bash test-pairing-guard.sh build     -> create the mis-paired scratch dir
#         bash test-pairing-guard.sh clean     -> remove it
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
D="$STAGE/work-pairtest"
K="$ARLO_ROOT/a9linux/artefacts/kernel"
S="$STAGE/inputs"

case "${1:-build}" in
  build)
    rm -rf "$D"; mkdir -p "$D"
    # swap the contents: each filename now holds the OTHER kernel's artefact
    cp "$S/arlo-Image-qemu-pl011" "$D/Image"
    cp "$K/System.map"            "$D/System.map"
    cp "$S/arlo-Image"            "$D/Image-16k-qemu-pl011"
    cp "$K/System.map-qemu-pl011" "$D/System.map-qemu-pl011"
    echo "scratch dir built with SWAPPED contents (both pairs mis-paired): $D"
    for f in Image System.map Image-16k-qemu-pl011 System.map-qemu-pl011; do
      printf '  %-24s %10s B  sha256=%s\n' "$f" "$(stat -c%s "$D/$f")" "$(sha256sum "$D/$f" | cut -c1-16)"
    done
    echo
    echo "both kernels still have image_size == _end - _text == 0x1370000, so the"
    echo "footprint rule MUST still pass here; only the discriminator can reject these."
    echo
    echo "expected: their script exits non-zero (reporting two rejected mis-pairs)."
    exit 0
    ;;
  clean)
    rm -rf "$D"
    echo "removed $D"
    exit 0
    ;;
  *)
    echo "usage: test-pairing-guard.sh [build|clean]" >&2
    exit 2
    ;;
esac
