#!/usr/bin/env bash
# a9linux/qemu/resolve-pc.sh <physical-pc> [image-load-base] [system.map]
#
# Map a pre-MMU physical PC back to a kernel symbol. Needs a System.map: pass one
# as $3, or it prefers the repo copies (kernel-engineer copied both out on
# request, so this no longer depends on the Podman VM's build tree). The WSL
# drvfs path and /build/linux-a9 stay as fallbacks.
#
#   shipping kernel : a9linux/artefacts/kernel/System.map           (821a3f3a…)
#   console variant : a9linux/artefacts/kernel/System.map-qemu-pl011 (07408377…)
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
PC="${1:?usage: resolve-pc.sh <phys-pc> [load-base] [system.map]}"
BASE="${2:-0x40080000}"
SM="${3:-}"
if [ -z "$SM" ]; then
  # Repo copy first (both hosts have it); the WSL drvfs copy and the Podman
  # build tree stay as fallbacks for the host that has no checkout.
  for cand in "$W/a9linux/artefacts/kernel/System.map" \
              /mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel/System.map \
              /build/linux-a9/System.map; do
    [ -f "$cand" ] && SM="$cand" && break
  done
fi
[ -n "$SM" ] && [ -f "$SM" ] || { echo "no System.map found (pass one as \$3)" >&2; exit 1; }
echo "  using System.map: $SM"
echo "  sha256          : $(sha256sum "$SM" | cut -d' ' -f1)"

python3 - "$SM" "$PC" "$BASE" <<'PY'
import sys
sm, pc, base = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0)
syms = []
with open(sm) as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 3:
            try:
                syms.append((int(parts[0], 16), parts[1], parts[2]))
            except ValueError:
                pass
syms.sort()
text = [s for s in syms if s[2] == '_text']
if not text:
    print("no _text symbol found"); sys.exit(1)
text_va = text[0][0]
offset = pc - base                      # bytes into the loaded Image
target_va = text_va + offset
print(f"  _text VA        = 0x{text_va:x}")
print(f"  load base       = 0x{base:x}")
print(f"  PC (phys)       = 0x{pc:x}  -> offset 0x{offset:x} into the Image")
print(f"  implied VA      = 0x{target_va:x}")
lo = None
for addr, kind, name in syms:
    if addr <= target_va:
        lo = (addr, kind, name)
    else:
        break
if lo:
    addr, kind, name = lo
    print(f"  nearest symbol  = {name} ({kind}) at 0x{addr:x}, +0x{target_va - addr:x}")
    for addr2, kind2, name2 in syms:
        if addr2 > target_va:
            print(f"  next symbol     = {name2} ({kind2}) at 0x{addr2:x}")
            break
PY
