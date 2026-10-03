# n69ap loader-owned placeholder inventory

**Task:** `task-7` · **Author:** `dt-engineer` · **Date:** 2026-10-03
**Deliverable 1 of 3.** Companion: [LOADER-FILL.md](LOADER-FILL.md) (the contract) ·
[CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) (where output appears).

**Labels** (HANDOFF §9.5): **MEASURED** = read from bytes on disk · **INSPECTED** = read from a
cited source · **INFERRED** = reasoned, not confirmed.

---

## 0. Method, so these numbers can be re-derived

Everything below comes from the DTB the kernel tree actually built, not from the `.dts` sources —
the two can drift, and this is exactly the task where a plausible-looking value is worse than none.

| Step | Command (inside the a9build VM) |
|---|---|
| Hash the artefact | `sha256sum arch/arm64/boot/dts/apple/s8003-n69.dtb` |
| Decode it | `scripts/dtc/dtc -I dtb -O dts arch/arm64/boot/dts/apple/s8003-n69.dtb` |
| Check the driver side | `grep`, `sed` against `/build/linux-a9` as cited per row |

**The artefact, MEASURED:**

```
path   : /build/linux-a9/arch/arm64/boot/dts/apple/s8003-n69.dtb
size   : 22,880 bytes
sha256 : cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc
kernel : Linux 7.3.0-rc1  (tree /build/linux-a9)
decoded: a9linux/dts/ref/dts/s8003-n69.decompiled.dts
         sha256 32cf17ea5f93e5df987a32a3de65474566fc8c4030d4794fe370ae8962fd97f
```

A decoded copy and all five `.dts`/`.dtsi` inputs are pinned under [`ref/`](ref/MANIFEST.md); the
five inputs are byte-identical to `a9linux/src/dts-ref/`, so that earlier reference work is
faithful and was reused rather than redone.

