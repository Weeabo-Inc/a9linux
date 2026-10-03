#!/bin/bash
# Runs on the podman-main VM host.
# Fresh end-to-end re-verification, staged from the scripts SHIPPED on E:.
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

SRC=/mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel/scripts
echo "=== staging shipped scripts fresh from E: into /build/a9scripts ==="
rm -rf /build/a9scripts
mkdir -p /build/a9scripts
cp -f "$SRC"/*.sh /build/a9scripts/
chmod +x /build/a9scripts/*.sh
echo "staged: $(ls /build/a9scripts | wc -l) scripts"

echo
echo "=== md5 of the staged scripts vs E: (must be identical) ==="
for f in /build/a9scripts/*.sh; do
  b=$(basename "$f")
  a=$(md5sum "$f" | cut -d' ' -f1)
  c=$(md5sum "$SRC/$b" | cut -d' ' -f1)
  if [ "$a" = "$c" ]; then s=OK; else s=DIFFERS; fi
  printf '  %-24s %s\n' "$b" "$s"
done

echo
echo "=== FINAL VERIFICATION RUN (shipped script, unmodified) ==="
podman exec a9build bash /build/a9scripts/40-verify-image.sh 2>&1 | \
  grep -E '^>>>|PAGE-SIZE VERDICT|^from \.config|^EXPECTED|^observed|^expected bits|^flags |^file size|^image_size|^magic |stride|^#define CONFIG_ARM64_16K_PAGES|^#define CONFIG_PAGE_SIZE_16KB|^15:#define|^374:#define|warnings:|errors:|^39a|^3eef|^cbb|^eaee'

echo
echo "=== E: artefact listing ==="
ls -la /mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel/
