# a9linux/qemu — the arm64 boot-contract harness

Boots an arm64 kernel with a device tree and an initramfs under QEMU `virt`,
captures the console, and — where it cannot capture anything — observes the guest
from outside. Its job is to make boot-contract mistakes cheap: **every mistake caught
on a laptop is a device round trip not spent.**

> **Read [`CANNOT-PROVE.md`](CANNOT-PROVE.md) before quoting any result here.** A green
> run is evidence about QEMU `virt`, never about the iPhone. A9 has a SecureROM
> checkm8 hand-off, a 16K-page granule, an Apple AIC interrupt controller, a real DRAM
> map and a real panel; QEMU `virt` has none of those.

---

## 1. Environment (MEASURED)

| Thing | Value |
|---|---|
| QEMU | `QEMU emulator version 8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18)`, package `qemu-system-arm` |
| device tree compiler | `dtc` 1.7.0 (`fdtget`/`fdtdump` used for structured reads) |
| assembler for the hand-off stub | GNU binutils 2.42 (`binutils-aarch64-linux-gnu`) |
| Where QEMU runs | originally **WSL2 `Ubuntu-24.04`** as root; since 2026-10-03 also **bare-metal Ubuntu 24.04**, uid 1000, no KVM (§10) |
| Staging / working directory | `$A9QEMU_STAGE/{inputs,work,logs}`; default `/opt/a9qemu` (WSL, inside the VM's ext4), falling back to `$XDG_STATE_HOME/a9qemu` when `/opt` is not writable (§10.1). All paths are resolved by `qemu-env.sh` |
| `E:` visibility | `/mnt/e` (drvfs). Only small text/log files are written there. Builds and QEMU never run over `/mnt/*` (HANDOFF §9.3). |
| KVM | **absent** (`no /dev/kvm`): everything runs under TCG. Fine for boot tests, useless for timing. |

Install once:

```powershell
wsl -d Ubuntu-24.04 -u root -- bash -lc "apt-get update -qq && apt-get install -y qemu-system-arm device-tree-compiler cpio zstd file python3 binutils-aarch64-linux-gnu"
```

## 2. Inputs and where they came from (MEASURED, SHA-256)

| Input | Source | SHA-256 | Granule |
|---|---|---|---|
| `arlo-Image` (19,755,520 B) — **the shipping kernel** | kernel-engineer, task-6 → `a9linux/artefacts/kernel/Image` | `39a270676141f42575cbadffbac085cc120aa1e0f6e61af0b6db8ad5b0c7e228` | **16K** (`file(1)`: "16K pages"; `CONFIG_ARM64_16K_PAGES=y`) |
| `arlo-Image.gz` (8,427,837 B) | same | `3eef7ffa5197846a033bf66f5b0dad38d70b7f45e10c95be6b74ce1b06da4051` | 16K |
| `arlo-Image-qemu-pl011` (19,757,568 B) — **TEST INSTRUMENT, never for the device** | kernel-engineer → `a9linux/artefacts/kernel/Image-16k-qemu-pl011` | `2697e77d901d44844cb8871400ee59119148be08182ccf57bbb6df9b766fde88` | 16K (kept deliberately) |
| `n69-loader-target.dtb` | dt-engineer, task-7 → `a9linux/dts/n69-loader-target.dtb` | pin `f63bc33c…` is **STALE**: dt-engineer's file was 23,061 B at the WSL run and 23,193 B / `1b0ff193c104f0b198ba97bc4e1f5615baac630c106c8c88d5d3f8066e3c9088` on 2026-10-03 15:37 (§10.2). Their scope; not touched here | — |
| `arlo-initramfs-min.cpio.gz` (997,191 B) | rootfs-engineer, task-9 → `debian-ios/dist/` | `c8b2dbb4a10c6510fab492c9b2eebc452fa4b2c5270f30b69710cad7c4ec2608` | — |
| `arlo-initramfs-dash.cpio.gz` (4,015,918 B) | same | `9eb1964db74b50d66bc0ab296238dbc76b743752a2fbef51e955d89c6365239f` | — |
| `arlo-initramfs-debian.cpio.gz` (7,478,005 B) | same | `0dae863c10bddd615a5a026ecb8bbc9768296a216b895e3f47e226cd6eb0c9dd` | — |
| `source-n69.dtb` (22,880 B) | **stand-in**: the upstream reference copy dt-engineer inherits, `a9linux/dts/ref/dts/s8003-n69.dtb` | `cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` | — |
| `stock-Image` (58,075,528 B) | **stand-in**: Ubuntu `linux-image-6.8.0-71-generic` arm64 from ports.ubuntu.com, decompressed from `vmlinuz` | `9e114978788d0639aecf0e17b04aff687613b58177b7d86b669e3d99fc6e0b3e` | **4K** |
| `harness-selfinit.cpio.gz` | mine, built by `mk-selfinit.sh`; busybox taken from `a9linux/artefacts/initramfs.gz` | **WSL build `552422d5…` is NOT re-derivable** (it embedded build time). Reproducible build since 2026-10-03: `350ca58b6a1c39e45be8cf00386bfcd43b911fefa68fecd02d2f7398416b4632` (940,621 B) — see §10.2 | — |
| `handoff-stub.bin` (357 B) | mine, built by `mk-handoff-stub.sh` from `handoff-stub.S` | `45c8eae0eb0f98a39fbdd7afbca6bd544b117bb4c0b22e99798b9cb7880a327d` | — |
| `System.map` (4,592,199 B) — shipping | kernel-engineer → `a9linux/artefacts/kernel/System.map` | `821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c` | — |
| `System.map-qemu-pl011` (4,596,104 B) | kernel-engineer → `a9linux/artefacts/kernel/System.map-qemu-pl011` | `07408377308361cb8d91d35e24857325c98c698c5c0703dd476b3bb7ee46c6ab` | — |

Stand-ins are labelled stand-ins everywhere. `fetch-inputs.sh` re-downloads the stock
kernel and records its own provenance in `inputs/PROVENANCE.txt`.

**Never take a size or a hash from a note — including this one.** These artefacts were
rebuilt twice during the day (the debian initramfs passed through 7,503,864 → 7,504,935 →
7,478,005 bytes). Every run records `initrd_size`/`initrd_sha256` of the file it actually
booted in `logs/<name>.meta.txt`, and the harness always computes `linux,initrd-end` from
`stat -c%s` of the file it is about to load rather than from a constant.

**The `System.map` files are cited, so their pairing with the Images is checked, not assumed.**
`resolve-pc.sh` turns a PC into a symbol with one of them, and a map from a sibling build would
produce a confident wrong symbol — which would quietly corrupt the granule finding in §4.
kernel-engineer's rule (`image_size == _end - _text`, `arch/arm64/kernel/image.h`) is
**necessary but not sufficient**: both kernels report `image_size = _end - _text = 0x1370000`,
because `image_size` is page-granular and the PL011 driver fits inside the existing rounded
footprint. `verify-map-pairing.sh` (mine, independent of their PowerShell checker) tests the
rule *and* a discriminator that cannot collide (`pl011` symbols in the map vs `pl011` literals
in the Image) across **all four pairings**: both correct pairings pass, and both mis-pairings
pass the footprint rule and are rejected only by the discriminator. It confirms that the map
used for the `__no_granule_support` resolution is the device map for the device Image.

Their guard's teeth were then tested rather than assumed (`test-pairing-guard.sh`): a scratch
directory whose two pairs have their contents **swapped** is fed to their script, unmodified,
through its `-Dir` parameter. It exits **4** with `*** MIS-PAIR ACCEPTED -- GUARD BROKEN ***`,
on a case where the footprint rule passes on both mis-pairs — so "it cannot rot silently" holds.

**That negative control only covered swaps, and the limit I recorded here was not a caveat — it
was a hole.** kernel-engineer then constructed the case I had said I could not: append **one
comment line** to a map, changing nothing the rules read, and all four combinations stay green.
Structure is blind to *staleness*. So the check has **two independent verdicts, and both must
pass**:

* **(A) pairing** — footprint rule plus discriminator across all four combinations → catches a **swap**.
* **(B) pins** — every artefact's SHA-256 equals the value recorded in §2 → catches a **stale or
  regenerated** artefact, which (A) cannot see.

I reproduced their stale-map case on a scratch copy and confirmed **both** guards reject it
(`test-pin-teeth.sh`, `test-pin-teeth-run.sh`; their script via `-Dir`, mine via its pins).
Their guard now carries a **third** verdict — **(C) doc agreement**, every script pin must also
appear in `BUILD-LOG.md` — and I negative-controlled that one too
(`test-doc-agreement-guard.sh`: genuine artefacts, one pin corrupted in a *copy* of the doc →
(A) and (B) pass, (C) fails, exit 1). Three verdicts, each separately shown to fail.

> **Do not misread the two hash values these controls produce.** My stale-map test appends one
> fixed comment line and gets `821a3f3a…` → **`c83d4df2…`** (4,592,273 B). kernel-engineer's
> appends different text and gets `821a3f3a…` → **`22a50fa4…`** (4,592,261 B). Different
> appended bytes, different hashes, **one test intent**. The load-bearing fact is identical in
> both runs: the structural rules stayed green and only the pin caught it. `test-pin-teeth.sh`
> now prints the hash its own control is expected to produce, so "the control ran" is
> distinguishable from "the control silently did nothing".

**Limit, stated precisely and shared by both implementations:** (A) is sufficient for the artefact
set we cite, not in general; and (B) means a deliberate regeneration fails until someone re-pins
by hand — which is the correct workflow, because re-pinning *is* the moment a human re-decides
that the new pair is the pair to cite. `selfcheck.sh` re-runs the whole thing as a standing
assertion, so a changed artefact cannot be cited by accident.

**`arlo-Image-qemu-pl011` is a control, not our kernel.** Its config differs from the
shipping config in exactly two symbols — one line removed (`# CONFIG_SERIAL_AMBA_PL011 is
not set`), two added (`CONFIG_SERIAL_AMBA_PL011=y`, `CONFIG_SERIAL_AMBA_PL011_CONSOLE=y`);
verified here by diffing the two `config*.used` files (the whole delta) and by two
independent instruments on the binaries: `System.map` lines matching `pl011` are **0 vs 62**,
and literal `pl011` strings inside the `Image` are **0 vs 20**, while the `s5l`/Samsung
console is identical in both (`System.map` 23 vs 23). The gap between 62 and 20 is kallsyms
tokenisation, not a missing driver: `pl011_early_write`, `pl011_probe` and `pl011_putc` are
each in the variant's map and absent as literal strings, and the literals that do survive are
visibly tokenised fragments (`dpl011_zt`, `_pl011_670`). Reproduce all of it with
`verify-systemmap-ab.sh`. Either instrument is decisive (0 vs non-zero); the literal count is
the one a reviewer needs no build tree for. It keeps the 16K granule on purpose. It exists so
QEMU can see our kernel boot at all, and it must never reach the phone.

`harness-selfinit.cpio.gz` is **not** our rootfs. It is a harness self-test: it mounts
proc/sys, prints the kernel's own view of the device tree (`/proc/device-tree/*`), the
memory map (`/proc/iomem`), the console nodes, and then powers off. It exists so that
"did the kernel get OUR DT?" is answered by the kernel, not by my hopes.

## 3. The exact commands

Each script is a plain file in this directory and runs on **either** host — the
WSL incantations below still work, and `bash a9linux/qemu/<script>.sh` works from
any cwd on bare-metal Linux. Paths come from `qemu-env.sh` (§10.1); nothing is
hardcoded twice any more.

```powershell
# 0. stage inputs into the VM's ext4 (also prints what is missing)
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/fetch-inputs.sh
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/stage-arlo-inputs.sh

# 1. static gate — no QEMU, no hardware: audits a DTB against the loader contract
wsl -d Ubuntu-24.04 -u root -- bash -lc "python3 /mnt/e/Reverseing/Arlo/a9linux/qemu/check-dtb.py /opt/a9qemu/inputs/n69-loader-target.dtb"

# 2. build the harness pieces
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/mk-selfinit.sh
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/mk-handoff-stub.sh
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/make-variants.sh

# 3. the boot ladder: unfilled DT -> filled DT with the A9 AIC -> QEMU-substituted DT
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/run-ladder.sh

# 4. the hand-off: QEMU places every blob the way a loader would; our stub does the jump
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/run-stub.sh

# 5. observe the spin-table mailbox from outside the guest
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/observe-mailbox.sh

# 6. our own kernel (16K): granule sweep, then a boot with monitor observation
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/granule-sweep.sh
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/run-arlo-kernel.sh
wsl -d Ubuntu-24.04 -u root -- bash /mnt/e/Reverseing/Arlo/a9linux/qemu/locate-arlo-hang.sh
```

The generic runner is `run-qemu.sh`; it prints an `exact_command:` line into
`logs/<name>.meta.txt` for every run, so any result can be re-executed verbatim:

```
timeout -k 5 300 qemu-system-aarch64 -M virt -cpu cortex-a57 -smp 2 -m 1024 \
  -display none -serial stdio -no-reboot -monitor none \
  -kernel /opt/a9qemu/inputs/stock-Image \
  --dtb /opt/a9qemu/inputs/n69-qemu-virt.dtb \
  -initrd /opt/a9qemu/inputs/harness-selfinit.cpio.gz \
  -append "console=ttyAMA0 earlycon=pl011,0x9000000 rdinit=/init panic=-1 loglevel=7"
```

## 4. The page-granule question — answered, and it is a trap

**Our kernel is a 16K-page kernel; QEMU `virt` can run it, but only under `-cpu max`.**

MEASURED (`granule-sweep.sh`, `logs/10-granule-*.log`): under `-cpu cortex-a57`,
`-cpu cortex-a53` **and** `-cpu cortex-a72`, our Image halts immediately in
**`__no_granule_support`** with status word **0x202** (`CPU_STUCK_IN_KERNEL`) written to
`early_cpu_boot_status` — resolved from kernel-engineer's `System.map`, not guessed
(`resolve-pc.sh 0x41055590 0x40080000` → `__no_granule_support+0x24`, using the map whose
sha256 `821a3f3a…` it prints). That routine is reached when
`ID_AA64MMFR0_EL1.TGran16` reports the granule as unimplemented. Under `-cpu max` the same
image proceeds with the MMU on.

So: the limitation is the **emulated CPU model's ID register**, not QEMU's TCG page-table
walk. Do not conclude "our 16K kernel is broken" from a run that did not use `-cpu max` —
and do not conclude anything about A9 from `-cpu max` either (`CANNOT-PROVE.md` §9).

The baseline/stand-in runs (01–05) use the 4K Ubuntu stand-in kernel with `-cpu cortex-a57`.
They demonstrate the harness and the DT shape. They say nothing about our granule.

## 5. Results (all MEASURED; logs in `logs/`)

| Run | Kernel | DT | Outcome |
|---|---|---|---|
| `01-baseline-virt-stockkernel` | stock 4K | QEMU's own | **reached userland**, 13 s wall clock, clean power-off |
| `02-dtb-unfilled-memory` | stock 4K | our DT, memory still `<0x8 0 0 0>` | kernel panic: `Attempted to kill the idle task!` after `aic_of_ic_init` external abort |
| `03-dtb-memory-filled-aic` | stock 4K | our DT, memory filled, A9 AIC left in | **same panic**: `pc : aic_of_ic_init+0x610/0x800`, `of_irq_init` → `irqchip_init` → `init_IRQ` |
| `04-dtb-qemu-virt` | stock 4K | our DT, QEMU devices substituted | **reached userland** (18,670 bytes of console); `/proc/device-tree/model = Apple iPhone SE (TSMC)`; `simpledrm` bound to our framebuffer node; `CPU1: failed to come online` |
| `05-loader-stub-handoff` | stock 4K | our DT + QEMU substitutions | **reached userland through our own hand-off stub**, with bootargs and initramfs delivered *only* through the DT |
| `06-mailbox-observe` | stock 4K | as 05 | kernel wrote `0x426d4348` into `cpu-release-addr` (read via QEMU's monitor) |
| `07-arlo-kernel-virt-dt` | our **shipping** 16K Image | QEMU's own | 0 console bytes — our kernel has no PL011 driver. PC observed in kernel high VA (MMU on) |
| `08-arlo-kernel-our-dtb` | our **shipping** 16K Image | dt-engineer's DTB, adapted | stub banner only (119 B); MMU on, no exceptions, framebuffer marker **absent** → userland not proven reached |
| `09-arlo-kernel-exc` | our shipping 16K Image | adapted | **no exceptions at all** in `-d int,guest_errors` |
| `10-granule-*` | our shipping 16K Image | adapted | a57/a53/a72 → `__no_granule_support` (0x202); `max` → MMU on, kernel running |
| `12-nokaslr` | our shipping 16K Image | adapted, `nokaslr` | PC pinned at image offset `0x9e8cc` (scheduler region); `early_cpu_boot_status = 0` |
| `13-variant-virt-dt` | **QEMU-console variant** | QEMU's own | **reached a shell** (`arlo:/#`), 14,710 B console, min initramfs |
| `14-variant-our-dtb-stub` | **QEMU-console variant** | **our DT (adapted) via our stub** | **reached a shell** (15,116 B): `Machine model: Apple iPhone SE (TSMC)`, `9000000.pl011: ttyAMA0 ... is a PL011 rev1`, `printk: console [ttyAMA0] enabled`, cmdline taken from `/chosen/bootargs` only |
| `16-variant-dash` | QEMU-console variant | QEMU's own | **reached a shell** (`arlo:\w#`), 4,015,918 B initramfs |
| `15-variant-debian-initrd` | QEMU-console variant | QEMU's own | **reached a shell** (`arlo:\w#`), 7,478,005 B initramfs |

The console files for the runs re-executed on bare-metal Linux carry a `-linux`
suffix (`logs/07-arlo-kernel-virt-dt-linux.log`, …) so the two hosts cannot
collide; §10 has that re-validation, including one collision that happened before
the tag existed.

Runs 13–16 need kernel-engineer's two-symbol test variant (§2) — the shipping kernel
produces no console at all here. Run 14 is the strongest off-device result the project has:
**our kernel, our device tree, our hand-off sequence, our initramfs, userland.**

## 6. What this harness caught (the point of the exercise)

Each of these was a silent failure — no error message, no clue on a phone:

1. **`initrd-start` is not a device-tree property.** The kernel reads
   `linux,initrd-start` / `linux,initrd-end` only. Writing the bare names produced a
   kernel that booted normally and then panicked with
   `VFS: Cannot open root device "" or unknown-block(0,0): error -6`. Fix in
   `adapt-dtb.py`; the gate now fails a DTB that has bare names.
2. **A loader must not place the DTB or the initramfs inside the kernel image's own
   footprint.** `__primary_switched` clears `.bss` *before* `setup_arch` reads the DTB.
   Our first stub map put the DTB at 0x43900000 and the initramfs at 0x43a00000, inside a
   59 MB image: the kernel zeroed both and printed **absolutely nothing**. Fix: everything
   the loader owns sits above the kernel's end (0x44000000+ here).
3. **QEMU rewrites a `-dtb` tree** (memory node replaced, `/psci` injected), so a green
   `-dtb` run does **not** validate the loader's memory fill. Caught with
   `-M virt,dumpdtb=`. The gate checks `/memory` statically instead.
4. **`cpu-release-addr = 0`** in dt-engineer's `n69-loader-target.dtb` (both CPUs) — the
   gate fails it. Without a loader-written value the kernel writes the secondary entry
   address to PA 0 and CPU1 never arrives.
5. **`linux,initrd-end` is a fixed guess (2,670,592 B) in that DTB**, while rootfs-engineer's
   real initramfs is 997,191 B (min), 4,015,918 B (dash) or 7,478,005 B (debian). Loading a
   larger image under that end value hands the kernel a truncated initramfs. The declared
   window is 717 bytes larger than `a9linux/artefacts/initramfs.gz` (2,669,875 B) — it was
   sized to an image that is not ours. Their own guard, `debian-ios/scripts/check-loader-window.sh`,
   reproduces the mismatch independently.
6. **`-cpu max` is mandatory for our 16K kernel** (see §4).
7. **Our *shipping* kernel cannot print on QEMU at all** (`CONFIG_SERIAL_AMBA_PL011` unset),
   so its QEMU behaviour is only observable at the register level; the two-symbol test
   variant is what made runs 13–16 possible. `console-audit.sh` tells you which console a
   given config can drive.
8. **All 14 A9 peripheral nodes must be disabled in an adapted DT** — any MMIO read of an
   unmapped QEMU address is a guest data abort, which oopses the probe (run 03 shows the
   signature).
9. **A too-specific marker produced a confident wrong answer — mine.** The first version of
   `run-console-variant.sh` looked for the prompt `arlo:/#` and therefore reported the dash
   and debian runs as "no userland marker" when both had in fact reached a shell with
   `arlo:\w#`. Fixed to a loose match, and recorded here because it is exactly the failure
   mode this project keeps paying for: the tool said no, and I nearly believed it.

## 7. Files

| File | What it is |
|---|---|
| `qemu-env.sh` | **the one place paths are resolved.** Sourced by every script: `Q` (this directory), `W` (repo root), `STAGE`, `LOG_SCOPE`, `LOG_TAG`. Overrides: `A9_ARLO_ROOT`, `A9QEMU_STAGE`, `A9QEMU_LOG_SCOPE`, `A9QEMU_LOG_TAG`. WSL defaults preserved; no root required (§10.1) |
| `check-dtb.py` | **static gate.** `/memory` fill, `stdout-path` resolution through `/aliases`, `enable-method`/`cpu-release-addr`, timer, `linux,initrd-*`, `framebuffer0` geometry vs `reg` size, leftover placeholders. Exits non-zero on FAIL. No QEMU. |
| `adapt-dtb.py` | builds a QEMU-runnable variant of our DTB and writes every transform to `*.transform.txt` |
| `make-variants.sh` | builds + audits the three variants (`console`, `fill`, `virt`) |
| `run-qemu.sh` | the generic runner: boots, captures, writes `logs/<name>.meta.txt` with the exact command and input hashes |
| `run-ladder.sh` | runs 02/03/04 in sequence and classifies each outcome |
| `handoff-stub.S`, `mk-handoff-stub.sh` | the arm64 hand-off stub: `x0 = DTB`, `x1..x3 = 0`, MMU off, jump to the Image, plus a spin-table parked CPU (`--defsym` load map) |
| `run-stub.sh` | the hand-off run: QEMU places every blob, the stub does the jump, the DTB carries bootargs and the initramfs |
| `observe-mailbox.sh`, `mon-read.py`, `mon-cmd.py` | read guest RAM / registers through QEMU's monitor (needed because `CONFIG_STRICT_DEVMEM` blocks `/dev/mem` inside the guest) |
| `mk-selfinit.sh` | builds the harness self-test initramfs (including the framebuffer marker used as a console-free userland proof) |
| `console-audit.sh` | which console can a given kernel config actually drive? |
| `stage-arlo-inputs.sh`, `fetch-inputs.sh` | bring inputs into `/opt/a9qemu/inputs`, with hashes |
| `granule-sweep.sh` | the `-cpu` sweep for 16K support |
| `stage-qemu-console-kernel.sh` | verify + stage kernel-engineer's QEMU-console test variant (config delta, `pl011` literal A/B, granule flags) |
| `run-console-variant.sh` | runs 13–16: the variant with our DT, our stub and each initramfs variant (`SUMMARY_ONLY=1` re-prints verdicts from existing logs) |
| `refresh-and-check-initramfs.sh`, `compare-initramfs-runs.sh` | re-point at rootfs-engineer's current artefacts, verify their hashes, and compare initramfs variants at the point they diverge |
| `run-arlo-kernel.sh`, `locate-arlo-hang.sh`, `diag-arlo-kernel.sh`, `probe-entry.sh`, `resolve-pc.sh` | our-kernel runs and the tooling that names where it stops. `resolve-pc.sh` prefers the `System.map` copies on `E:` (`a9linux/artefacts/kernel/`) and prints the map's hash, so a symbol claim is citable without the build tree |
| `verify-systemmap-ab.sh` | reproduces the shipping-vs-variant control with both instruments and tests the kallsyms explanation |
| `verify-map-pairing.sh` | checks each `System.map` belongs to the `Image` cited with it — footprint rule **plus** a discriminator, over all four pairings, so it also demonstrates that the footprint rule alone cannot separate them |
| `test-pairing-guard.sh` | negative control for the pairing guards: builds a scratch directory of deliberately mis-paired artefacts (`build`) and removes it (`clean`), to be fed to either guard and shown to fail |
| `test-pin-teeth.sh`, `test-pin-teeth-run.sh` | negative control for the **staleness** case: appends one comment line to a copy of a map (structure stays green) and shows that both guards' hash pins reject it |
| `test-doc-agreement-guard.sh` | negative control for **doc-vs-enforcement drift**: genuine artefacts, one pin corrupted in a *copy* of the doc, so the other verdicts pass and only doc agreement fails |
| `selfcheck.sh` | `bash -n` + `py_compile` over every script here, plus an inventory. Run it after any edit; a typo should not be discovered by a half-finished QEMU run |
| `dt-explore.sh` | quick structured dump of a DTB with `fdtget` |
| `final-consistency-run.sh` | **run this after any edit to these scripts**: rebuilds the harness pieces, re-runs the ladder, the hand-off, the granule sweep and the static gate, so every number quoted here is regenerated from the shipped code (HANDOFF §9.7) |
| `dts/` | decompiled reference DTB, the adapted variants, their transform records, and the DTB QEMU actually handed the guest (`qemu-dumped-virt-patched.dtb`) |
| `logs/` | console captures + `.meta.txt` per run |

## 8. Reproducing a run from scratch

1. `fetch-inputs.sh` (needs network for the stand-in kernel only).
2. `stage-arlo-inputs.sh` (copies the other engineers' artefacts; reports anything missing).
3. `mk-selfinit.sh` (the self-test initramfs; the only input it needs is the busybox already in `a9linux/artefacts/initramfs.gz`).
4. `make-variants.sh` then `run-ladder.sh` — expect the same three outcomes as §5 (02/03 panic in the AIC driver, 04 reaches userland).
5. `mk-handoff-stub.sh` then `run-stub.sh` — expect the stub banner, then userland.

If a step disagrees with §5, the first thing to check is the input hash in
`logs/<name>.meta.txt` against §2; every run records what it actually booted.

## 9. Rules this harness obeys

* **QEMU only.** It never touches the phone and never runs `a9pwn`, `a9drv` or `irecovery`.
* No build, no QEMU and no staging over `/mnt/*` (HANDOFF §9.3); nothing is ever written to `D:`.
* Every device claim stays INFERRED until it runs on the device (`CANNOT-PROVE.md`).
* Results are labelled MEASURED / INSPECTED / INFERRED. A tool's own output is not treated
  as a measurement until it is checked against a second source (HANDOFF §8.12).

---

## 10. Bare-metal Linux re-validation (MEASURED, 2026-10-03)

The workstream moved off the Windows/WSL box. This section is the harness's
re-validation on the new host: Ubuntu 24.04, uid 1000 (no root), no `/dev/kvm`,
`qemu-system-aarch64` **8.2.2 (Debian 1:8.2.2+ds-0ubuntu1.18)** — the version §1
already recorded. The artefacts about to be loaded onto the phone were re-checked
here byte-for-byte, and the harness's own checks were made to *fail* before being
believed (§10.4).

### 10.1 Paths: one file decides them (`qemu-env.sh`)

~20 scripts used to hardcode `/mnt/e/Reverseing/Arlo` and `/opt/a9qemu`. They now
`source "$(dirname "${BASH_SOURCE[0]}")/qemu-env.sh"`, which resolves:

| Variable | Default | Override |
|---|---|---|
| `Q` / `QEMU_DIR` | the directory of `qemu-env.sh` | — (derived) |
| `W` / `ARLO_ROOT` | that directory's `../..` | `A9_ARLO_ROOT` |
| `STAGE` | `/opt/a9qemu` if writable, else `$XDG_STATE_HOME/a9qemu` | `A9QEMU_STAGE` |
| `LOG_SCOPE` / `WIN_SCOPE` | this directory's `logs/` | `A9QEMU_LOG_SCOPE` |
| `LOG_TAG` | empty | `A9QEMU_LOG_TAG` (e.g. `-linux`) |

The WSL defaults are unchanged (root can still write `/opt`), a `/mnt/e` fallback
remains in `resolve-pc.sh`, and the fallback is printed, never silent. No root is
needed anywhere: the whole re-validation below ran as uid 1000.

### 10.2 Staged inputs vs §2 (sha256, MEASURED)

`stage-arlo-inputs.sh`, `stage-qemu-console-kernel.sh`, `mk-selfinit.sh` and
`mk-handoff-stub.sh` were run on this host; every staged input was hashed:

| Input | §2 pin | Staged here | Verdict |
|---|---|---|---|
| `arlo-Image` | `39a27067…` | `39a27067…` | **MATCH** |
| `arlo-Image.gz` | `3eef7ffa…` | `3eef7ffa…` | **MATCH** |
| `arlo-Image-qemu-pl011` | `2697e77d…` | `2697e77d…` | **MATCH** |
| `arlo-initramfs-min.cpio.gz` | `c8b2dbb4…` | `c8b2dbb4…` | **MATCH** |
| `arlo-initramfs-debian.cpio.gz` | `0dae863c…` | `0dae863c…` | **MATCH** |
| `System.map`, `System.map-qemu-pl011` | `821a3f3a…`, `07408377…` | same | **MATCH** |
| `source-n69.dtb` (reference copy) | `cbb79a14…` | `cbb79a14…` | **MATCH** |
| `handoff-stub.bin` (357 B) | `45c8eae0…` | `45c8eae0…` | **MATCH** — the stub rebuilds byte-identically on Linux/binutils 2.42 |
| `stock-Image` (stand-in, 58,075,528 B) | `9e114978…` | `9e114978…` | **MATCH** (re-fetched from ports.ubuntu.com by `fetch-inputs.sh`) |
| `harness-selfinit.cpio.gz` | `552422d5…` | `350ca58b…` (940,621 B) | **CHANGED — see below** |
| `n69-loader-target.dtb` | `f63bc33c…` (23,061 B) | `1b0ff193…` (23,193 B) | **CHANGED — dt-engineer's file, see below** |

**`harness-selfinit.cpio.gz` could never have matched.** The first build embedded
its build time (cpio member mtimes plus gzip's name/timestamp), so its pin was not
re-derivable — a pin on a generated file that cannot be regenerated is decoration.
`mk-selfinit.sh` now fixes member mtimes, sorts the member list, and packs with
`cpio --reproducible | gzip -9n`; **two consecutive builds on this host produced
the identical hash `350ca58b…`** (verified). The new hash is what §2 now records.
One consequence of running unprivileged: `mknod` needs `CAP_MKNOD`, so the archive
carries no `/dev` nodes. That is stated by the script, not hidden, and it is
harmless here — this kernel has `CONFIG_DEVTMPFS_MOUNT=y` and `/init` mounts
devtmpfs, which is where `/dev` comes from in every run below.

**`n69-loader-target.dtb` moved under us.** dt-engineer edited it at 15:37 today
(23,061 → 23,193 B); it is their scope and was not touched here. The harness staged
a copy at 23,193 B and every run below used that copy, so the runs are pinned to a
known input. §2's pin is stale by their hand and is theirs to re-pin.

### 10.3 Results re-produced on this host

All runs used `-cpu max` (the 16K granule needs it, §4) and our adapted DTB. Logs
are in `logs/` with a `-linux` suffix.

| Run | Log (this host) | MEASURED result | §5 said |
|---|---|---|---|
| 07 — shipping Image, QEMU's DT, `-kernel` | `07-arlo-kernel-virt-dt-linux.log` | **0 console bytes**; PC `ffff…acd7bc` in kernel high VA (MMU on), stable at t=12 s and t=24 s | identical |
| 08 — shipping Image, our adapted DT, via our stub | `08-arlo-kernel-our-dtb-linux.log` | **119 console bytes = the stub's own banner**; PC stable in high VA; framebuffer read-back all-zero → **marker absent** | identical |
| 10 — granule sweep | `10-granule-{cortex-a57,cortex-a53,cortex-a72,max}-linux.log` | a57/a53/a72: PC `0x41055590`, status word at `0x41356800` = **`0x202`** (CPU_STUCK_IN_KERNEL) → refused; `max`: status word `0x0`, **PC in kernel high VA → MMU on, granule accepted** | identical |
| 02 — stock 4K stand-in, our DT, memory unfilled | `02-dtb-unfilled-memory-linux.log` | **KERNEL PANIC** `Attempted to kill the idle task!`, console **5,688 B** | identical |
| 03 — stock 4K, memory filled, A9 AIC left in | `03-dtb-memory-filled-aic-linux.log` | **same panic**, console **5,688 B** | identical |
| 04 — stock 4K, QEMU devices substituted | `04-dtb-qemu-virt-linux.log` | **REACHED USERLAND**, console **18,670 B** | identical, byte count included |
| 05 — hand-off through our stub, DT-delivered bootargs + initrd | `05-loader-stub-handoff-linux.log` | **REACHED USERLAND through the stub hand-off**, console 19,044 B, stub banner present | same result; the size differs because the initramfs was rebuilt here without `/dev` nodes (§10.2) |
| 12 — `nokaslr`, PC → symbol | `12-nokaslr-linux.log` | PC `ffff80008009e8cc` = image offset **`0x9e8cc`**; `early_cpu_boot_status = 0`; resolved with the pinned map (`821a3f3a…`) to **`dl_server_swap_bw+0xfc`** | identical |

The refused PC also resolves to the symbol §4 names, using the map whose hash the
resolver prints:

```
$ bash a9linux/qemu/resolve-pc.sh 0x41055590 0x40080000
  using System.map: …/a9linux/artefacts/kernel/System.map   sha256 821a3f3a…
  PC (phys) = 0x41055590 -> offset 0xfd5590 into the Image
  nearest symbol = __no_granule_support (t) at 0xffff800080fd556c, +0x24
```

### 10.4 Self-checks and negative controls (this host)

| Check | Result here |
|---|---|
| `selfcheck.sh` | **exit 0** — 31 shell + 4 python + 2 docs clean, LF-only; `verify-map-pairing.sh` PASS; all 4 script pins present in README §2 |
| `verify-map-pairing.sh` | **exit 0** — both correct pairings accepted, **both mis-pairings rejected by the discriminator while the footprint rule passes on all four**, all 4 hashes pinned |
| N1 — contents **swapped** between the two pairs (doctored copies) | **exit 1** — all four rows rejected, and verdict (B) reports both Images `*** CHANGED ***`. The real artefacts still PASS afterwards |
| N2 — genuine artefacts, **one comment line appended** to a copy of `System.map` | **exit 1** — the structural rows stay green on all four combinations (the documented blind spot) and only the pin catches it: `System.map b643c66f… want 821a3f3a…` |
| `test-pin-teeth-run.sh` (staleness, end to end) | **exit 0** — altered map hashes to `c83d4df2…`, exactly the value the script documents for its own control, and our pin rejects it |
| `test-pairing-guard.sh build`, `test-doc-agreement-guard.sh build` | run; the scratch dirs are built **outside the repo** in `$STAGE`. kernel-engineer's PowerShell guard itself is Windows-only and **was not run here** — on this host the same failure modes are exercised through `verify-map-pairing.sh` (N1/N2), which is the harness's own independent guard |

The controls use the harness's real scripts, unmodified, against deliberately
doctored inputs; only their `A9_ARLO_ROOT`/`A9QEMU_STAGE` point at the scratch
copies. Nothing under `a9linux/dts/` or in another engineer's scope was touched.

### 10.5 Defects found in this harness by the re-validation (all fixed here)

1. **Two hosts shared one log namespace.** `run-arlo-kernel.sh`'s copy-back had no
   tag, so the first Linux run overwrote `logs/07-…log` and `logs/08-…log`; the
   manual log copies overwrote `logs/10-granule-*.log`. `A9QEMU_LOG_TAG` now
   suffixes the staged name, the copy-back and the framebuffer read-back, and
   `granule-sweep.sh` / `locate-arlo-hang.sh` copy their logs back tagged too. The
   subsequent tagged run wrote `…-linux.log` and left the untagged files alone
   (verified). The incident itself is recorded in §10.6 — it is not recoverable.
2. **`locate-arlo-hang.sh` read the PC after killing QEMU**, so it printed
   `PC=0xunknown` and the symbol resolution below it had never run on any host.
   It now reads the monitor before the kill; §10.3's `dl_server_swap_bw+0xfc` is
   the first time that path produced a symbol.
3. **`test-pin-teeth-run.sh` never called `build`**, so the end-to-end staleness
   control ran `mine` against a missing directory, printed a note on stderr and
   exited 0 — a control reporting success while testing nothing. It now builds
   first and fails if the pin check fails.
4. **The framebuffer verdict grepped a file nothing wrote**
   (`08-fb-readback.txt`), so it always answered "NOT PROVEN by readback". The
   probes now `tee` the monitor read-back and the verdict distinguishes three
   states: marker present / read-back happened and marker absent / no read-back.
   On this host it reports the second — an honest "userland not proven".
5. **`stage-qemu-console-kernel.sh` and `locate-arlo-hang.sh` required
   `wsl.exe -d podman-main`.** Both now use the repository `System.map` copies
   (the Podman path remains a fallback), so the A/B instrument and the hang
   locator work on a host with no WSL at all.
6. **Unprivileged staging and non-reproducible packing** — §10.2.
7. **My own alias bug, found by running the harness rather than reading it:**
   `qemu-env.sh` first exported `WIN_SCOPE` as the *logs directory*, but
   `run-qemu.sh` appends `/logs` to it (on WSL `WIN_SCOPE` was the harness
   directory). The ladder's logs landed in `logs/logs/`. Fixed: `WIN_SCOPE` is the
   harness directory again, `LOG_SCOPE` is the logs directory, and the two now
   yield the same copy target (verified).

### 10.6 Incident, stated plainly: the WSL console logs for 07/08/10 were overwritten

Before `A9QEMU_LOG_TAG` existed, the first Linux run of `run-arlo-kernel.sh`
copied its captures over `logs/07-arlo-kernel-virt-dt.log` and
`logs/08-arlo-kernel-our-dtb.log`, and the manual evidence copy did the same to
the four `logs/10-granule-*.log` files. Those files held the WSL captures of the
same runs. **They are not recoverable**: this tree is not a git repository and no
backup copy of those six files exists on this host (searched). What replaced them
is this host's capture of the same runs — 0 B for 07, the 119-byte stub banner for
08, 119 B for each granule run — which is the same content the WSL runs produced
and is what §10.3 documents. The loss is of provenance, not of kind, and it is
recorded here rather than papered over. From now on the tag makes the two hosts'
logs distinguishable.

### 10.7 What this re-validation proves, and what it does not

Proves (MEASURED, about QEMU `virt` on this host): the artefacts under
`a9linux/artefacts/` are the ones §2 records, except where §10.2 says otherwise;
the shipping 16K `Image` runs with the MMU on and takes no exceptions under
`-cpu max`; the three refused CPU models park in `__no_granule_support` with
`0x202`; the `nokaslr` PC resolves to `dl_server_swap_bw+0xfc`; the harness's own
guards pass and were each shown failing.

Does **not** prove, and must never be quoted as: anything about the iPhone. From
[`CANNOT-PROVE.md`](CANNOT-PROVE.md) §0:

> This harness can prove that a *device tree shape*, an *initramfs* and a *loader
> hand-off sequence* are self-consistent enough for our kernel to reach a shell on
> a machine that is not the phone (demonstrated, with a two-symbol console test
> variant — §8). It can prove **nothing** about the A9 bootrom, the real DRAM map,
> the real interrupt controller, the real console, the real panel, the real
> power/clocks, or the secondary CPU bring-up.

Specifically for §10.3: the absent framebuffer marker means **userland was not
proven to have run for the shipping binary**, and a marker that is absent says
nothing about *why*; the shipping kernel's console is silent by configuration, so
"stuck" and "idle with nowhere to print" remain indistinguishable for that binary
(`CANNOT-PROVE.md` §4, §8). The granule result is a statement about **QEMU's CPU
models**, not about A9's `ID_AA64MMFR0_EL1` (`CANNOT-PROVE.md` §9). The A9 answer
needs the phone, which this harness never touches.
