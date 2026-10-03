#!/bin/bash
# Runs on the podman-main VM host. Blocks until the QEMU variant build finishes.
for i in $(seq 1 300); do
  if [ -f /build/kbuild-qemu-pl011.exit ]; then
    echo "=== QEMU VARIANT BUILD FINISHED after ~$((i*15))s of waiting ==="
    break
  fi
  sleep 15
done
if [ -f /build/kbuild-qemu-pl011.exit ]; then
  echo "EXIT=$(cat /build/kbuild-qemu-pl011.exit)"
else
  echo "TIMEOUT: /build/kbuild-qemu-pl011.exit never appeared"
fi
echo "--- tail of the QEMU variant build log ---"
tail -n 30 /build/kbuild-qemu-pl011.log
