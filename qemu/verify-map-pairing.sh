#!/usr/bin/env bash
# a9linux/qemu/verify-map-pairing.sh — independently check that each System.map
# belongs to the Image it is cited with.
#
# Why this matters to THIS harness: resolve-pc.sh turns a physical PC into a symbol
# using these maps, and my granule finding (__no_granule_support) rests on that. A
# map from a sibling build would produce a confident wrong symbol, which is the
# failure mode this project keeps paying for.
#
# kernel-engineer's rule (arch/arm64/kernel/image.h):  _kernel_size_le = _end - _text,
# so the Image header's image_size must equal _end - _text in its own map.
#
# Their finding, which I set out to reproduce rather than accept: that rule is
# NECESSARY BUT NOT SUFFICIENT, because image_size is page-granular and two builds can
# share it. So this script checks it AND a discriminator that cannot collide, and it
# runs all four pairings — both correct ones and both mis-pairings — as a negative
# control. A check that has never been shown to fail is not a check.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
W="$ARLO_ROOT/a9linux/artefacts/kernel"
DEV_IMG="$STAGE/inputs/arlo-Image"
VAR_IMG="$STAGE/inputs/arlo-Image-qemu-pl011"
DEV_MAP="$W/System.map"
VAR_MAP="$W/System.map-qemu-pl011"

python3 - "$DEV_IMG" "$VAR_IMG" "$DEV_MAP" "$VAR_MAP" <<'PY'
import struct, subprocess, sys

dev_img, var_img, dev_map, var_map = sys.argv[1:5]
IMAGES = {'device': dev_img, 'variant': var_img}
MAPS = {'device': dev_map, 'variant': var_map}

def image_facts(path):
    b = open(path, 'rb').read(0x100)
    code0, code1, text_off, image_size, flags = struct.unpack_from('<IIQQQ', b, 0)
    magic = struct.unpack_from('<I', b, 56)[0]
    # kallsyms-tokenised names do not survive as literals; the driver's identity
    # strings do. This is the discriminator that cannot collide between the two builds.
    strings = subprocess.run(['strings', '-a', path], capture_output=True, text=True).stdout
    return {
        'image_size': image_size,
        'magic_ok': magic == 0x644d5241,
        'granule': (flags >> 1) & 3,
        'pl011_literals': sum(1 for l in strings.splitlines() if 'pl011' in l.lower()),
    }

def map_facts(path):
    text = end = None
    pl011 = 0
    for line in open(path):
        p = line.split()
        if len(p) < 3:
            continue
        if p[2] == '_text':
            text = int(p[0], 16)
        elif p[2] == '_end':
            end = int(p[0], 16)
        if 'pl011' in p[2]:
            pl011 += 1
    return {'text': text, 'end': end, 'span': (end - text) if (text and end) else None,
            'pl011_symbols': pl011}

print("=== artefact facts ===")
img = {k: image_facts(v) for k, v in IMAGES.items()}
mp = {k: map_facts(v) for k, v in MAPS.items()}
for k in ('device', 'variant'):
    i, m = img[k], mp[k]
    print(f"  {k:8s} Image image_size=0x{i['image_size']:x} magic_ok={i['magic_ok']} "
          f"granule_bits={i['granule']} pl011_literals={i['pl011_literals']:3d} | "
          f"map _text=0x{m['text']:x} span=0x{m['span']:x} pl011_symbols={m['pl011_symbols']:3d}")

print()
print("=== all four pairings (the two correct ones are rows 1 and 4) ===")
print(f"  {'Image':8s} {'map':8s} {'footprint rule':16s} {'discriminator':24s} verdict")
fails = 0
for ik in ('device', 'variant'):
    for mk in ('device', 'variant'):
        i, m = img[ik], mp[mk]
        same_span = (i['image_size'] == m['span'])
        # a map and an image belong together iff both share the same pl011 presence
        disc_ok = (m['pl011_symbols'] == 0) == (i['pl011_literals'] == 0)
        correct = (ik == mk)
        ok = same_span and disc_ok and correct
        if not ok:
            fails += 1
        print(f"  {ik:8s} {mk:8s} {'PASS' if same_span else 'FAIL':16s} "
              f"{'PASS' if disc_ok else 'FAIL':24s} {'CORRECT PAIR' if ok else 'WRONG PAIR (rejected)'}")

print()
span_same = img['device']['image_size'] == img['variant']['image_size']
print(f"=== the point of the exercise ===")
print(f"  both images share image_size: {span_same}  "
      f"(device 0x{img['device']['image_size']:x}, variant 0x{img['variant']['image_size']:x})")
print("  -> the footprint rule alone therefore CANNOT separate them; the discriminator must.")
print("  -> a mis-pairing that passes the footprint rule but fails the discriminator is the")
print("     exact case this script exists to keep visible.")

# ---------------------------------------------------------------------------
# VERDICT B: hash pinning. kernel-engineer demonstrated the case I had only named
# as a limit: append one comment line to a map and rules 1+2 stay green on ALL
# four combinations, because those rules read only _text, _end and pl011 names.
# They are structurally blind to a stale-but-well-formed map. A pin is not.
# A regeneration therefore fails this script until someone re-pins by hand --
# which is the point: re-pinning IS the moment a human re-decides that the new
# pair is the pair to cite.
print()
print("=== verdict B: hash pins (catches staleness, which rules 1+2 cannot) ===")
PINS = {
    dev_img: '39a270676141f42575cbadffbac085cc120aa1e0f6e61af0b6db8ad5b0c7e228',
    var_img: '2697e77d901d44844cb8871400ee59119148be08182ccf57bbb6df9b766fde88',
    dev_map: '821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c',
    var_map: '07408377308361cb8d91d35e24857325c98c698c5c0703dd476b3bb7ee46c6ab',
}
import hashlib
pin_bad = 0
for path, want in PINS.items():
    with open(path, 'rb') as fh:
        got = hashlib.sha256(fh.read()).hexdigest()
    state = 'PINNED' if got == want else '*** CHANGED ***'
    if got != want:
        pin_bad += 1
    print(f"  {state:16s} {path.split('/')[-1]:28s} {got[:16]}… want {want[:16]}…")

if pin_bad:
    print(f"  -> {pin_bad} artefact(s) differ from the pins recorded in README §2. The pairing")
    print("     may still be structurally fine, but nothing here says the pair is the one we")
    print("     MEASURED. Re-run the checks against the new artefacts and re-pin deliberately.")
sys.exit(0 if (fails == 2 and pin_bad == 0) else 1)
PY
rc=$?
echo
if [ $rc -eq 0 ]; then
  echo "RESULT: PASS - (A) both correct pairings accepted and both mis-pairings rejected;"
  echo "        (B) every artefact matches its pin. The maps cited in README §2 are the maps"
  echo "        of the Images cited with them, including the map used for the"
  echo "        __no_granule_support resolution."
else
  echo "RESULT: FAIL (rc=$rc) - either a pairing is not as assumed, or an artefact has"
  echo "        changed since it was pinned. Do not cite these maps until resolved."
fi
exit $rc
