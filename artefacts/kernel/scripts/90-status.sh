#!/bin/bash
# Runs on the podman-main VM host. Poll helper.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
echo "--- clean rebuild log ---"
ls -la /build/kbuild-clean.log /build/kbuild-clean.exit 2>&1
echo "--- exit code ---"
cat /build/kbuild-clean.exit 2>/dev/null || echo NOT_FINISHED_YET
echo "--- tail ---"
tail -n 6 /build/kbuild-clean.log 2>/dev/null || echo "(no log yet)"
echo "--- counters ---"
if [ -f /build/kbuild-clean.log ]; then
  echo "lines=$(wc -l < /build/kbuild-clean.log)"
  echo "CC=$(grep -c 'CC ' /build/kbuild-clean.log)"
fi
echo "--- phase markers ---"
grep -n -E "object census|stashed|mtime sanity|make LLVM=1 ARCH=arm64 clean" /build/kbuild-clean.log 2>/dev/null | head -n 10
echo "--- incremental stash ---"
ls -la /build/kb-incremental/ 2>&1
echo "--- objects now in tree ---"
find /build/linux-a9 -name '*.o' 2>/dev/null | wc -l
echo "--- make alive? ---"
pgrep -c make 2>/dev/null || echo 0
