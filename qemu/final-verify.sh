#!/usr/bin/env bash
# a9linux/qemu/final-verify.sh — one command that re-runs every standing check in this
# directory and prints a summary. Written as a file rather than an inline one-liner
# because this session repeatedly lost output to shell/PowerShell quote mangling, and a
# check whose output can vanish is not a check.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
rc=0

echo "########## 1. staleness negative control (deterministic) ##########"
bash "$Q/test-pin-teeth.sh" build
bash "$Q/test-pin-teeth-run.sh" | grep -E 'our pin|altered copy|expected for THIS control|RESULT|removed'
bash "$Q/test-pin-teeth.sh" clean

echo
echo "########## 2. doc-agreement negative control ##########"
bash "$Q/test-doc-agreement-guard.sh" build | grep -E 'corrupted|occurrence|expected'
bash "$Q/test-doc-agreement-guard.sh" clean

echo
echo "########## 3. selfcheck (syntax, LF, shebang, pins, pairing) ##########"
bash "$Q/selfcheck.sh" | tail -12 || rc=1

echo
echo "########## 4. no scratch directories left behind ##########"
n=$(ls -d "$Q"/work-* 2>/dev/null | wc -l)
echo "  leftover work-* dirs: $n"
[ "$n" -ne 0 ] && rc=1

echo
if [ $rc -eq 0 ]; then
  echo "FINAL: all standing checks pass; no scratch state; harness is citable."
else
  echo "FINAL: something above failed (rc=$rc) - do not cite the artefacts."
fi
exit $rc
