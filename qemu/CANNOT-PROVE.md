# CANNOT-PROVE — what this QEMU harness can never establish about the iPhone

**Read this before quoting any result out of `a9linux/qemu/`.**

A green run in this directory is evidence about **QEMU `virt`**, a virtual machine with a
PL011 UART, a GICv2, 1 GiB of RAM at 0x40000000 and no AIC, no PMGR, no panel and no
SecureROM. It is **not** evidence about an iPhone SE 1st generation (Apple A9 `s8003`,
board `n69ap`). Every statement below is a device claim that this harness cannot make,
with the reason it cannot and the cheapest thing that *would* settle it.

Labelling follows HANDOFF §9.5: **MEASURED** = observed in a captured log here,
**INSPECTED** = read out of a file, **INFERRED** = reasoning, not observation.

---

## 0. The one-line version

> This harness can prove that a *device tree shape*, an *initramfs* and a *loader
> hand-off sequence* are self-consistent enough for our kernel to reach a shell on a
> machine that is not the phone (demonstrated, with a two-symbol console test variant —
> §8). It can prove **nothing** about the A9 bootrom, the real DRAM map, the real
> interrupt controller, the real console, the real panel, the real power/clocks, or the
> secondary CPU bring-up.

---

## 1. The A9 bootrom / SecureROM hand-off — not modelled at all

* **CANNOT PROVE:** anything about the DFU hand-off, checkm8, image4, iBoot, the SRTG
  state, or what state the A9 is actually in when a9boot gets control.
* **Why:** QEMU starts a CPU at a reset vector *we choose* with registers *we set*. There
  is no bootrom, no SecureROM, no pwned-DFU state, no USB. `-device loader,...cpu-num=0`
  is a fiction we wrote.
* **What would settle it:** the phone. This is the part that gets exactly one attempt.

## 2. The real DRAM map — and the harness actively hides it

* **CANNOT PROVE:** that `/memory` is filled correctly for A9, that the DRAM base is
  0x800000000, that the size is right, or that any loader-supplied address is sane.
* **Why — and this one surprised me (MEASURED):** QEMU's `virt` machine **rewrites a
  device tree supplied with `-dtb`**. `qemu-system-aarch64 -M virt,dumpdtb=…` proves it:
  our `/memory@800000000` is gone from the tree the guest receives, replaced by
  `/memory@40000000` sized to QEMU's RAM, and a `/psci` node is injected that our DTB does
  not contain. Log: `logs/` + `work/dumped-console.dtb` (see `probe-entry.sh`).
  Consequence: **the loader's memory fill is untestable through `-dtb`.** A run that
  "boots with our DTB" boots with QEMU's memory node, whoever filled ours.
* **What we do instead:** `check-dtb.py` audits `/memory` statically (device_type, non-zero
  size, 2 MiB alignment) and refuses to call a zero-size node a pass.
* **What would settle it:** a device boot, or a bootloader/QEMU configuration where the
  DT is not rewritten (our hand-off-stub path still ends up under QEMU's `virt`, because
  the machine model is what provides RAM).

## 3. The real interrupt controller (AIC) — substituted, and load-bearing

* **CANNOT PROVE:** anything about interrupts, timer ticks, FIQ/IRQ routing, AIC event
  registers, or the `apple,s8000-aic` driver on A9.
* **Why (MEASURED, `logs/03-dtb-memory-filled-aic.log`):** with our DT left as-is, the
  stock kernel dies during `init_IRQ`:
  `Internal error: synchronous external abort ... pc : aic_of_ic_init+0x610/0x800` →
  `Kernel panic - not syncing: Attempted to kill the idle task!`. QEMU has no AIC, so the
  driver's first MMIO read is an abort. Every adapted DTB therefore **substitutes a
  GICv2** at QEMU's addresses, and *all* interrupt behaviour in every green run here is
  QEMU's GIC.
* **What would settle it:** a device boot with the real DTB; the AIC driver path is not
  exercised anywhere in this harness.

## 4. The real console — and why our own kernel is invisible here

* **CANNOT PROVE:** that the phone's console works, that `apple,s5l-uart` binds, that
  `stdout-path = "serial0"` reaches a live UART, or that kernel messages appear anywhere
  on the device.
