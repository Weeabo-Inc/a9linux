#!/usr/bin/env bash
# a9linux/qemu/test-doc-agreement-guard.sh — negative control for verdict (C),
# doc-vs-enforcement drift.
#
# kernel-engineer added (C): every pin in their script must also appear in
# BUILD-LOG.md, so editing either side alone fails. Their doc path is derived from
# the same -Dir parameter as the artefacts, which makes the failure reachable
# without touching anything of theirs: copy the artefacts and the doc into a
# scratch directory, corrupt ONE pin in the DOC COPY only, and run their script.
#
#   bash test-doc-agreement-guard.sh build
#   bash test-doc-agreement-guard.sh clean
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
D="$STAGE/work-doctest"
K="$ARLO_ROOT/a9linux/artefacts/kernel"
S="$STAGE/inputs"
PIN_DEV_MAP=821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c

case "${1:-build}" in
  build)
    rm -rf "$D"; mkdir -p "$D"
    cp "$S/arlo-Image"            "$D/Image"
    cp "$K/System.map"            "$D/System.map"
    cp "$S/arlo-Image-qemu-pl011" "$D/Image-16k-qemu-pl011"
    cp "$K/System.map-qemu-pl011" "$D/System.map-qemu-pl011"
    if [ ! -f "$K/BUILD-LOG.md" ]; then echo "FATAL: $K/BUILD-LOG.md not found" >&2; exit 1; fi
    cp "$K/BUILD-LOG.md" "$D/BUILD-LOG.md"

    echo "scratch dir built. artefacts are CORRECT; only the DOC copy is corrupted."
    printf '  device-map pin as stated in the real doc : %s\n' \
      "$(grep -c "$PIN_DEV_MAP" "$K/BUILD-LOG.md") occurrence(s)"
    # corrupt exactly one pin in the DOC COPY (the device map's), nothing else
    sed -i "s/$PIN_DEV_MAP/0000000000000000000000000000000000000000000000000000000000000000/" "$D/BUILD-LOG.md"
    printf '  after corruption in the copy            : %s occurrence(s)\n' \
      "$(grep -c "$PIN_DEV_MAP" "$D/BUILD-LOG.md")"
    echo
    echo "  expected: (A) pairing PASS, (B) pinning PASS (artefacts are genuine),"
    echo "            (C) doc agreement FAILS for System.map -- that is the point."
    if [ -d /mnt/e ]; then
    echo "  Windows path for their guard: E:\\Reverseing\\Arlo\\a9linux\\qemu\\work-doctest"
    else
      echo "  their PowerShell guard is Windows-only; on this host feed the same"
      echo "  directory to verify-map-pairing.sh with A9_ARLO_ROOT/A9QEMU_STAGE —"
      echo "  that is what the Linux negative controls in README section 10 do."
    fi
    exit 0
    ;;
  clean)
    rm -rf "$D"; echo "removed $D"; exit 0
    ;;
  *) echo "usage: test-doc-agreement-guard.sh [build|clean]" >&2; exit 2 ;;
esac
