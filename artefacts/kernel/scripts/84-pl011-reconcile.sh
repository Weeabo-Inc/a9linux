#!/bin/bash
# Runs INSIDE the a9build container.
# (1) Reconcile the two PL011 A/B counts so 62 vs 20 is not left looking like a
#     disagreement. (2) Produce the variant System.map so the claim is citable.
set -u

SHIP=/build/linux-a9
VAR=/build/linux-a9-qemu
SHIP_IMG=$SHIP/arch/arm64/boot/Image
VAR_IMG=$VAR/arch/arm64/boot/Image

echo "########################################################################"
echo "# Instrument 1: System.map symbols (the LINKER's symbol table)         #"
echo "########################################################################"
printf '%-34s %s\n' "shipping System.map pl011 lines:" "$(grep -c -i pl011 $SHIP/System.map)"
printf '%-34s %s\n' "variant  System.map pl011 lines:" "$(grep -c -i pl011 $VAR/System.map)"
printf '%-34s %s\n' "shipping System.map s5l/samsung:" "$(grep -c -i 's5l\|samsung' $SHIP/System.map)"
printf '%-34s %s\n' "variant  System.map s5l/samsung:" "$(grep -c -i 's5l\|samsung' $VAR/System.map)"

echo
echo "########################################################################"
echo "# Instrument 2: plain strings in the Image (what qemu-validator used)  #"
echo "########################################################################"
printf '%-34s %s\n' "shipping Image pl011 strings:" "$(strings $SHIP_IMG | grep -c -i pl011)"
printf '%-34s %s\n' "variant  Image pl011 strings:" "$(strings $VAR_IMG | grep -c -i pl011)"
printf '%-34s %s\n' "shipping Image s5l/samsung strings:" "$(strings $SHIP_IMG | grep -c -i 's5l\|samsung')"
printf '%-34s %s\n' "variant  Image s5l/samsung strings:" "$(strings $VAR_IMG | grep -c -i 's5l\|samsung')"

echo
echo "--- WHY the two instruments differ: kallsyms names are COMPRESSED, so"
echo "--- most symbol names never appear as plain strings in the Image ---"
echo "variant Image: is 'pl011_early_write' findable as a plain string?"
if strings $VAR_IMG | grep -q 'pl011_early_write'; then echo "  yes"; else echo "  NO -> confirms kallsyms compression"; fi
echo "variant System.map: is it there?"
grep -q 'pl011_early_write' $VAR/System.map && echo "  yes (symbol table is uncompressed)" || echo "  no"
echo
echo "--- what the pl011 strings in the Image actually ARE ---"
strings $VAR_IMG | grep -i pl011 | sort -u | head -n 25
echo
echo "--- and confirm the A/B is decisive under BOTH instruments ---"
S1=$(grep -c -i pl011 $SHIP/System.map); V1=$(grep -c -i pl011 $VAR/System.map)
S2=$(strings $SHIP_IMG | grep -c -i pl011); V2=$(strings $VAR_IMG | grep -c -i pl011)
S1=${S1:-0}; V1=${V1:-0}; S2=${S2:-0}; V2=${V2:-0}
echo "  System.map : shipping=$S1 variant=$V1 -> $( [ "$S1" -eq 0 ] && [ "$V1" -gt 0 ] && echo 'DECISIVE (0 vs non-zero)' || echo 'CHECK')"
echo "  strings    : shipping=$S2 variant=$V2 -> $( [ "$S2" -eq 0 ] && [ "$V2" -gt 0 ] && echo 'DECISIVE (0 vs non-zero)' || echo 'CHECK')"

echo
echo "########################################################################"
echo "# Variant System.map, for citation                                    #"
echo "########################################################################"
ls -la $VAR/System.map
sha256sum $VAR/System.map
echo "lines: $(wc -l < $VAR/System.map)"
echo "=== END ==="
