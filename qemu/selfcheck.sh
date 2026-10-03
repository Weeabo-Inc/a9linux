#!/usr/bin/env bash
# a9linux/qemu/selfcheck.sh — syntax-check every script in this directory.
# Cheap, and it stops a typo from being discovered by a half-finished QEMU run.
#
# The CRLF and shebang checks come from kernel-engineer's pass over their own
# scripts, and they earn their place: a .sh with CRLF line endings passes `bash -n`
# and still fails at run time, and this session repeatedly had CRLF injected when a
# file was staged through a PowerShell pipe. On this side I edited
# run-console-variant.sh in place with PowerShell's Set-Content, which is exactly
# that mechanism, so "it parses" is not enough.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
rc=0
echo "=== shell scripts (bash -n, LF-only, shebang) ==="
for f in *.sh; do
  [ -f "$f" ] || continue
  problems=""
  bash -n "$f" 2>/tmp/e || problems="$problems syntax"
  grep -qU $'\r' "$f" 2>/dev/null && problems="$problems CRLF"
  [ "$(head -c 2 "$f")" = "#!" ] || problems="$problems no-shebang"
  if [ -z "$problems" ]; then
    printf '  ok    %s\n' "$f"
  else
    printf '  FAIL  %s  (%s)\n' "$f" "${problems# }"
    sed 's/^/        /' /tmp/e 2>/dev/null
    rc=1
  fi
done
echo "=== python scripts (py_compile, LF-only) ==="
for f in *.py; do
  [ -f "$f" ] || continue
  problems=""
  python3 -m py_compile "$f" 2>/tmp/e || problems="$problems compile"
  grep -qU $'\r' "$f" 2>/dev/null && problems="$problems CRLF"
  if [ -z "$problems" ]; then
    printf '  ok    %s\n' "$f"
  else
    printf '  FAIL  %s  (%s)\n' "$f" "${problems# }"
    sed 's/^/        /' /tmp/e 2>/dev/null
    rc=1
  fi
done
rm -rf __pycache__

echo "=== docs (LF-only, and no stray CRLF from an editor) ==="
for f in *.md; do
  [ -f "$f" ] || continue
  if grep -qU $'\r' "$f" 2>/dev/null; then printf '  FAIL  %s  (CRLF)\n' "$f"; rc=1; else printf '  ok    %s\n' "$f"; fi
done

echo "=== every System.map referenced here must still be paired with its Image ==="
if [ -x "$(command -v bash)" ] && [ -f verify-map-pairing.sh ]; then
  if bash verify-map-pairing.sh >/tmp/pair 2>&1; then
    printf '  ok    verify-map-pairing.sh (%s)\n' "$(grep -m1 'RESULT' /tmp/pair | cut -c1-60)"
  else
    printf '  FAIL  verify-map-pairing.sh -> %s\n' "$(grep -m1 'RESULT' /tmp/pair | cut -c1-80)"
    rc=1
  fi
fi

echo "=== pin agreement: the script is the source of truth, the docs must not drift ==="
# The pins exist to catch a regenerated artefact. They live in the script AND in
# README §2, and two copies of anything is exactly the drift risk this exercise is
# about. So the script's pins are extracted here and required to appear in the README:
# editing the README table alone, or re-pinning the script alone, FAILS this check.
pins=$(grep -oE "'[0-9a-f]{64}'" verify-map-pairing.sh 2>/dev/null | tr -d "'" | sort -u)
np=0
for h in $pins; do
  np=$((np + 1))
  if grep -q "$h" README.md 2>/dev/null; then
    printf '  ok    pin %s… present in README.md\n' "${h:0:16}"
  else
    printf '  FAIL  pin %s… declared in the script but ABSENT from README.md\n' "${h:0:16}"
    rc=1
  fi
done
[ "$np" -eq 0 ] && { echo "  FAIL  no pins found in verify-map-pairing.sh"; rc=1; }
printf '  (%s pin(s) declared in the script)\n' "$np"

echo "=== inventory ==="
printf '  shell: %s   python: %s   docs: %s   logs: %s   dts: %s\n' \
  "$(ls *.sh 2>/dev/null | wc -l)" "$(ls *.py 2>/dev/null | wc -l)" \
  "$(ls *.md 2>/dev/null | wc -l)" "$(ls logs 2>/dev/null | wc -l)" "$(ls dts 2>/dev/null | wc -l)"
exit $rc