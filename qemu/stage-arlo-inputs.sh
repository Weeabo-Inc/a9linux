#!/usr/bin/env bash
# a9linux/qemu/stage-arlo-inputs.sh — pull the other engineers' artefacts into the
# harness staging area and report what we got. Read-only against their scopes.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
mkdir -p "$STAGE/inputs"

copy() { # src dst label
  if [ -f "$1" ]; then
    cp -f "$1" "$2"
    printf 'OK   %-26s %10s bytes  sha256=%s\n' "$3" "$(stat -c%s "$2")" "$(sha256sum "$2" | cut -c1-16)"
  else
    printf 'MISS %-26s (%s)\n' "$3" "$1"
  fi
}

copy "$W/a9linux/artefacts/kernel/Image"                "$STAGE/inputs/arlo-Image"            "kernel-engineer Image"
copy "$W/a9linux/artefacts/kernel/Image.gz"             "$STAGE/inputs/arlo-Image.gz"         "kernel-engineer Image.gz"
copy "$W/a9linux/dts/n69-loader-target.dtb"             "$STAGE/inputs/n69-loader-target.dtb" "dt-engineer DTB"
copy "$W/debian-ios/dist/arlo-initramfs-min.cpio.gz"    "$STAGE/inputs/arlo-initramfs-min.cpio.gz"    "rootfs min initramfs"
copy "$W/debian-ios/dist/arlo-initramfs-debian.cpio.gz" "$STAGE/inputs/arlo-initramfs-debian.cpio.gz" "rootfs debian initramfs"

echo
echo "=== page granule of our Image (file(1) reports the granule from the header) ==="
file -b "$STAGE/inputs/arlo-Image"
echo
echo "=== kernel config facts that decide whether it can boot on QEMU virt ==="
CFG="$W/a9linux/artefacts/kernel/config.used"
for k in CONFIG_ARM64_16K_PAGES CONFIG_ARM64_4K_PAGES CONFIG_ARM64_64K_PAGES \
         CONFIG_SERIAL_AMBA_PL011 CONFIG_SERIAL_AMBA_PL011_CONSOLE CONFIG_SERIAL_EARLYCON \
         CONFIG_SERIAL_APPLE CONFIG_DRM_SIMPLEDRM CONFIG_SYSFB_SIMPLEFB CONFIG_FB \
         CONFIG_BLK_DEV_INITRD CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT CONFIG_ARCH_APPLE \
         CONFIG_ARM_PSCI_FW CONFIG_PSCI_CHECKER CONFIG_PROC_FS CONFIG_SYSFS; do
  line=$(grep -E "^$k=|^# $k is not set" "$CFG" 2>/dev/null | head -1)
  printf '  %-34s %s\n' "$k" "${line:-<absent from config.used>}"
done
