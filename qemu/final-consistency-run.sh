#!/usr/bin/env bash
# a9linux/qemu/final-consistency-run.sh — regenerate every result the README quotes,
# in one go, on the shipped scripts. Run this after any script edit; a report
# measured before a final edit is stale (HANDOFF §9.7).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
S="$STAGE"
mkdir -p "$S/inputs" "$S/logs"

echo "########## rebuilding harness pieces ##########"
bash "$Q/mk-selfinit.sh" | tail -1
bash "$Q/mk-handoff-stub.sh" | head -2
bash "$Q/make-variants.sh" > "$S/logs/00-make-variants.log" 2>&1
echo "selfinit   sha256: $(sha256sum "$S/inputs/harness-selfinit.cpio.gz" | cut -d' ' -f1)"
echo "stub       sha256: $(sha256sum "$S/inputs/handoff-stub.bin" | cut -d' ' -f1)"

echo
echo "########## ladder ##########"
bash "$Q/run-ladder.sh" 2>&1 | grep -E 'RESULT|###|console_bytes|ladder'

echo
echo "########## hand-off (stub) ##########"
bash "$Q/run-stub.sh" 2>&1 | grep -E 'RESULT|\[stub\]|Brought up|CPU1:|audit|FAIL|PASS' | head -20

echo
echo "########## our kernel: granule sweep ##########"
bash "$Q/granule-sweep.sh" 2>&1 | grep -E '####|=>|status word|console bytes'

echo
echo "########## self-test evidence in the hand-off log ##########"
grep -a 'A9QEMU-SELFTEST' "$S/logs/05-loader-stub-handoff.log" | head -20

echo
echo "########## static gate on every DTB we have ##########"
for d in "$S/inputs/source-n69.dtb" "$S/inputs/n69-loader-target.dtb" \
         "$S/inputs/n69-qemu-console.dtb" "$S/inputs/n69-qemu-fill.dtb" "$S/inputs/n69-qemu-virt.dtb"; do
  [ -f "$d" ] || continue
  printf '%-34s ' "$(basename "$d")"
  python3 "$Q/check-dtb.py" "$d" 2>/dev/null | grep -E 'RESULT for' | sed 's/^ *//'
done
true
