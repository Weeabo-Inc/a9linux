# `a9linux/dts/` — the n69ap device-tree workstream

**Owner:** `dt-engineer` · **Task:** `task-7` · **Date:** 2026-10-03
**Scope:** everything in this directory. `a9linux/artefacts/kernel/` belongs to `kernel-engineer`,
`a9boot/` to `a9boot-engineer`, `debian-ios/` to `rootfs-engineer` — read-only from here.

---

## Start here

| If you want to… | Read |
|---|---|
| know **where console output will actually appear** | [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) |
| know **exactly what the loader must write into the DTB** | [LOADER-FILL.md](LOADER-FILL.md) |
| know **what is wrong with the DTB as built** | [PLACEHOLDER-INVENTORY.md](PLACEHOLDER-INVENTORY.md) |
| run **the first-pwned-session measurements** | [LOADER-FILL.md](LOADER-FILL.md) §12 — numbered, mechanical |
| know **the exact bootargs string** | [LOADER-FILL.md](LOADER-FILL.md) §4.1 |

**The four answers, up front:**

1. **The device tree needs no patch to reach a serial console.** `stdout-path` is wired to
   `serial0`, the alias exists, the UART node is `status = "okay"`, and its driver and early console
   are compiled in. MEASURED from the built DTB, not assumed from the sources. **No patched DTB was
   needed for the console** — the target DTB below exists as a diff target and test vector instead.
2. **The loader must still fill four things or the kernel cannot boot**: `memory/reg` (currently
   size **0**), `bootargs` (currently **absent**), and `linux,initrd-start`/`-end` (absent). A fifth
   placeholder — the AUSB PHY tunables — was missing from every earlier list; **as of `task-13` it is
   measured and filled** ([AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)), so it no longer blocks the USB
   console.
3. **The physical UART is probably unreachable**, so a green boot is currently unfalsifiable. The
   cheapest new observable channel is a **USB gadget console** over the cable already plugged in; its
   blocker was four PHY values *read back from live registers* (§12 step 2) — **now measured and in
   the DTB**; what remains is the boot itself and the userspace configfs gadget.
4. **The final bootargs string is**
   `console=ttySAC0 console=ttyGS0 nokaslr clk_ignore_unused pd_ignore_unused panic=20` — and the
   two non-obvious decisions behind it are that `ttyGS0` must be **last** (it becomes `/dev/console`)
   and that **`earlycon` must be absent** (it would clear `CON_PRINTBUFFER` on the gadget and make it
   replay nothing). Both are derived in [LOADER-FILL.md](LOADER-FILL.md) §4.2–4.3.

---

## Artefacts

| File | What it is |
|---|---|
| [LOADER-FILL.md](LOADER-FILL.md) | **The contract.** DRAM map, the exact property writes, the bootargs string, the CPU-release rules, what the loader must do that no DT property can express, and every INFERRED value ranked by boot risk |
| [PLACEHOLDER-INVENTORY.md](PLACEHOLDER-INVENTORY.md) | Every loader-owned property with its as-built value, plus the early-boot node audit and a list of things that are *not* placeholders |
| [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) | Where output can be seen, what each channel proves, and what it costs |
| [n69-loader-target.dts](n69-loader-target.dts) | The target DTB in source form — the built DTB plus the four example fills, annotated, **and (after `task-13`) the four MEASURED `ausbphy0` tunables** |
| [n69-loader-target.dtb](n69-loader-target.dtb) | Same, compiled: **23,193 B**, sha256 `1b0ff193…`. **Use as a diff target for a9boot's patcher, not as a flashable image** |
| [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) | The `ausbphy0` fill: measured values, before/after hashes, the decompiled node, the host-pair decision, and what could not be verified without hardware |
| [build/build-dtb.sh](build/build-dtb.sh) | Reproducible build recipe. `verify` proves it reproduces the tree's DTB byte-for-byte; `target` rebuilds and read-back checks this one |
| [build/check-ausbphy-node.sh](build/check-ausbphy-node.sh) | Checks the **compiled blob** (exact node path + whole property names, then a raw FDT walk) for the four tunables; exits non-zero if absent or wrong. Its header records the two spoofs that forced the stricter matching |
| [build/verify-bootargs-claims.sh](build/verify-bootargs-claims.sh) | Re-checks all 22 load-bearing claims behind the final bootargs string. Read-only, exits non-zero if one stops holding |
| [ref/](ref/MANIFEST.md) | Pinned inputs with SHA-256: the five `.dts`/`.dtsi` sources, the built DTB, its preprocessed form, and the kernel sources cited here |

### Hashes

| Artefact | SHA-256 |
|---|---|
| `s8003-n69.dtb` (in-tree, as built) | `cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` |
| `n69-loader-target.dtb` (23,193 B, after the `ausbphy0` fill) | `1b0ff193c104f0b198ba97bc4e1f5615baac630c106c8c88d5d3f8066e3c9088` |
| `n69-loader-target.dtb` (23,061 B, before — superseded) | `f63bc33c77771d5489b2e4903987210a0e3be43c8390082269c0b184b3ca4cb9` |
| `n69-loader-target.dts` (41,086 B, after the `ausbphy0` fill) | `a7dacd54ee0e34c40d026a3b1fdd69dc8da7d16256014432f1cff8b433dcb072` |
| `n69-loader-target.dts` (37,417 B, before — superseded) | `6ca35ad5e5b8f8d66f4f809841b04dfa1f086f2acacc9ae522ecc8368e956eab` |