**The in-tree artefact above is unchanged by this task, and that is correct.** `s8003-n69.dtb` is the
*kernel's* as-built DTB and the **parent** of the round-trip (`build/build-dtb.sh:31`); the loader's
fills belong in `n69-loader-target.dtb`, which is the diff target `a9boot` patches. After `task-13`
filled `ausbphy0` (§2.7) the loader target is 23,193 B / `1b0ff193…` (was 23,061 B / `f63bc33c…`),
rebuilt with the project script and verified by decompiling the blob. Before/after hashes for both
source and blob: [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §3.

**One pre-existing warning, so nobody chases it:** the tree's own DTB build already emits
`Warning (simple_bus_reg): /soc/bus@20c000000: simple-bus unit address format error, expected
"20c900000"`. It is upstream's (`reg = <0x2 0xc900000 ...>` under a node named `bus@20c000000`),
cosmetic, and not ours.

---

## 1. Early-boot node audit — what the kernel needs to reach a console

Every node the kernel touches before or during early console setup. "Loader must supply" means
the value is wrong, absent, or conditional in the DTB as built.

| Node / property | As built (decoded) | Loader must supply? | Evidence |
|---|---|---|---|
| `/memory@800000000/reg` | `<0x08 0x00 0x00 0x00>` → base `0x8_0000_0000`, **size 0** | **YES — mandatory** | MEASURED |
| `/chosen/stdout-path` | `"serial0"` | **No — already correct** | MEASURED |
| `/aliases/serial0` | `"/soc/serial@20a0c0000"` | **No — already correct** | MEASURED |
| `/soc/serial@20a0c0000` | `apple,s5l-uart`, `reg = <0x2 0xa0c0000 0x0 0x4000>`, `reg-io-width = <4>`, `status = "okay"` | **No** — but the loader must enable its **clock, power domain and pinmux** (none of which are DT properties) | MEASURED (DTB) + INSPECTED (`s800-0-3.dtsi:79-90`) |
| `/chosen/bootargs` | **property does not exist** | **YES — mandatory** | MEASURED |
| `/chosen/linux,initrd-start` | **absent** | **YES if an initramfs is used** | MEASURED |
| `/chosen/linux,initrd-end` | **absent** | **YES if an initramfs is used** | MEASURED |
| `/cpus/cpu@0/cpu-release-addr` | `<0x00 0x00>` | **Conditional** — see §2.4 | MEASURED |
| `/cpus/cpu@1/cpu-release-addr` | `<0x00 0x00>` | **Conditional** | MEASURED |
| `/cpus/cpu@*/enable-method` | `"spin-table"` | No — and there is no alternative on A9 | MEASURED |
| `/timer` | `arm,armv8-timer`, `interrupt-names = "phys","virt"`, 2 interrupts | **No** | MEASURED |
| `psci` node | **does not exist** | No — A9 has no EL2, so PSCI is not an option (HANDOFF §8.10) | MEASURED |
| `/soc/interrupt-controller@20e100000` (AIC) | `apple,s8000-aic`, `apple,aic` | **No** — but the AIC must be live at entry, which is the loader's / SecureROM's doing, not a DT property | MEASURED |
| `/chosen/framebuffer@0` | `apple,simple-framebuffer`,`simple-framebuffer`; `reg = <0 0 0 0>`; `status = "disabled"`; **no** `width`/`height`/`stride`/`format` | **Conditional** — only if the loader lights the panel | MEASURED |
| `/soc/bus@20c000000/phy@20c000030` (ausbphy0) | `apple,s8000-ausb-phy`,`apple,ausb-phy`; **now carries all four** `apple,cfg{0,1}-{device,host}` — device pair MEASURED, host pair `0` by decision | **No longer** for the device pair: filled in the loader target, verified in the rebuilt blob. See §2.7 | MEASURED in the blob ([AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)) + INSPECTED `ref/kernel/ausb.c:149-156` |
| `/reserved-memory` | present, **zero children** | **Conditional** — see §2.6 | MEASURED |
| `/soc/backlight@20e200080` (dwi_bl) | `apple,s8000-dwi-bl`,`apple,dwi-bl`, `status = "okay"` | **No** — Linux drives the backlight itself | MEASURED + INSPECTED `s800-0-3.dtsi:212-217` |

**Why `stdout-path` alone is enough for the real console.** `drivers/tty/serial/serial_core.c:3140`
calls `of_console_check()` when the UART port is added, and `drivers/of/base.c:2064-2074` registers
it as the preferred console unless `console=` was given on the command line. So the kernel picks up
`stdout-path` by itself. `console=ttySAC0` in bootargs is belt-and-braces, not a requirement — and it
must **not** carry a `,baud`, for the reason in LOADER-FILL §4.

**Why the device is `ttySAC0` and not `ttyS0`.** The Samsung driver's dev name is
`S3C24XX_SERIAL_NAME = "ttySAC"` (`drivers/tty/serial/samsung_tty.c:50`) and the instance number
comes from the alias — `of_alias_get_id(np, "serial")` at `samsung_tty.c:1947`, and the DTB has
`serial0 = "/soc/serial@20a0c0000"`. Getting this wrong in bootargs means no console. INSPECTED.

**A second channel exists — `earlycon` — but it is deliberately NOT used on the first boot.**
`OF_EARLYCON_DECLARE(s5l, "apple,s5l-uart", ...)` (`samsung_tty.c:2851`) means a bare `earlycon` on
the command line resolves through `/chosen/stdout-path` to this UART and prints **before the memory
allocator and before any driver probes**. That is genuinely the earliest output available — but
`earlycon` registers a `CON_BOOT` console, which clears `CON_PRINTBUFFER` on the preferred real
console (`ttyGS0`) and makes the USB console replay **nothing**. The full derivation, and the
phase-3 configuration for when a UART is actually attached, are in
[LOADER-FILL.md](LOADER-FILL.md) §4.3. **Do not add it to the boot-1 string.**

---

## 2. The complete loader-owned placeholder set

Seven items, as of `task-13`. **Updated 2026-10-03:** item §2.7 (`ausbphy0`) is **no longer an open
placeholder for the device pair** — the rung-2 measurement filled it, and the fill is verified in the
compiled blob ([AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)). What remains open there is one *decision*
(the host pair), not a blocker. The first two items are still mandatory for any boot at all; the rest
are conditional on what the loader is trying to achieve.

### 2.1 `/memory@800000000/reg` — MANDATORY

```
as built : reg = <0x08 0x00 0x00 0x00>      base 0x8_0000_0000, size 0
target   : reg = <0x08 0x00 0x00 0x80000000> base 0x8_0000_0000, size 0x8000_0000 (2 GiB)
```
Four cells = 2 address + 2 size, per the root node's `#address-cells = <2>` / `#size-cells = <2>`.
The upstream source marks it `/* To be filled by loader */`
(`arch/arm64/boot/dts/apple/s800-0-3-common.dtsi:33-36`).

- Base `0x8_0000_0000` — **INSPECTED**: it is the node's unit-address, `memory@800000000`.
  A memory node's unit-address is its base address.
- Size 2 GiB — **INSPECTED from the product specification, NOT measured on this device**
  ([iPhone SE benchmarks: 2 GB RAM](https://wccftech.com/iphone-se-benchmarks-reveals-2gb-ram/)).
- **Size 0 is not a "small placeholder", it is a hard stop.** With no memory, arm64 has nothing to
  build the linear map from and panics before it can print. This alone makes the DTB
  unbootable standalone (HANDOFF §8.11).

### 2.2 `/chosen/bootargs` — MANDATORY

**Absent as built.** With `CONFIG_CMDLINE=""` and neither `CONFIG_CMDLINE_EXTEND` nor
`CONFIG_CMDLINE_FORCE` set, the kernel is handed an **empty** command line — INSPECTED at
`drivers/of/fdt.c:1124-1145`:

```c
	p = of_get_flat_dt_prop(node, "bootargs", &l);
	if (p != NULL && l > 0)
		strscpy(cmdline, p, min(l, COMMAND_LINE_SIZE));
	...
#else
	/* No arguments from boot loader, use kernel's cmdl */
	if (!((char *)cmdline)[0])
		strscpy(cmdline, CONFIG_CMDLINE, COMMAND_LINE_SIZE);
```

Nothing to append, nothing to fall back to. No `earlycon`, no `console=`, no `loglevel`. The full
string and the justification for every token are in LOADER-FILL §4.

### 2.3 `/chosen/linux,initrd-start` and `/chosen/linux,initrd-end` — MANDATORY IF AN INITRAMFS IS USED

**Both absent as built.** A single u64 each, in **two** big-endian cells —
`drivers/of/fdt.c:817-825` reads `len/4` cells, so four cells here would silently truncate the
address. The kernel then reserves exactly `[start, end)` itself
(`arch/arm64/mm/init.c:278-288`), so these two properties are load-bearing in both directions: a
wrong value either loses the rootfs or reserves the wrong RAM.

### 2.4 `/cpus/cpu@*/cpu-release-addr` — CONDITIONAL, and safe to leave at 0

```
as built : <0x00 0x00> on both cpu@0 and cpu@1
method   : enable-method = "spin-table"
```

Upstream marks both `/* To be filled in by loader */`
(`arch/arm64/boot/dts/apple/s800-0-3.dtsi:35,48`).

**Verified: leaving it 0 is safe, and yields a clean single-CPU boot — not a hang.** Three separate
reads of the kernel source:

1. `arch/arm64/kernel/smp_spin_table.c:71-72` — `if (!cpu_release_addr[cpu]) return -ENODEV;`
   **There is no write to physical address 0.** Without this guard, `<0 0>` would be a
   memory-corruption bug; with it, it is a clean refusal.
2. `arch/arm64/kernel/smp_spin_table.c:55-59` — `of_property_read_u64` on `<0 0>` *succeeds*
   (it is a well-formed value), so `cpu_init` returns 0 and `smp_cpu_setup`
   (`arch/arm64/kernel/smp.c:494-503`) marks cpu1 possible without error.
3. `arch/arm64/kernel/smp.c:810-818` — `err = ops->cpu_prepare(cpu); if (err) continue;` — cpu1 is
   simply never marked present. One CPU, no warning storm, no hang.

**Fill it only if you have actually parked the secondaries**, and then follow
`Documentation/arch/arm64/booting.rst:589-601` exactly: the release location must be a
naturally-aligned 64-bit zero-initialised location **inside a reserved region** (`/memreserve/` or
`/reserved-memory`), and the CPUs must be spinning there in that region. A plausible-looking
address with nothing spinning behind it turns a working single-CPU boot into a dead SMP bring-up —
this is the highest-risk value in the whole contract, precisely because it looks like progress.

**Recommendation for rung 1: leave both at `<0 0>` and take the single CPU.** A9 has two cores in
one cluster; one core is enough for a console and an initramfs userland.

### 2.5 `/chosen/framebuffer@0` — CONDITIONAL (rung 2 only)

```
as built : reg = <0x00 0x00 0x00 0x00>;  status = "disabled";
           no width, height, stride, format
```

Upstream: `reg = <0 0 0 0>; /* To be filled by loader */` and
`/* Format properties will be added by loader */`, with the node deliberately pre-filled and
disabled — which is exactly what the binding advises
(`simple-framebuffer.yaml:46-50`). The platform-specific first compatible exists because a
pre-filled node needs a way to be identified (`simple-framebuffer.yaml:52-55`).

**It is reachable** — this was worth checking because the node lives under `/chosen`, which has no
`compatible` and so is not populated by the normal bus walk. The kernel handles it explicitly:

```c
drivers/of/platform.c:581
	node = of_get_compatible_child(of_chosen, "simple-framebuffer");
	if (node) {
		sysfb_disable(NULL);
		of_platform_device_create(node, NULL, NULL);
```
and `of_get_compatible_child` (`drivers/of/base.c:866-877`) matches **any** entry in the compatible
list — so the *second* compatible, plain `"simple-framebuffer"`, is what does the work.
`drivers/of/platform.c:161` then refuses to create a device unless the node is available, so
`status` must become `"okay"`. The driver that binds is simpledrm
(`drivers/gpu/drm/sysfb/simpledrm.c:954`), and it **fails outright** without the mode properties:
`simpledrm.c:674-686` returns an error for each of `width`/`height`/`stride`/`format`, and
`drivers/gpu/drm/sysfb/drm_sysfb.c:23-31` rejects `width`/`height` of **0** specifically.

Required on top of `reg`/`status`: `width`, `height`, `stride`, `format`. Values, and the format's
honest uncertainty, are in LOADER-FILL §5.

### 2.6 `/reserved-memory` — CONDITIONAL

Present with `#address-cells = <2>`, `#size-cells = <2>`, `ranges`, and **zero children**.
Upstream marks the node body `/* To be filled by loader */`
(`s800-0-3-common.dtsi:38-44`).

**For a serial-console-only rung-1 boot, empty is correct** — the kernel reserves the three things
that would otherwise be clobbered:

| What | Where the kernel reserves it |
|---|---|
| the kernel image itself | `arch/arm64/mm/init.c:293` — `memblock_reserve(__pa_symbol(_text), _end - _text)` |
| the initrd | `arch/arm64/mm/init.c:278-288`, from `/chosen/linux,initrd-*` |
| the DTB blob | `arch/arm64/kernel/setup.c:177` — `memblock_reserve(dt_phys, size)` |

The loader **must** add a child in exactly two cases:

1. **It hands over a framebuffer.** simpledrm does **not** reserve it —
   `simpledrm.c:787` calls `devm_request_mem_region()`, which on System RAM fails by design, and the
   code deliberately carries on with the raw resource (`simpledrm.c:789-797`). Nothing stops the
   allocator handing the scanout buffer to someone else and painting over it. Use a **plain** child
   (not `no-map`, or it leaves the linear map) covering the same range as `framebuffer@0`'s `reg`.
2. **It parks secondary CPUs for spin-table** — those CPUs keep executing for the whole life of the
   kernel, and `booting.rst:589-601` requires their memory to be reserved.

Do **not** add a child for a9boot's own code unless something in it must still be running after the
jump, and never one that overlaps the kernel image, this DTB, or the initrd — `no-map` removes the
range from the linear map entirely.

### 2.7 `/soc/bus@20c000000/phy@20c000030` (ausbphy0) — **FILLED, MEASURED** (device pair)

**Status as of `task-13` (2026-10-03): no longer a boot blocker.** This item was missing from every
earlier list, including the task's — the DTS marked it `/* Tunables to be filled by loader */`
(`s800-0-3.dtsi:150`), a comment with no properties behind it, which is why it looked empty and got
overlooked.

**Before:** absent from the DTB. `drivers/phy/apple/ausb.c:149-156` returns `-ENODEV` from probe on
the first missing property, so the PHY never registered, `phys = <&ausbphy0 PHY_TYPE_USB2>` on
`usbdev@20c100000` never resolved, and the dwc2 probe deferred forever. **USB was dead.**

**After — the four properties, in the compiled blob** (verified by decompiling
`n69-loader-target.dtb` *and* by a raw FDT walk, [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §5):

```
apple,cfg0-device = <0x373723f3>     MEASURED   AUSB_CFG0 @ 0x20C000038
apple,cfg1-device = <0x00020e04>     MEASURED   AUSB_CFG1 @ 0x20C00003C
apple,cfg0-host   = <0x00000000>     DECISION   not measured -- see below
apple,cfg1-host   = <0x00000000>     DECISION   not measured -- see below
```

**Evidence path:** [`../RUNG2-EVIDENCE.md`](../../RUNG2-EVIDENCE.md) §2 →
`a9pwn-traces/linux/rung2-fresh-1.json` (+ `.txt`) and `rung2-fresh-2.json`. Read as little-endian
u32 through the pwned payload's MEMC read, **twice in two separate runs, byte-identical**
(`f3 23 37 37 04 0e 02 00`) — non-zero and stable, which is `LOADER-FILL.md` §12 step 2's pass
condition. `AUSB_CTL` read `0x00000010`, i.e. RESET/PWRDOWN/SIDDQ clear, so the step's stated
precondition for treating the CFG reads as meaningful is met — **but "the PHY is up" is not claimed**:
bit 4 is set, the driver names no bit 4, and the capture's own note reads that bit as "not in the
DFU-idle state … context, not a tunable" (`AUSB-FILL-RECORD.md` §1.1; an adversarial reviewer caught
the over-claim). The measured words were not adjusted, and nothing came from a datasheet or another
SoC.

**What remains — the host pair, a decision rather than a blocker.** `-host` is required to be
*present* (`ausb.c:153-156`) but **nothing in this kernel consumes it**: its only reader,
`ausb_phy_usb2_set_mode()`, is inside `#if 0` (`ausb.c:63-95`). Host-mode tunables were **not
measured** — the PHY is in device role in DFU — so they are `0`, deliberately: copying the measured
device words here would present an unmeasured guess in the syntax of measured data, whereas `0` is
recognisably unset. Settling it needs a host-mode session reading `AUSB_CFG0`/`CFG1`; until then the
value is UNKNOWN.

Two follow-ons this fill does **not** cover:
- **The DTS is not the load-time artefact.** `a9boot plan` writes these properties from
  `--ausb-cfg0`/`--ausb-cfg1` into the staged DTB; and its own host pair currently **mirrors the
  device pair** (`bundle.rs:76-78`), which disagrees with the `0` decided here. Both pass probe; the
  conflict is recorded rather than silently resolved — [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)
  §2.1, §4.
- **USB still is not a console.** `ttyGS0` needs the boot to reach userspace and build the configfs
  gadget (no `CONFIG_USB_G_SERIAL`). See [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) Q3 rung C.

---

## 3. Things that are NOT placeholders (checked, so nobody re-checks)

| Assumption | Reality | Evidence |
|---|---|---|
| "the debug UART is disabled and needs enabling" | It is `status = "okay"`, wired to `stdout-path`, and its driver is compiled in. **No DTS patch is needed for a serial console.** | MEASURED in the DTB; `.config` |
| "`CONFIG_SERIAL_APPLE` must be enabled" | **That symbol does not exist in this tree.** The A9 UART is served by the Samsung driver. `15-bootcheck.sh` greps for `CONFIG_SERIAL_APPLE`/`CONFIG_SERIAL_8250_APPLE` and will always report empty — that is a bug in the check, not a finding. | `grep` over `.config` and Kconfig |
| "`CONFIG_DRM_SIMPLE` handles the framebuffer" | That symbol does not exist. It is `CONFIG_DRM_SIMPLEDRM=y`, and `CONFIG_FB_SIMPLE` is **not** set. | `.config` |
| "the framebuffer node can never bind because it is under `/chosen`" | It binds. `drivers/of/platform.c:581` looks it up explicitly. | INSPECTED |
| "`ps_disp0`/`ps_mipi_dsi` are missing so simpledrm will defer forever" | Both are present (`s800-0-3-pmgr.dtsi:406,575`) and are matched by the generic `apple,pmgr-pwrstate` (`drivers/pmdomain/apple/pmgr-pwrstate.c:308-312`). And simpledrm only *warns* on power-domain failures, except `-EPROBE_DEFER` (`simpledrm.c:512-560`). Low risk. | INSPECTED |
| "the DTB is not reproducible outside `make dtbs`" | It is, byte-exactly — see [build/build-dtb.sh](build/build-dtb.sh) `verify`. | MEASURED |
| "`a9linux/artefacts/config_16k` is the config that built this DTB" | It is byte-identical to the tree's **`.config.old`** (sha `a5cbcb0d…`). The live `.config` is `eaee02be…` and differs in 82 symbol lines — but **zero** console/framebuffer-relevant ones, so every conclusion here holds for both. | MEASURED |