* **Why:** QEMU `virt` provides exactly one UART, a **PL011 at 0x9000000**. A9's console is
  an **`apple,s5l-uart` at 0x20A0C000, driven by `CONFIG_SERIAL_SAMSUNG`** (INSPECTED:
  `drivers/tty/serial/samsung_tty.c` match table entry `apple,s5l-uart` → `S5L_SERIAL_DRV_DATA`).
  A QEMU run that shows a login on `ttyAMA0` has shown nothing about `ttyS5L`.
* **Worse, and specific to us (MEASURED):** our *shipping* kernel
  (`a9linux/artefacts/kernel/config.used`) has
  `# CONFIG_SERIAL_AMBA_PL011 is not set` and no `CONFIG_SERIAL_AMBA_PL011_CONSOLE`, so
  the PL011 earlycon name is not registered either. A QEMU run of **our shipping** kernel
  produces **zero console bytes** — see `logs/07-arlo-kernel-virt-dt.log` (0 bytes) and
  `logs/08-arlo-kernel-our-dtb.log` (119 bytes, and those 119 are our stub's own banner).
  See `console-audit.sh`.
* **Partly mitigated, and this is a control not a fix:** kernel-engineer built
  `Image-16k-qemu-pl011` (sha256 `2697e77d…`), identical to the shipping config except two
  symbols (`CONFIG_SERIAL_AMBA_PL011=y`, `CONFIG_SERIAL_AMBA_PL011_CONSOLE=y`), 16K granule
  kept. With it, QEMU **can** see our kernel: runs 13–16 reach a shell. But every console
  statement from those runs is a statement about **that variant**, not about the binary we
  intend to boot on the phone, and it is still a statement about a PL011, not about
  `apple,s5l-uart`. **The variant must never reach the device.**
* **What would settle it:** a device boot. The A9 console is only proven by characters
  appearing from the real `ttySAC*`/`s5l` path on the phone.

## 5. The real panel — and the framebuffer numbers are mostly placeholders

* **CANNOT PROVE:** that the 640×1136 panel lights, that `simple-framebuffer` is the
  right inheritance mechanism, that the loader's framebuffer base/stride/format match
  what iBoot/the display pipe actually leaves in DRAM, or anything about DSI, backlight
  (DWI) or the display power domains.
* **Why:** QEMU `virt` has **no display device**. There is no scanout, no timing, no
  backlight; the "framebuffer" in the adapted DT is a region of ordinary RAM.
  What a green run *does* show (MEASURED, `logs/04-dtb-qemu-virt.log`) is that the DRM
  stack accepts the **node shape**:
  `[drm] Initialized simpledrm 1.0.0 ... for 7c000000.framebuffer` +
  `simple-framebuffer 7c000000.framebuffer: [drm] fb0: simpledrmdrmfb`. That is a
  statement about property names, geometry arithmetic and simpledrm's parser — not about
  a picture.
* **Honesty note:** unless `a9linux/dts/LOADER-FILL.md` supplies them, the geometry used in
  the adapted DTs (640×1136, stride 2560, `a8r8g8b8`) is **harness placeholder data**
  chosen by me, not a measurement of this panel. Any real values must come from
  dt-engineer's document or the device.
* **What would settle it:** a photograph of the phone's screen, which is what HANDOFF §4
  already says.

## 6. Power domains, clocks, pinctrl, PMGR, cpufreq — switched off, not tested

* **CANNOT PROVE:** that any A9 power domain comes up, that the PMGR/clock tree is
  programmed correctly, that CPU idle/OPP states work, that pinctrl is right, or that the
  kernel's `power-domains`/`clocks` phandles resolve on real hardware.
* **Why:** QEMU has none of these blocks. Every A9 peripheral node is set
  `status = "disabled"` in the adapted DT, `power-domains` is stripped from the
  framebuffer node (a provider that never probes would leave simpledrm deferred forever),
  and `operating-points-v2`/`performance-domains` are removed from the CPU nodes. Each
  transform is recorded in the `*.transform.txt` beside each adapted DTB.
* **What would settle it:** a device boot; this is the classic silent-hang territory and
  the harness is blind to all of it.

## 7. Secondary CPU bring-up (spin-table) — cannot be exercised at all

* **CANNOT PROVE:** that a9boot parks CPU1 where the DTB says, that the A9's release
  protocol works, that `cpu-release-addr` is correct for this SoC, or that a second CPU
  ever comes online on the phone.
* **Why (MEASURED):** QEMU `virt` holds secondary cores **powered off**; only PSCI can
  release them, and a spin-table mailbox is not consulted. `-device loader,...,cpu-num=1`
  does **not** start a powered-off core — our stub's CPU1 banner never appears, and the
  kernel reports `CPU1: failed to come online` / `CPU1: failed in unknown state : 0x0`
  (~6 s timeout) in `logs/04`, `logs/05`, `logs/08`.
* **What the harness does still show (MEASURED, `logs/06-mailbox-observe.log`, read
  through QEMU's monitor from outside the guest because CONFIG_STRICT_DEVMEM blocks
  `/dev/mem` on RAM):** the kernel wrote **0x426d4348** into the mailbox address our DTB
  named — the physical address of `secondary_holding_pen`. So the *kernel half* of the
  contract (it writes where we point, with the value it must) is verified; the *parked
  core half* is not, and that is a9boot's.
* **What would settle it:** the device.

## 8. Our own kernel's boot — demonstrated only for a two-symbol test variant

* **CANNOT PROVE (for the shipping `Image`, sha256 `39a27067…`):** that it reaches userland,
  that it initialises A9 drivers, or where it would stop on the phone.
* **What IS measured:** the *shipping* kernel, booted on QEMU `virt` with our adapted DT,
  runs with the MMU on, takes **no exceptions** (`-d int,guest_errors`), and sits in a
  stable high-VA loop in the scheduler region (`nokaslr` resolution: image offset `0x9e8cc`,
  attributed to `dl_server_swap_bw+0xfc`). It emits no console, so "stuck" and "idle with
  nowhere to print" are indistinguishable **for that binary** (`logs/07`, `logs/08`, §4).
* **What is ALSO measured, and is a different binary:** the QEMU-console variant
  (`Image-16k-qemu-pl011`, two config symbols different, 16K granule kept) boots to a
  **shell** on QEMU `virt` — with QEMU's DT (runs `13`, `16`, `15`) and, more importantly,
  with **our adapted device tree delivered by our own hand-off stub** (`14`:
  `Machine model: Apple iPhone SE (TSMC)`, cmdline read from `/chosen/bootargs`, initramfs
  from `/chosen/linux,initrd-*`, `arlo:/#`). All three initramfs variants reach the shell.
* **Why the distinction matters:** that result validates the *contract* — DT shape, bootargs
  and initrd delivery, entry registers, initramfs handling, userland start — and it does not
  validate the *shipping binary*'s console-less behaviour, nor anything about A9.
* **What would settle it:** the device.

## 9. The 16K granule — QEMU's answer is about QEMU's CPU model, not about A9

* **CANNOT PROVE:** that A9 implements the 16K granule the way the kernel expects, nor
  that any page-table behaviour transfers.
* **Why (MEASURED, `granule-sweep.sh`, `logs/10-granule-*.log`):** our kernel halts in
  **`__no_granule_support`** with status word **0x202 (CPU_STUCK_IN_KERNEL)** under
  `-cpu cortex-a57`, `-cpu cortex-a53` **and** `-cpu cortex-a72`. That routine is reached
  when `ID_AA64MMFR0_EL1.TGran16` reports the granule as unimplemented. Only `-cpu max`
  advertises it, and then the kernel proceeds. **The blocker was the emulated CPU model,
  not QEMU's TCG.**
  Conversely: QEMU's `max` model is not an A9. Nothing here says A9's 16K behaviour,
  TLB behaviour, cache maintenance or errata match.
* **Practical rule:** never conclude "our 16K kernel is broken" from a QEMU run that used
  anything other than `-cpu max`. And never conclude "16K works on A9" from `-cpu max`.

## 10. Timing, watchdogs, resets, storage, USB, PMIC, Wi-Fi

* **CANNOT PROVE:** boot duration, timeout margins (including the ~6 s SMP timeout — TCG
  timing is not a model), watchdog behaviour, reset/PSCI behaviour of the real boot chain,
  or anything about storage, USB host, PMIC or Wi-Fi (upstream A9 has no driver for any of
  them, HANDOFF §4).
* **Why:** TCG execution speed is meaningless as a timing model; QEMU's PSCI is QEMU's.
* **What would settle it:** the device, plus a clock.

## 11. The adapted DTBs are NOT the shipping DTB

Any run that used `n69-qemu-*.dtb` used a **transformed** tree. The transformations are
listed per file in `*.transform.txt`, and they are: memory rebased to QEMU RAM, AIC → GIC,
A9 timer interrupts → GIC PPIs, every A9 peripheral disabled, PL011 grafted as `serial0`,
CPU cpufreq properties removed, framebuffer filled with harness geometry, and
bootargs/initrd written for the hand-off runs. A result from such a tree is a result about
the *shape* we intend to hand the kernel, not about the tree we will hand it.

---

## 12. What this harness CAN show (so the boundary is not read as "it proves nothing")

* MEASURED: a stock arm64 kernel boots, with the `/memory`, `/cpus`, `/chosen`,
  `/aliases`, `/reserved-memory` and `simple-framebuffer` shape we intend, to **userland**
  from an initramfs, with `simpledrm` bound to our framebuffer node
  (`logs/04-dtb-qemu-virt.log`, 18,670 bytes of console).
* MEASURED: the arm64 hand-off sequence itself — `x0 = DTB`, `x1..x3 = 0`, MMU/caches off,
  entry at the Image — works when *our code* performs it rather than QEMU's loader
  (`logs/05-loader-stub-handoff.log`; `handoff-stub.S`).
* MEASURED: a kernel finds its command line and its initramfs **only** through
  `/chosen/bootargs` and `/chosen/linux,initrd-start/end`. Writing `initrd-start` without
  the `linux,` prefix produced a kernel that booted normally and then panicked with
  `VFS: Cannot open root device ""` — a real, silent-until-late failure this harness caught.
* MEASURED: a loader that places the DTB or the initramfs **inside the kernel's own
  image+bss** gets them zeroed before `setup_arch` reads them, producing a total silence
  with no console output at all. Our first stub map did exactly that.
* MEASURED: the kernel writes the secondary CPU's entry address (0x426d4348) into the
  `cpu-release-addr` our DT names.
* MEASURED: QEMU `virt` rewrites a supplied DTB (memory + PSCI) — see §2.
* MEASURED, and the strongest result here: **our kernel reaches a shell on QEMU `virt` with
  our device tree delivered by our own hand-off stub** — `Machine model: Apple iPhone SE
  (TSMC)`, command line from `/chosen/bootargs`, initramfs from `/chosen/linux,initrd-*`,
  `printk: console [ttyAMA0] enabled`, `arlo:/#` (`logs/14-variant-our-dtb-stub.log`). It
  used the two-symbol console variant (§4, §8), so it validates the *contract* rather than
  the shipping binary — and it is the closest thing to the device's first boot that can be
  obtained without the device.
* MEASURED: the harness's own reporting can be wrong in the same way the project's other
  tooling has been. A first version of `run-console-variant.sh` matched only the prompt
  `arlo:/#` and therefore reported the dash and debian runs as failures when both had
  reached a shell with `arlo:\w#`. The fix is in the script; the lesson is in README §6.9.
* MEASURED, and the sharpest form of that lesson: the `System.map` pairing check passed on all
  four combinations while blind to a **stale** map (one appended comment line, no symbol
  changed). It had already been shown to fail for *swaps* — which is not the same as being shown
  to fail for *every* failure mode it claimed to catch. Both implementations now carry two
  verdicts (structure **and** hash pins), and both were made to fail before being trusted
  (`test-pairing-guard.sh` for swaps, `test-pin-teeth.sh` for staleness). Generalisation,
  adopted from kernel-engineer and written down here on purpose: **a check earns trust by having
  been shown to fail — for each failure mode it claims.**

That list is the harness's real product: silent, expensive failures that now have a name, a
signature and a test — plus one demonstration that the contract itself works end to end.
None of it is a statement about the phone.
