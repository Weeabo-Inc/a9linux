# `ausbphy0` fill record — the measured AUSB tunables, and how the blob was checked

**Task:** `task-13` · **Author:** `dt-engineer` · **Date:** 2026-10-03
**Deliverable:** the `ausbphy0` DTB placeholder, filled from the rung-2 measurement, and verified **in
the compiled blob**.
Companions: [LOADER-FILL.md](LOADER-FILL.md) (the contract) · [PLACEHOLDER-INVENTORY.md](PLACEHOLDER-INVENTORY.md)
§2.7 (the item) · [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) Q3 rung C (what it unblocks).

**Labels:** **MEASURED** = read from bytes on disk or from the hardware capture · **INSPECTED** = read
from a cited source · **INFERRED** = reasoned, not confirmed · **UNKNOWN** = nobody has established it.

---

## 1. What was filled, and where the numbers come from

`/soc/bus@20c000000/phy@20c000030`, alias `ausbphy0` (`n69-loader-target.dts:1135`), had **no**
`apple,cfg*` properties. `drivers/phy/apple/ausb.c:149-156` returns `-ENODEV` from probe unless all
four are present, so the PHY never registered and the dwc2 controller (and therefore the only console
channel this device has, `ttyGS0`) deferred forever.

| Property | Value | Source register | Label |
|---|---|---|---|
| `apple,cfg0-device` | `0x373723F3` | `AUSB_CFG0` @ `0x20C000038` | **MEASURED** |
| `apple,cfg1-device` | `0x00020E04` | `AUSB_CFG1` @ `0x20C00003C` | **MEASURED** |
| `apple,cfg0-host` | `0x00000000` | — (decision, not a measurement) | **DECISION** |
| `apple,cfg1-host` | `0x00000000` | — (decision, not a measurement) | **DECISION** |

**Evidence path:** [`RUNG2-EVIDENCE.md`](../../RUNG2-EVIDENCE.md) §2, from
`a9pwn-traces/linux/rung2-fresh-1.json` (+ `.txt` usbmon capture) and `rung2-fresh-2.json`. The CFG
pair was read as little-endian u32 through the pwned payload's MEMC read in **two separate runs** and
was byte-identical both times — reply `f3 23 37 37 04 0e 02 00`. Non-zero **and** stable is
`LOADER-FILL.md` §12 step 2's pass condition, and it is satisfied. Nothing here was rounded, adjusted,
taken from a datasheet, or taken from another SoC's device tree.

**Two honesty notes about that pass condition**, because "read twice" deserves its exact shape
(MEASURED from the two JSON transcripts by an adversarial reviewer, and re-checked here):

- The two CFG reads are the first exchange of two `firstlight` runs started **13:29:19Z** and
  **13:29:35Z** — 16 s apart, in the *same* DFU session. §12's wording suggests two reads ~100 ms
  apart; this is stronger in one way (separate tool invocations, separate DNLOAD) and weaker in
  another (one session, one pwn). A third independent read is still listed as open in
  `RUNG2-EVIDENCE.md` §4.
- `AUSB_CTL`/`AUSB_SIG` were read **once**, in the second run, not twice. §12's "read each address
  twice" was not literally met for those two context registers. That does not affect the CFG values,
  which are the tunables.

**The trace link checked mechanically, not by eye.** The two u32s above, written little-endian, are
exactly the captured reply: `f3 23 37 37` `04 0e 02 00`. The check script below asserts that equality
directly against the blob, so the artefact is tied to the capture rather than to the `.dts` text.

**Why these are the *device* tunables (labelled, because it is a chain):**
- **MEASURED** — the contents of `0x20C000038`/`0x20C00003C` on live hardware.
- **INSPECTED** — that those contents are what the driver calls `cfg0_device`/`cfg1_device`:
  `ausb.c:31-32` puts `AUSB_CFG0`/`AUSB_CFG1` at offsets `0x08`/`0x0c` from the node base
  `0x2_0C000030`, and `ausb.c:102-103` writes `cfg{0,1}_device` into exactly those two registers.
- **INFERRED** — that the ROM left the PHY in the device role, because DFU is enumerated as a USB
  device in the very session that produced the read.

