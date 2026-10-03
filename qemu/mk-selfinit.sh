#!/usr/bin/env bash
# a9linux/qemu/mk-selfinit.sh — build the harness SELF-TEST initramfs.
#
# Purpose: give the QEMU harness a deterministic, greppable known-good userland
# that (a) proves kernel -> initramfs -> /init works and (b) dumps the kernel's
# OWN view of the device tree it was handed (/proc/device-tree/*) plus the memory
# map it derived (/proc/iomem). That second part is the real value: if we hand
# the kernel our DTB and the kernel reports our compatible string, we have
# measured that the DTB pointer we passed was the DTB the kernel parsed.
#
# This is a HARNESS SELF-TEST, not our rootfs. rootfs-engineer's initramfs
# (task-9) is the real one and is booted by the same harness.
#
# busybox is taken from the existing Hoolock ramdisk at
# a9linux/artefacts/initramfs.gz (musl, aarch64, dynamically linked).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
SRC_RAMDISK="$W/a9linux/artefacts/initramfs.gz"
OUT="$STAGE/inputs/harness-selfinit.cpio.gz"
TREE="$STAGE/work/selfinit"

echo "== [1/4] harvesting busybox + musl loader from the Hoolock ramdisk =="
rm -rf "$STAGE/work/selfsrc" "$TREE"
mkdir -p "$STAGE/work/selfsrc"
( cd "$STAGE/work/selfsrc" && zcat "$SRC_RAMDISK" | cpio -idm --quiet bin/busybox lib/ld-musl-aarch64.so.1 2>/dev/null )
BUSYBOX="$STAGE/work/selfsrc/bin/busybox"
LOADER="$STAGE/work/selfsrc/lib/ld-musl-aarch64.so.1"
[ -f "$BUSYBOX" ] || { echo "FATAL: no busybox in $SRC_RAMDISK" >&2; exit 1; }
file -b "$BUSYBOX"
echo "busybox sha256: $(sha256sum "$BUSYBOX" | cut -d' ' -f1)"

echo "== [2/4] building initramfs tree =="
mkdir -p "$TREE"/{bin,dev,proc,sys,tmp,lib,etc}
cp "$BUSYBOX" "$TREE/bin/busybox"
cp "$LOADER"   "$TREE/lib/ld-musl-aarch64.so.1"
ln -sf ld-musl-aarch64.so.1 "$TREE/lib/libc.musl-aarch64.so.1"
# Device nodes need CAP_MKNOD, which an unprivileged bare-metal run does not
# have (the WSL harness ran as root). The archive is still usable without them:
# this kernel has CONFIG_DEVTMPFS_MOUNT=y and /init mounts devtmpfs on /dev, so
# /dev comes from the kernel at boot. Say so, loudly, instead of failing or
# pretending the nodes are there.
mknod -m 622 "$TREE/dev/console" c 5 1 2>/dev/null || echo "NOTE: no CAP_MKNOD (uid $(id -u)): /dev/console not in the archive; devtmpfs provides it at boot"
mknod -m 666 "$TREE/dev/null"    c 1 3 2>/dev/null || echo "NOTE: no CAP_MKNOD (uid $(id -u)): /dev/null not in the archive; devtmpfs provides it at boot"

cat > "$TREE/init" <<'INIT'
#!/bin/busybox sh
# a9linux/qemu harness self-test /init.  Busybox-only, no external deps.
BB=/bin/busybox
MARK="A9QEMU-SELFTEST"

$BB echo ""
$BB echo "$MARK: BEGIN"
$BB --install -s /bin 2>/dev/null      # applet symlinks, otherwise bare `grep`/`find` do not exist
export PATH=/bin
$BB mount -t proc  proc  /proc 2>/dev/null
$BB mount -t sysfs sysfs /sys  2>/dev/null
$BB mount -t devtmpfs devtmpfs /dev 2>/dev/null

$BB echo "$MARK: uname: $($BB uname -a)"
$BB echo "$MARK: cmdline: $($BB cat /proc/cmdline)"
$BB echo "$MARK: cpus: $(grep -c ^processor /proc/cpuinfo)"

# --- the kernel's own view of the DTB it was handed -------------------------
dtshow() {
  if [ -e "$1" ]; then
    $BB echo "$MARK: dt $1 = $($BB tr -d '\0' < "$1" 2>/dev/null)"
  else
    $BB echo "$MARK: dt $1 = <ABSENT>"
  fi
}
dtshow /proc/device-tree/model
dtshow /proc/device-tree/compatible
dtshow /proc/device-tree/chosen/stdout-path
dtshow /proc/device-tree/chosen/bootargs
if [ -d /proc/device-tree ]; then
  for m in /proc/device-tree/memory*; do
    [ -d "$m" ] || continue
    $BB echo "$MARK: dt $m/device_type = $($BB tr -d '\0' < "$m/device_type" 2>/dev/null)"
    if [ -e "$m/reg" ]; then
      # Print the raw 16 bytes rather than a decoded base/size: busybox hexdump
      # formatting is easy to misread, and a plausible-looking wrong number in a
      # log is this project's recurring injury. Layout is <base_hi base_lo
      # size_hi size_lo>, big-endian cells. The kernel's own authoritative view
      # is the "System RAM" line in the /proc/iomem block below.
      $BB echo "$MARK: dt $m/reg bytes = $($BB hexdump -v -e '16/1 "%02x "' "$m/reg" 2>/dev/null)"
    fi
  done
  if [ -e /proc/device-tree/chosen/initrd-start ]; then
    $BB echo "$MARK: dt /chosen/initrd-start present"
  fi
