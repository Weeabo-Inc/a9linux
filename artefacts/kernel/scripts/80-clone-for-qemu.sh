#!/bin/bash
# Runs on the podman-main VM HOST (needs git; the container has none).
# Makes a PRISTINE checkout at the same commit so the QEMU variant can be built
# without touching the shipping tree's .config or Image in any way.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

SRC=/build/linux-a9
DST=/build/linux-a9-qemu

echo "############ shipping tree (must remain untouched) ############"
echo "HEAD              : $(git -C $SRC rev-parse HEAD)"
echo "branch            : $(git -C $SRC rev-parse --abbrev-ref HEAD)"
echo "dirty files       : $(git -C $SRC status --porcelain | wc -l)"
echo ".config sha256    : $(sha256sum $SRC/.config | cut -d' ' -f1)"
echo "Image sha256      : $(sha256sum $SRC/arch/arm64/boot/Image | cut -d' ' -f1)"

echo
echo "############ create pristine clone for the QEMU variant ############"
if [ -d "$DST/.git" ]; then
  echo "clone already present, leaving it alone"
else
  git clone --local --branch hoolock "$SRC" "$DST" 2>&1 | tail -n 5
fi

echo
echo "############ verify the clone ############"
echo "HEAD              : $(git -C $DST rev-parse HEAD)"
echo "branch            : $(git -C $DST rev-parse --abbrev-ref HEAD)"
echo "dirty files       : $(git -C $DST status --porcelain | wc -l)  (expect 0 = pristine)"
echo "has .config?      : $([ -f $DST/.config ] && echo 'YES - PROBLEM' || echo 'no - as expected')"
echo "has build output? : $(find $DST -name '*.o' 2>/dev/null | wc -l) object files (expect 0)"
echo
if [ "$(git -C $SRC rev-parse HEAD)" = "$(git -C $DST rev-parse HEAD)" ]; then
  echo ">>> PASS: clone is at exactly the shipping commit"
else
  echo ">>> FAIL: commit mismatch -- refusing to proceed"
  exit 1
fi
echo
echo "############ re-verify shipping tree AFTER the clone ############"
echo ".config sha256    : $(sha256sum $SRC/.config | cut -d' ' -f1)"
echo "Image sha256      : $(sha256sum $SRC/arch/arm64/boot/Image | cut -d' ' -f1)"
echo "=== END ==="