### 1.1 `AUSB_CTL` / `AUSB_SIG` are context, and deliberately NOT properties

Both were MEASURED. Neither became a DT property: the driver reads **no** DT property for either and
writes both itself in `ausb_phy_usb2_power_on()` (`ausb.c:105-111`), so a property here would be
invented ABI with no consumer. They are recorded in the node comment instead, raw:

```
AUSB_CTL @ 0x20C000030 = 0x00000010
    RESET(bit0)=0, PWRDOWN(bit2)=0, SIDDQ(bit3)=0 (ausb.c:20-23), so LOADER-FILL.md
    sec 12 step 2's stated precondition -- "if AUSB_CTL shows RESET or PWRDOWN set,
    the PHY is not up and the read is not yet meaningful" -- is met.
    bit4 is SET and the driver names no bit4. The capture's own note reads that set
    bit as "the PHY is not in the DFU-idle state and this read is context, not a
    tunable". So the precondition is met, but "the PHY is up" is NOT claimed -- an
    earlier revision of this record said it was, following RUNG2-EVIDENCE.md sec 2's
    gloss rather than the capture, and an adversarial reviewer caught the difference.
    Recorded raw, unnamed bit and all.
AUSB_SIG @ 0x20C000034 = 0x0001C103
    VBUSDET_FORCE_EN(bit1)=1, CABLE_CONNECTED(bit8)=1 (ausb.c:25-28). bits 14, 15 and 16
    also read 1; bit14 lies inside AUSB_SIG_HOST (7<<12, ausb.c:28), which as a 3-bit
    field reads 4, not 7. Recorded raw -- context, not a tunable, and nothing is
    written back.
```

**What the measured `AUSB_CTL` does and does not buy us.** It does not prove the PHY is up; the
literal §12 precondition is met and the driver's own `power_on()` sequence (`ausb.c:105-111`) clears
PWRDOWN/SIDDQ regardless, which is why the CFG values are usable as tunables either way. The
untouched question is what bit4 means — **UNKNOWN**, and not something a datasheet should be
consulted for.

## 2. The host-pair decision: **zero**, explicitly

`apple,cfg0-host`/`apple,cfg1-host` are `0`. This is a decision, recorded here rather than left as a
silent default, and the reasoning is fully in the node comment:

1. `ausb.c:153-156` requires them **present**, but **nothing in this kernel consumes them.** Their
   only reader, `ausb_phy_usb2_set_mode()`, is inside `#if 0` (`ausb.c:63-95`). Any u32 passes probe.
2. Host-mode tunables were **not measured**. The PHY is in *device* role in DFU, and
   `RUNG2-EVIDENCE.md` §2 explicitly leaves this pair open.
3. Copying the measured **device** words into `-host` would present an unmeasured guess in exactly
   the syntax of measured data — the failure mode this project keeps paying for. `0` is recognisably
   *unset*: if a future kernel re-enables `set_mode()`, host mode fails visibly and must be
   re-measured, rather than silently programming device tunables into the host role.
4. **What would settle it:** a host-mode session that reads `AUSB_CFG0`/`AUSB_CFG1` with the PHY in
   host role. Not obtainable in a DFU device-role session. **UNKNOWN.**

### 2.1 Found while documenting the load-time link: `a9boot` currently disagrees

`a9boot plan` does **not** read this node; it writes the four properties itself into the DTB it stages
(see §4). Its own host-pair choice is a **mirror of the device pair**:

```
a9boot/crates/a9boot-host/src/bundle.rs:76-78
    pub fn host_pair(&self) -> (u32, u32) {
        (self.cfg0_device, self.cfg1_device)
    }
```

**INSPECTED.** So the two artefacts answer the same question differently:

| Artefact | `cfg0-host` | `cfg1-host` | Consumed? |
|---|---|---|---|
| `n69-loader-target.dtb` (this fill) | `0x00000000` | `0x00000000` | no — `#if 0` |
| DTB `a9boot plan` stages, with `--ausb-cfg0/1` | `0x373723F3` | `0x00020E04` | no — `#if 0` |