fi
dtshow /proc/device-tree/interrupt-controller/compatible
$BB echo "$MARK: dt node count = $(ls -d /proc/device-tree/* 2>/dev/null | wc -l) (root children)"

# --- the memory map the kernel actually built ------------------------------
$BB echo "$MARK: ---- /proc/iomem ----"
$BB cat /proc/iomem 2>/dev/null | $BB head -20
$BB echo "$MARK: ---- meminfo ----"
$BB head -3 /proc/meminfo 2>/dev/null

# --- does the console we were told about actually exist? -------------------
for t in /dev/ttyAMA0 /dev/ttyS0 /dev/tty0 /dev/console; do
  if [ -c "$t" ]; then $BB echo "$MARK: console-node $t present"; else $BB echo "$MARK: console-node $t absent"; fi
done

# --- module/virtio probe (what the DT exposed to userspace) ----------------
$BB echo "$MARK: ---- /sys/bus/platform/devices (first 25) ----"
$BB ls /sys/bus/platform/devices 2>/dev/null | $BB head -25

# --- spin-table mailbox probe ---------------------------------------------
# If the bootargs carry mailbox=<hex>, read it. The arm64 spin-table code
# writes the secondary entry address there and then SEVs; seeing a non-zero
# value proves the kernel wrote to the address our DTB named.
MB=$(sed -n 's/.*mailbox=\([0-9a-fx]*\).*/\1/p' /proc/cmdline 2>/dev/null | head -1)
if [ -n "$MB" ]; then
  if [ -e /dev/mem ]; then
    V=$($BB devmem "$MB" 64 2>/dev/null)
    $BB echo "$MARK: spin-table mailbox $MB = ${V:-<READ FAILED>}"
    case "$V" in
      "")
        # A failed read is NOT evidence of absence. On this kernel
        # CONFIG_STRICT_DEVMEM blocks /dev/mem on RAM, so this path proves
        # nothing either way; observe-mailbox.sh reads the same word through
        # QEMU's monitor instead.
        $BB echo "$MARK: mailbox read FAILED (STRICT_DEVMEM?) -> proves nothing about whether the kernel wrote it" ;;
      "0x0"|"0x0000000000000000")
        $BB echo "$MARK: mailbox is ZERO -> the kernel did not park a release address here" ;;
      *)
        $BB echo "$MARK: mailbox WRITTEN -> the kernel wrote a secondary entry address to our cpu-release-addr" ;;
    esac
  else
    $BB echo "$MARK: mailbox $MB requested but /dev/mem is absent (CONFIG_DEVMEM off)"
  fi
fi

# --- console-free userland proof -------------------------------------------
# Our own kernel has no driver for QEMU virt's PL011, so on a QEMU run of OUR
# kernel there is no console at all and "did init run?" is otherwise unanswerable.
# The framebuffer is ordinary RAM at a physical address the host can read through
# QEMU's monitor, so /init stamps a marker into it. Seeing the marker from the
# host proves userland executed; not seeing it proves nothing about why.
if [ -c /dev/fb0 ]; then
  $BB printf 'A9QEMU-USERLAND-MARKER' | $BB dd of=/dev/fb0 bs=64 count=1 conv=notrunc 2>/dev/null
  $BB echo "$MARK: framebuffer marker written to /dev/fb0"
else
  $BB echo "$MARK: no /dev/fb0 (simpledrm did not bind) -> no console-free marker"
fi

$BB echo "$MARK: REACHED-USERLAND"
$BB echo "$MARK: END"
$BB sync
$BB poweroff -f
# if poweroff is unavailable/refused, do not spin forever
$BB echo "$MARK: poweroff returned"
while true; do $BB sleep 5; done
INIT
chmod 755 "$TREE/init"

echo "== [3/4] packing $OUT =="
# Reproducible: fixed mtimes, sorted member order, no gzip name/timestamp. The
# first WSL build embedded the build time, so its hash could never be re-derived
# -- a pin on a file the harness *generates* has to be re-derivable or it is
# decoration. (README section 2 records both hashes.)
find "$TREE" -exec touch -h -t 200001010000 {} + 2>/dev/null || true
( cd "$TREE" && find . | LC_ALL=C sort | cpio -o -H newc --quiet --reproducible | gzip -9n ) > "$OUT"
ls -l "$OUT"
echo "sha256: $(sha256sum "$OUT" | cut -d' ' -f1)"

echo "== [4/4] contents =="
zcat "$OUT" | cpio -tv --quiet 2>/dev/null | head -20

{
  echo "# harness self-test initramfs (NOT our rootfs)"
  echo "generated   = $(date -u +%Y-%m-%dT%H:%M:%SZ) by mk-selfinit.sh"
  echo "sha256      = $(sha256sum "$OUT" | cut -d' ' -f1)"
  echo "busybox_src = a9linux/artefacts/initramfs.gz (Hoolock ramdisk)"
  echo "busybox_sha256 = $(sha256sum "$BUSYBOX" | cut -d' ' -f1)"
} > "$STAGE/inputs/harness-selfinit.PROVENANCE.txt"
cat "$STAGE/inputs/harness-selfinit.PROVENANCE.txt"
echo OK
