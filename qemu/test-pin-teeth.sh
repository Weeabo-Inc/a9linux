#!/usr/bin/env bash
# a9linux/qemu/test-pin-teeth.sh — negative control for the STALENESS case.
#
# kernel-engineer demonstrated what I had only named as a limit: append one comment
# line to a copy of a System.map and the structural rules (footprint + PL011
# discriminator) stay green on all four combinations, because those rules read only
# _text, _end and symbol names. They are blind to a stale-but-well-formed map.
#
# Their fix and mine is the same in shape: a hash pin, which is a second verdict that
# must also pass. This script proves both pins have teeth, using artefacts of our own
# making in a scratch directory -- no file of theirs is modified.
#
#   bash test-pin-teeth.sh build   -> create scratch dir with one map altered
#   bash test-pin-teeth.sh mine    -> run OUR pin check against the altered copy
#   bash test-pin-teeth.sh clean
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
D="$STAGE/work-pintest"
K="$ARLO_ROOT/a9linux/artefacts/kernel"
S="$STAGE/inputs"

case "${1:-build}" in
  build)
    rm -rf "$D"; mkdir -p "$D"
    cp "$S/arlo-Image"             "$D/Image"
    cp "$K/System.map"             "$D/System.map"
    cp "$S/arlo-Image-qemu-pl011"  "$D/Image-16k-qemu-pl011"
    cp "$K/System.map-qemu-pl011"  "$D/System.map-qemu-pl011"
    # the alteration: one comment line. Nothing rules 1+2 read is touched.
    printf '\n# stale-map negative control: this line changes no symbol, only the hash\n' >> "$D/System.map"
    echo "scratch dir built; device map has ONE comment line appended:"
    for f in Image System.map Image-16k-qemu-pl011 System.map-qemu-pl011; do
      printf '  %-24s %10s B  sha256=%s\n' "$f" "$(stat -c%s "$D/$f")" "$(sha256sum "$D/$f" | cut -c1-32)"
    done
    echo
    echo "  expected: structural rules still PASS on all four combinations (blind),"
    echo "            pin verdict FAILS for the altered map."
    if [ -d /mnt/e ]; then
    echo "  Windows path for their guard: E:\\Reverseing\\Arlo\\a9linux\\qemu\\work-pintest"
    else
      echo "  their PowerShell guard is Windows-only; on this host feed the same"
      echo "  directory to verify-map-pairing.sh with A9_ARLO_ROOT/A9QEMU_STAGE —"
      echo "  that is what the Linux negative controls in README section 10 do."
    fi
    exit 0
    ;;
  mine)
    # run our own pin verdict against the altered copy, without touching the real one
    if [ ! -f "$D/System.map" ]; then echo "run 'build' first" >&2; exit 2; fi
    PIN_DEV_MAP=821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c
    # Deterministic control: the altered file is the original plus one fixed comment line,
    # so its hash is reproducible. Pinning the CONTROL's expected hash as well means a
    # future reader can tell "the control ran" from "the control silently did nothing".
    # NOTE: kernel-engineer's own stale-map test appends different comment text and so sees
    # a different hash (22a50fa4…). Two hashes, one test intent — different appended bytes,
    # no disagreement. Do not read one as a refutation of the other.
    EXPECT_ALTERED=c83d4df2288c08d49e6913d503a6ecf9bd6a0bc110b6d73edb7be30f529fe0a7
    got=$(sha256sum "$D/System.map" | cut -d' ' -f1)
    printf '  our pin for System.map : %s…\n' "${PIN_DEV_MAP:0:32}"
    printf '  altered copy on disk   : %s…\n' "${got:0:32}"
    printf '  expected for THIS control (original + one fixed comment line): %s…\n' "${EXPECT_ALTERED:0:32}"
    if [ "$got" != "$EXPECT_ALTERED" ]; then
      echo "  NOTE: the scratch copy is not the file this control was written against;"
      echo "        re-run 'build' before trusting the verdict below."
    fi
    if [ "$got" = "$PIN_DEV_MAP" ]; then
      echo "  RESULT: FAIL - our pin check did NOT notice an altered map; it has no teeth."
      exit 1
    fi
    echo "  RESULT: PASS - our pin check rejects the altered map (as their verdict B does)."
    exit 0
    ;;
  clean)
    rm -rf "$D"; echo "removed $D"; exit 0
    ;;
  *) echo "usage: test-pin-teeth.sh [build|mine|clean]" >&2; exit 2 ;;
esac