---

## How to rebuild

Everything runs inside the a9build VM — **never** over `/mnt/*` (HANDOFF §9.3):

```bash
bash build/build-dtb.sh verify   # MEASURES that the recipe reproduces the tree's DTB exactly
bash build/build-dtb.sh target   # builds n69-loader-target.dtb and decompiles it again to check
```

`verify` is the load-bearing one. It reproduces `cbb79a14…` byte-for-byte using only `cpp` +
`scripts/dtc/dtc`, which means the loader-target artefact is a **meaningful** diff target rather
than a hand-made file. Confirmed twice: once against the tree's existing DTB, and once after the
running `make dtbs` regenerated that DTB and produced the same hash again.

**On a host without the kernel tree** (`task-13` was done on one: no `/build/linux-a9`, no `podman`,
and **`dtc` absent when the task started** — a different workstream installed
`device-tree-compiler` system-wide at 15:36:22, and `/usr/bin/dtc` is byte-identical to the copy
unpacked here), `target` mode runs through the script's documented `K=` override:

```bash
apt-get download device-tree-compiler && dpkg-deb -x device-tree-compiler_*.deb /tmp/dtc-1.7.0
mkdir -p /tmp/dtcroot/scripts/dtc && ln -sf /tmp/dtc-1.7.0/usr/bin/dtc /tmp/dtcroot/scripts/dtc/dtc
cd a9linux/dts
K=/tmp/dtcroot DTS_DIR="$PWD" OUT=/tmp/dtwork bash build/build-dtb.sh target   # OUT must be ABSOLUTE
DTC=/usr/bin/dtc bash build/check-ausbphy-node.sh                             # checks the BLOB
```

That `dtc` (1.7.0) **reproduced the pinned pre-change blob `f63bc33c…` byte-for-byte** from the
pre-change source, which is what makes the rebuild trustworthy rather than a toolchain artefact;
three post-change builds then produced the same `1b0ff193…` each time (a reviewer added six more).
`verify` mode itself cannot run without the tree — an honest gap, recorded in
[AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §6. The full corrected toolchain story, including the
`dtc` arrival and two `build-dtb.sh` robustness nits, is in the same record §3.1.

The recipe deliberately uses a **`dtc` round-trip** for the target rather than the `cpp` path: a
round-trip needs no kernel tree, no `#include`, and no preprocessor, which is the situation
`a9boot`'s host-side tooling is in. The cost is cosmetic `*_property ... not a phandle reference`
warnings — an artefact of phandles being plain numbers instead of `&label` references, not a real
problem, as the parent→target diff proves. The `ausbphy0` fill added **no** new warning
(82 before, 82 after).

---

## What was NOT done, and why

- **No source patch to the kernel tree.** Out of scope, and unnecessary: the console needs no DTS
  change. A `make dtbs` was running throughout, so writing into the tree would also have corrupted
  another workstream's build.
- **No m1n1 source was read** (HANDOFF §0.5, §9.9). No value here depends on it — everything is
  either cited from the kernel tree, measured from the DTB, or explicitly labelled INFERRED with the
  measurement that would settle it (LOADER-FILL §8).
- **`framebuffer0` is left `status = "disabled"`** in the target DTB. That is deliberate and is the
  honest state: no loader has lit the panel yet, and enabling the node without a live scanout would
  claim a framebuffer that does not exist. The six properties it will need are documented and
  commented in place.
- **`cpu-release-addr` is left `<0 0>`** in the target DTB. Verified safe (clean single-CPU boot, no
  write to address 0), and filling it without actually parking the secondaries would be worse than
  leaving it.

## `task-13` additions, and two things it deliberately did not do

- **The phone was not touched.** No `libusb`, no `a9pwn` device command, no `sysfs` write: the four
  measured values came from the rung-2 capture, and this task only edited the DTS and rebuilt the
  blob. Hardware is the Lead's.
- **The `-host` pair is `0` and is not a measurement.** The decision and its reasoning are in
  [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2; it is recorded rather than defaulted.
- **Not resolved here, deliberately:** `a9boot`'s own host pair **mirrors** the device pair
  (`bundle.rs:76-78`), which disagrees with the `0` in this DTS. Both satisfy the probe (`-host` is
  never consumed — `ausb.c:63-95` is `#if 0`). It is `bundle.rs`'s owner's call and is recorded, not
  silently matched — [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2.1.
- **The staged-blob check is still owed.** `--dump-dtb` is how the DTB that actually reaches the
  device gets inspected, and `a9boot plan` currently refuses earlier on the Image-header
  `image_size` bug. Dependency recorded in [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §4.3, not
  worked around.
