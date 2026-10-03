#!/bin/bash
# Runs INSIDE the a9build container. Exact resolved toolchain versions for BUILD-LOG.
set -u
echo "=== resolved toolchain ==="
printf '%-14s %s\n' clang    "$(clang --version | head -n 1)"
printf '%-14s %s\n' ld.lld   "$(ld.lld --version | head -n 1)"
printf '%-14s %s\n' llvm-ar  "$(llvm-ar --version | head -n 1)"
printf '%-14s %s\n' llvm-nm  "$(llvm-nm --version | head -n 1)"
printf '%-14s %s\n' make     "$(make --version | head -n 1)"
printf '%-14s %s\n' dtc      "$(dtc --version 2>&1 | head -n 1)"
printf '%-14s %s\n' gcc      "$(gcc --version | head -n 1)"
printf '%-14s %s\n' python3  "$(python3 --version 2>&1)"
printf '%-14s %s\n' flex     "$(flex --version 2>&1 | head -n 1)"
printf '%-14s %s\n' bison    "$(bison --version | head -n 1)"
printf '%-14s %s\n' bc       "$(bc --version | head -n 1)"
printf '%-14s %s\n' gzip     "$(gzip --version | head -n 1)"
echo
echo "=== container identity ==="
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID)='
echo "hostname: $(hostname)"
echo "nproc   : $(nproc)"
echo
echo "=== absent tools that the config does NOT need (recorded so nobody hunts) ==="
for t in pahole lz4 rustc git perl; do
  printf '%-8s %s\n' "$t" "$(command -v $t || echo 'ABSENT')"
done
echo
echo "=== why their absence is fine ==="
grep -E '^# CONFIG_DEBUG_INFO_BTF is not set|^CONFIG_DEBUG_INFO_BTF|^CONFIG_RUST=|^# CONFIG_RUST is not set|^CONFIG_KERNEL_GZIP=|^CONFIG_KERNEL_LZ4=' /build/linux-a9/.config || echo "(none of those symbols are set)"
grep -E '^CONFIG_DEBUG_INFO_BTF|^CONFIG_RUST|^CONFIG_KERNEL_LZ4|^CONFIG_KERNEL_GZIP' /build/linux-a9/.config
echo "=== END ==="