Both pass `ausb.c:149-156`, and the **device pair agrees exactly** in both, so this is not a boot
blocker. It is a recorded decision conflict, not a silent one: the DTS rationale is that mirroring is
itself an unmeasured claim about host mode, while `bundle.rs:72-75` documents mirroring as "the
least-invented choice". **Recommendation: align on `0`** — the loader's reason to differ is that it
avoids introducing a number, but it introduces a *claim* instead. Either way it is `a9boot`'s call to
change (`bundle.rs` is not `dt-engineer`'s write scope) and it must not be resolved by editing this
node quietly.

## 3. Hashes — source and blob, before and after

Built with the project's own [`build/build-dtb.sh`](build/build-dtb.sh) `target` mode (never by hand):

| Artefact | Before | After |
|---|---|---|
| `n69-loader-target.dts` | 37,417 B · `6ca35ad5e5b8f8d66f4f809841b04dfa1f086f2acacc9ae522ecc8368e956eab` | 41,086 B · `a7dacd54ee0e34c40d026a3b1fdd69dc8da7d16256014432f1cff8b433dcb072` |
| `n69-loader-target.dtb` | 23,061 B · `f63bc33c77771d5489b2e4903987210a0e3be43c8390082269c0b184b3ca4cb9` | 23,193 B · `1b0ff193c104f0b198ba97bc4e1f5615baac630c106c8c88d5d3f8066e3c9088` |

**The blob hash is independent of the comment.** After the reviewer's `AUSB_CTL` finding the node
comment was corrected (a `.dts` change only), the rebuild produced the **same** `1b0ff193…` blob —
comments do not reach a DTB. The `.dts` after-hash above is the corrected one; an intermediate
revision of the source hashed `e8b48644…` (40,682 B) and is superseded. That is a small live
demonstration of why this record insists on checking the blob.

The `.dts` grew by the explanatory comment as well as the properties; the **blob** grew by exactly
**132 B** = 4 × 16 B property records + 68 B of new string table. Logically the only difference is
four properties appearing on one node — the decompiled pre→post `diff` shows exactly four added
lines, and an adversarial reviewer reconstructed the post blob's structure block from the pre blob's
bytes plus the four records and got byte equality. **At the raw byte level the diff is larger than
64 bytes**, because `dtc` inserted the four new name strings in tree order at string-table offset 473
rather than appending them, shifting 338 `nameoff` fields by +68. That is forced by the insertion and
fully accounted for, but do not read "only four properties changed" as "only 64 bytes differ".

**The parent is untouched by design.** `s8003-n69.dtb` remains 22,880 B /
`cbb79a14…`: `build-dtb.sh:31` makes it the *parent* of the round-trip, it is the kernel's as-built
artefact, and filling the loader's obligations into it would destroy the diff target. MEASURED
(`a9linux/artefacts/kernel/s8003-n69.dtb`).

### 3.1 Build reproducibility, on a host with no kernel tree

`build-dtb.sh`'s `verify` mode (which proves the `cpp`+`dtc` recipe reproduces the *in-tree* DTB)
**could not be run here**: there is no `/build/linux-a9` and no `podman` on this host, and `dtc` was
**not installed when this task started** (`command -v dtc` empty at 15:34 — MEASURED then). What was
done instead, MEASURED:

1. `device-tree-compiler` 1.7.0 was fetched and **unpacked into `/tmp`** (`dpkg-deb -x`); nothing was
   installed system-wide *by this task*.
2. That `dtc` was pointed at `build-dtb.sh` through its documented `K=` override
   (`K=/tmp/dtcroot`, with `scripts/dtc/dtc` → the extracted binary).
3. **`target` mode on the pre-change source reproduced the committed blob byte-for-byte**
   (`f63bc33c…`) — so this `dtc` is output-equivalent to whatever built the pinned artefact, and the
   before/after comparison is meaningful rather than a toolchain artefact.
4. Three builds of the post-change source produced the **same hash** (`1b0ff193…`) each time; an
   adversarial reviewer re-ran six more builds from three different working directories and three
   `OUT` directories and got the same two hashes.
5. dtc warning count is **identical pre and post: 82**, all pre-existing (the `*_property ... not a
   phandle reference` round-trip noise and the known `simple_bus_reg` unit-address warning); the new
   properties add none. MEASURED; the reviewer confirmed the warning *sets* are identical, not just
   the counts.

**Correction, found by the adversarial reviewer:** at **15:36:22**, i.e. after this task's initial
"no dtc" check and before its first rebuild, a *different workstream* installed
`device-tree-compiler` system-wide (`apt-get install -y -qq device-tree-compiler
binutils-aarch64-linux-gnu`, `/var/log/dpkg.log`). So `/usr/bin/dtc` exists now and is **byte-identical**
(sha256 `0ef74efe…`) to the copy unpacked to `/tmp`. The builds above used the `/tmp` copy explicitly
(`K=/tmp/dtcroot`), and the check script prefers `DTC=`/`$K/scripts/dtc/dtc` before falling back to
`command -v dtc`. Because both are the same binary, **no conclusion changes** — but an earlier version
of this record said "dtc is not installed on this host", which stopped being true at 15:36:22 and has
been corrected here. Two build-script nits the reviewer also found: `K=` is mandatory (with the
documented default the script exits 9 at `cd "$K"` before reaching its `FATAL: no dtc` path), and
`OUT` must be **absolute** (`mkdir -p "$OUT"` runs before `cd "$K"`).

## 4. The load-time link: the DTS is not what reaches the device

**This is the gap that would leave correct documentation next to a dead PHY.** The blob the device
actually receives is produced by `a9boot plan`, which edits the **parent** DTB and writes these
properties from its **command line** — so the fill above documents and pins the intended node, while
the value at load time comes from the flags. INSPECTED
(`a9boot/crates/a9boot-host/src/main.rs:40-42, 706-714, 748-750`;
`bundle.rs:382-393`):

```
a9boot-host plan --image a9linux/artefacts/kernel/Image \
  --dtb a9linux/artefacts/kernel/s8003-n69.dtb \
  --initramfs debian-ios/dist/arlo-initramfs-debian.cpio \
  --ausb-cfg0 0x373723F3 --ausb-cfg1 0x00020E04 --dump-dtb /tmp/on-device.dtb
```

`--ausb-cfg0` and `--ausb-cfg1` **must be given together** (`main.rs:706-714`) and are the flags that
decide whether the gadget console can exist at all. All three file paths in that invocation were
checked **present** on this host (MEASURED: `Image` 19,755,520 B, `s8003-n69.dtb` 22,880 B,
`arlo-initramfs-debian.cpio` 20,251,648 B), so the Image-header check in §4.3 is the only thing
standing between this command and a `--dump-dtb` blob. Three load-bearing consequences:

1. **`--dump-dtb` is the only way to see the blob that will be staged.** Decompiling
   `n69-loader-target.dtb` cannot prove what the loader sends.
2. **The half-configured case is refused, not shipped.** `bundle.rs:461-480` errors if tunables are
   supplied without `console=ttyGS0` in bootargs, **and** if `console=ttyGS0` is promised without
   tunables. Because the plan's bootargs carry `console=ttyGS0`, "correct DTS + no flags" is a hard
   error in `plan`, not a silent dead PHY. INSPECTED.
3. **The `--dump-dtb` verification is BLOCKED and not by this workstream.** `plan` currently refuses
   before the edit, on the Image header check that demands `image_size == file length`.
   **Independently re-measured here, from the artefact itself** — not taken on trust:
   `a9linux/artefacts/kernel/Image` is **19,755,520 B = `0x12d7200`** long, while its arm64 header
   (magic `ARMd` at offset 56) carries `image_size = 0x1370000` = 20,381,696. The two are legitimately
   different: `_end - _text` is page-granular and includes BSS
   (`../artefacts/kernel/BUILD-LOG.md:845-846`). Handed to `loader-engineer`. **Dependency recorded
   here deliberately rather than worked around** — I did not run the phone or the loader to route
   around it.
   **Consequently: "the four properties land in the `--dump-dtb` blob" is NOT VERIFIED.** What *is*
   verified is the write path by inspection (`bundle.rs:388-392` sets all four as single cells;
   `bundle.rs:1345-1370` unit-tests exactly that) and the values by the measurement above.

## 5. Verified in the BLOB, not just the source

`dtc -I dtb -O dts n69-loader-target.dtb`, `ausbphy0` node as it exists **in the compiled blob**
(comment stripped by the round-trip; values are what matter):

```
phy@20c000030 {
        compatible = "apple,s8000-ausb-phy\0apple,ausb-phy";
        reg = <0x02 0xc000030 0x00 0x20>;
        power-domains = <0x0f>;
        #phy-cells = <0x01>;
        apple,cfg0-device = <0x373723f3>;
        apple,cfg1-device = <0x20e04>;
        apple,cfg0-host = <0x00>;
        apple,cfg1-host = <0x00>;
        phandle = <0x10>;
};
```

`apple,cfg1-device = <0x20e04>` is `0x00020E04`; the round-trip drops leading zeros.

On both paths, and with an independent tool:

```
# independent raw read, no dtc involved
fdtget -t x n69-loader-target.dtb /soc/bus@20c000000/phy@20c000030 apple,cfg0-device  -> 0x373723f3
                                                                        apple,cfg1-device  -> 0x20e04
                                                                        apple,cfg0-host    -> 0x0
                                                                        apple,cfg1-host    -> 0x0
```

### 5.1 The check, and proof that it can fail

Added: [`build/check-ausbphy-node.sh`](build/check-ausbphy-node.sh). It checks the **blob**, twice over:
(1) `dtc` decompile, then walk the decompiled tree to the **full node path** and match property names
exactly, comparing each value numerically; (2) a raw FDT structure walk in `python3` — no dtc, no
libfdt — that reads the property bytes straight out of the blob and asserts the `cfg0|cfg1`
little-endian byte sequence equals the **MEASURED capture** `f3233737040e0200`. Path 2 is what ties the
artefact to the evidence rather than to the `.dts` text.

A check earns trust only by having been shown to fail. The full battery, MEASURED:

| Input | What it is | Result |
|---|---|---|
| `n69-loader-target.dtb` | the artefact | **PASS**, exit 0 |
| pre-change blob | `f63bc33c…` (committed before this task) | **FAIL**, exit 1 — all four absent, both paths |
| value mutant | `cfg0-device` `0x373723f3`→`0x373723f4` | **FAIL** — value, both paths, and the capture link |
| value mutant | `cfg1-device` → `0x00020e05` | **FAIL**, exit 1 |
| **rename spoof** | properties renamed `Xapple,cfg0-*` in the blob | **FAIL**, exit 1 |
| **duplicate-node spoof** | real node deleted, a `phy@20c000030` with correct values planted under `/chosen` | **FAIL**, exit 1 |
| unrelated byte flip | one byte flipped in another node | **PASS** — by design; this is not a blob-integrity check |
| truncated / empty / non-FDT | 5,000 B, 0 B, 17 B of text | **FAIL**, exit 1, cleanly graded (no traceback) |

**The two spoofs are the reason path 1 was rewritten.** An earlier revision of the script looked the
node up by **name** and matched property names **unanchored**, so it printed four `ok`s on a blob whose
real node had none of the properties — an adversarial reviewer found both holes and proved them
(mutants m16/m17). The old logic was reproduced here to confirm the finding:

```
rename-spoof.dtb        OLD name-based path 1 -> ok      (new path 1: FAIL)
dupe-node-spoof.dtb     OLD name-based path 1 -> ok      (new path 1: FAIL)
```

The script now anchors on the full path and whole property names, and its header records this history
with "do not simplify it back". Its scope is stated there too: one node's four properties, **not** a
blob-integrity check, and neither path should be trusted alone.

## 6. What could NOT be verified without hardware

Stated plainly, because this artefact's whole purpose is a device that has not been booted yet:

1. **That the kernel actually probes the PHY with these values.** The driver source says the four
   properties are sufficient (`ausb.c:149-156`) and nothing more is required to reach
   `devm_phy_create`, but no Linux has run on this device. **UNVERIFIED.**
2. **That the PHY is in the device role when the ROM programmed it** — the INFERRED link in §1. The
   measurement is real; the role attribution is inference from DFU being a device.
3. **That host-mode tunables are anything** — never measured, hence `0` and the §2 decision.
4. **That the values persist across a pwn/reset cycle.** They were measured twice *within* one DFU
   session's lifetime rules (`RUNG2-EVIDENCE.md` §1.1) — same session, 16 s apart. A new session
   should re-read them; the driver overwrites both registers on `power_on()` anyway, which is the
   point of storing them.
5. **Whether §12 step 2's "read each address twice" was literally met.** The CFG pair was read twice
   (two runs, one session); `AUSB_CTL`/`AUSB_SIG` were read **once**. The context registers are not
   the tunables, so this does not weaken the values — it is recorded because the procedure says twice.
6. **What `AUSB_CTL` bit 4 means.** Set in the measurement, unnamed by the driver
   (`ausb.c:20-23`), and the capture's own note declines to interpret it. **UNKNOWN** — not to be
   guessed from a datasheet or from another SoC.
7. **That `ttyGS0` appears** — needs boot + userspace configfs gadget (no `CONFIG_USB_G_SERIAL`), a
   separate workstream.
8. **That `--dump-dtb` carries the properties** — blocked on the Image-header bug, §4.3.
9. **`build-dtb.sh verify` (the in-tree `cpp`+`dtc` reproduction)** — could not run at the time: no
   kernel tree and no podman here, and `dtc` was absent until 15:36:22 (§3.1). The `target` mode *was*
   validated against the pinned pre-change blob instead, which is the check that matters for this
   change.

## 7. Adversarial review — what it changed

A reviewer was asked to **falsify** this work, not to confirm it: that the four values match the
evidence, that they are in the compiled blob, that the build is byte-reproducible, and that the node
is otherwise unchanged. Verdict: **C1–C6 all PASS** (values traceable to the capture *including* the
DNLOAD bytes that encode the read address; blob confirmed by four independent readers; two hashes and
two sizes reproduced across six extra builds from three working directories; reconstruction of the
post blob from the pre blob's bytes exact; the `#if 0` host-pair claim verified line by line).

It also found five things that were **wrong or overstated in the first revision**, all corrected here
and in the code:

| Finding | Correction |
|---|---|
| `AUSB_CTL = 0x10` was glossed as "the PHY is up", but the capture's own note reads the set bit as "not in the DFU-idle state … context, not a tunable" | node comment, §1.1 and the other docs now claim only the literal §12 precondition; bit 4 recorded as UNKNOWN |
| "`dtc` is not installed on this host" | true at 15:34, false from 15:36:22 (§3.1, corrected — same binary, no conclusion changes) |
| "each register read twice" (from `RUNG2-EVIDENCE.md` line 63) is not true for `AUSB_CTL`/`AUSB_SIG`, read once | recorded as a limitation, §6 item 5 |
| the check script's path 1 could be spoofed two ways | path 1 rewritten to the full node path + whole-name matching, with the spoof mutants added to the battery, §5.1 |
| "only 64 bytes differ" would be a naive reading | §3 states the 338 shifted `nameoff` fields explicitly |

Nothing in the review contradicted the four values, their presence in the compiled blob, or the two
hashes. The reviewer's residual doubts are carried forward here rather than dropped: the
`of_property_read_u32` "any u32 is accepted" step is INFERRED (no kernel tree on this host), and the
evidence link in the check script is a hardcoded constant that was verified against the capture by
hand.

## 8. Reproduce it

```bash
cd a9linux/dts
# dtc 1.7.0 is now installed system-wide (/usr/bin/dtc); the extracted copy is identical.
# build-dtb.sh still needs K= because its default kernel tree is absent. OUT must be ABSOLUTE.
K=/tmp/dtcroot DTS_DIR="$PWD" OUT=/tmp/dtwork bash build/build-dtb.sh target
DTC=/usr/bin/dtc bash build/check-ausbphy-node.sh
```

`build-dtb.sh target` also writes its read-back `n69-loader-target.check.dts` into `OUT`; with
`OUT="$PWD"` that lands in this directory (it was removed after the `task-13` build, since it is
regenerable and was never part of the committed set). Use `OUT=/tmp/...` for a clean tree — and copy
the resulting `.dtb` into place, reporting that it is byte-identical to `1b0ff193…`.
