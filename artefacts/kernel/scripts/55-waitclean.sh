#!/bin/bash
# Runs on the podman-main VM host. Blocks until the CLEAN build finishes.
for i in $(seq 1 300); do
  if [ -f /build/kbuild-clean.exit ]; then
    echo "=== CLEAN BUILD FINISHED after ~$((i*15))s of waiting ==="
    break
  fi
  sleep 15
done
if [ -f /build/kbuild-clean.exit ]; then
  echo "EXIT=$(cat /build/kbuild-clean.exit)"
else
  echo "TIMEOUT: /build/kbuild-clean.exit never appeared"
fi
echo "--- tail of clean build log ---"
tail -n 40 /build/kbuild-clean.log
