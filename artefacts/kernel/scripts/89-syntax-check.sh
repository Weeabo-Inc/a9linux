#!/bin/bash
# 89-syntax-check.sh -- runs on the podman-main VM HOST (or any Linux with E: mounted).
#
# Hygiene pass over the shipped shell scripts, taken from qemu-validator's
# selfcheck.sh idea after they broke one of their own scripts with an in-place edit.
#
# Checks, per file:
#   1. bash -n            -- does it even parse? A typo should not be found by a
#                            half-finished build or a half-finished QEMU run.
#   2. CRLF detection     -- this session repeatedly got CRLF injected when a script
#                            was staged through a PowerShell pipe (`cat > file`). A
#                            .sh with CRLF can pass bash -n and still fail at runtime,
#                            so it is checked explicitly rather than assumed.
#   3. shebang presence   -- a script with no interpreter line cannot be executed.
#
# Read-only. Reports; changes nothing.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

DIR=${1:-/mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel/scripts}

echo "======================================================================"
echo "SCRIPT HYGIENE PASS"
echo "dir: $DIR"
echo "======================================================================"

sh_count=0; py_count=0; fail=0

echo
echo "--- bash -n (parse check) ---"
for f in "$DIR"/*.sh; do
  [ -e "$f" ] || continue
  sh_count=$((sh_count+1))
  b=$(basename "$f")
  if out=$(bash -n "$f" 2>&1); then
    printf '  %-32s OK\n' "$b"
  else
    printf '  %-32s FAIL\n' "$b"
    echo "$out" | sed 's/^/        /'
    fail=$((fail+1))
  fi
done

echo
echo "--- CRLF / line-ending check (.sh must be LF only) ---"
crlf=0
for f in "$DIR"/*.sh; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  if grep -qU $'\r' "$f" 2>/dev/null; then
    printf '  %-32s *** CRLF PRESENT ***\n' "$b"
    crlf=$((crlf+1)); fail=$((fail+1))
  fi
done
[ "$crlf" -eq 0 ] && echo "  no CRLF in any .sh"

echo
echo "--- shebang check (.sh must start with #!) ---"
noshebang=0
for f in "$DIR"/*.sh; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  if [ "$(head -c 2 "$f")" != "#!" ]; then
    printf '  %-32s *** NO SHEBANG ***\n' "$b"
    noshebang=$((noshebang+1)); fail=$((fail+1))
  fi
done
[ "$noshebang" -eq 0 ] && echo "  every .sh has a shebang"

echo
echo "--- Python compile check (if any .py present) ---"
for f in "$DIR"/*.py; do
  [ -e "$f" ] || continue
  py_count=$((py_count+1))
  b=$(basename "$f")
  if python3 -m py_compile "$f" 2>/dev/null; then
    printf '  %-32s OK\n' "$b"
  else
    printf '  %-32s FAIL\n' "$b"; fail=$((fail+1))
  fi
done
[ "$py_count" -eq 0 ] && echo "  no .py files in this directory (expected)"

echo
echo "--- PowerShell script present (checked on Windows, not here) ---"
for f in "$DIR"/*.ps1; do
  [ -e "$f" ] || continue
  printf '  %-32s %s bytes (run 88-...ps1 on Windows)\n' "$(basename "$f")" "$(stat -c %s "$f")"
done

echo
echo "======================================================================"
echo "shell scripts: $sh_count   python: $py_count   problems: $fail"
echo "total files in dir: $(ls -1 "$DIR" | wc -l)"
if [ "$fail" -eq 0 ]; then
  echo "RESULT: PASS -- every shell script parses, is LF-only, and has a shebang."
else
  echo "RESULT: FAIL ($fail problem(s)) -- fix before relying on these scripts."
fi
echo "======================================================================"
exit $fail
