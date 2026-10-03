#!/bin/bash
# Runs on the podman-main VM HOST (not in the container).
# Blocks until the kernel build finishes, then reports.
for i in $(seq 1 300); do
  if [ -f /build/kbuild.exit ]; then
    echo "=== BUILD FINISHED after ~$((i*15))s of waiting ==="
    break
  fi
  sleep 15
done

echo "--- exit code file ---"
if [ -f /build/kbuild.exit ]; then
  echo "EXIT=$(cat /build/kbuild.exit)"
else
  echo "TIMEOUT: /build/kbuild.exit never appeared"
fi

echo "--- last 30 log lines ---"
tail -n 30 /build/kbuild.log

echo "--- artefacts ---"
ls -la /build/linux-a9/arch/arm64/boot/Image \
       /build/linux-a9/arch/arm64/boot/Image.gz \
       /build/linux-a9/arch/arm64/boot/dts/apple/s8003-n69.dtb 2>&1
