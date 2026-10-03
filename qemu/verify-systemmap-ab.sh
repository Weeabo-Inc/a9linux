#!/usr/bin/env bash
# a9linux/qemu/verify-systemmap-ab.sh — verify kernel-engineer's A/B claim and the
# reason the two instruments disagree (System.map 0/62 vs strings 0/20).
#
# They said kallsyms tokenisation compresses symbol names, so a symbol can be in
# the linker map and absent as a literal string. That is checkable, so check it:
# they named pl011_early_write as the case. If it is in the map and not a literal
# in the Image, the explanation holds and BOTH instruments are decisive (0 vs
# non-zero); if it were also a literal, the explanation would be wrong.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
W="$ARLO_ROOT/a9linux/artefacts/kernel"
SHIP_MAP="$W/System.map"
VAR_MAP="$W/System.map-qemu-pl011"
SHIP_IMG="$STAGE/inputs/arlo-Image"
VAR_IMG="$STAGE/inputs/arlo-Image-qemu-pl011"

echo "=== [1] identity of the maps they copied out ==="
for f in "$SHIP_MAP" "$VAR_MAP"; do
  [ -f "$f" ] || { echo "  MISSING $f"; continue; }
  printf '  %-28s %10s B  sha256=%s\n' "$(basename "$f")" "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -d' ' -f1)"
done
echo "  (they quoted: shipping 4,592,199 / 821a3f3a…, variant 4,596,104 / 07408377…)"

echo
echo "=== [2] reproduce the A/B, both instruments ==="
printf '  %-34s %-10s %-10s\n' "instrument" "shipping" "variant"
printf '  %-34s %-10s %-10s\n' "System.map lines 'pl011'" \
  "$(grep -c pl011 "$SHIP_MAP")" "$(grep -c pl011 "$VAR_MAP")"
printf '  %-34s %-10s %-10s\n' "System.map lines 's5l|samsung'" \
  "$(grep -cE 's5l|samsung' "$SHIP_MAP")" "$(grep -cE 's5l|samsung' "$VAR_MAP")"
printf '  %-34s %-10s %-10s\n' "Image strings 'pl011' (case-insens)" \
  "$(strings -a "$SHIP_IMG" | grep -ci pl011)" "$(strings -a "$VAR_IMG" | grep -ci pl011)"
printf '  %-34s %-10s %-10s\n' "Image strings 's5l'" \
  "$(strings -a "$SHIP_IMG" | grep -c s5l)" "$(strings -a "$VAR_IMG" | grep -c s5l)"

echo
echo "=== [3] the kallsyms explanation, tested on the symbol they named ==="
for sym in pl011_early_write pl011_probe pl011_putc; do
  inmap=$(grep -c " $sym\$" "$VAR_MAP")
  instr=$(strings -a "$VAR_IMG" | grep -c "^$sym\$")
  printf '  %-20s in variant System.map=%s   as a literal string in Image=%s\n' "$sym" "$inmap" "$instr"
done
echo "  (expect: present in the map, absent as a literal -> names are tokenised)"
echo "  sample of the literals that DO survive:"
strings -a "$VAR_IMG" | grep -i pl011 | head -6 | sed 's/^/    /'

echo
echo "=== [4] which instrument a reviewer can actually use ==="
echo "  System.map needs the build tree or a copied-out map (now on E:, so citable)."
echo "  The literal count needs only the artefact under test and 'strings'. Both give"
echo "  0 vs non-zero, so the control holds whichever a reviewer has."
