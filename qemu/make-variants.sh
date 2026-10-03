#!/usr/bin/env bash
# a9linux/qemu/make-variants.sh — build the QEMU-adapted DTB variants and audit them.
# Run (either host):  bash a9linux/qemu/make-variants.sh [dtb]
#   WSL:  wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/make-variants.sh [dtb]
#
# Source DTB defaults to dt-engineer's produced DTB if present, else the upstream
# reference copy at a9linux/dts/ref/dts/s8003-n69.dtb.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
mkdir -p "$STAGE/inputs" "$STAGE/work" "$SCOPE/dts"

SRC="${1:-}"
if [ -z "$SRC" ]; then
  for cand in "$SCOPE/../dts/s8003-n69.dtb" \
              "$SCOPE/../dts/out/s8003-n69.dtb" \
              "$W/a9linux/dts/ref/dts/s8003-n69.dtb"; do
    [ -f "$cand" ] && SRC="$cand" && break
  done
fi
[ -n "$SRC" ] && [ -f "$SRC" ] || { echo "FATAL: no source DTB found (pass one as \$1)" >&2; exit 1; }
echo "SOURCE DTB: $SRC"
echo "SOURCE SHA: $(sha256sum "$SRC" | cut -d' ' -f1)"

# keep a read-only copy of the input inside our own scope for reproducibility
cp -f "$SRC" "$STAGE/inputs/source-n69.dtb"
cp -f "$SRC" "$SCOPE/dts/source-n69.dtb"

for MODE in console fill virt; do
  OUT="$STAGE/inputs/n69-qemu-$MODE.dtb"
  echo
  echo "############ mode=$MODE ############"
  python3 "$SCOPE/adapt-dtb.py" "$STAGE/inputs/source-n69.dtb" "$OUT" --mode "$MODE" \
      --cpu-release-addr 0x40002000 \
    || { echo "adapt failed for mode=$MODE" >&2; continue; }
  python3 "$SCOPE/check-dtb.py" "$OUT" || AUDIT_FAIL=1
done

# keep the reviewable artefacts next to the harness
cp -f "$STAGE/inputs/n69-qemu-"*.dtb "$SCOPE/dts/" 2>/dev/null || true
cp -f "$STAGE/inputs/n69-qemu-"*.transform.txt "$SCOPE/dts/" 2>/dev/null || true
ls -l "$SCOPE/dts/"
