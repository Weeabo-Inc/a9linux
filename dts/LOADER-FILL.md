# LOADER-FILL.md — the a9boot ↔ n69ap device-tree contract

**Task:** `task-7` · **Author:** `dt-engineer` · **Date:** 2026-10-03
**Deliverable 2 of 3.** Companion: [PLACEHOLDER-INVENTORY.md](PLACEHOLDER-INVENTORY.md) (what is
wrong today) · [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) (where output appears).

**Audience:** whoever writes `a9boot` (`task-16`). This document is the specification for the DTB
that `a9boot` must hand to Linux, and for the parts of the handoff a device tree cannot express.

**Labels** (HANDOFF §9.5): **MEASURED** = read from bytes on disk · **INSPECTED** = read from a
cited source · **INFERRED** = reasoned, not confirmed · **UNKNOWN** = nobody has established it.

> **Every value marked INFERRED in this document must be replaced at runtime with a measured one.**
> This project has been burned seven times by a plausible-looking wrong number (HANDOFF §9.5). The
> three that would hurt most are flagged in §8.

---

## 0. Read this first

**The console question, in short** (full reasoning in [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md)):

1. **The DT side of the serial console is already correct and needs no patch.** `stdout-path`
   points at `serial0`, the alias exists, the node is `status = "okay"`, the driver is compiled in,
   and an early console is declared. This is the one piece of good news in this task, and it is
   MEASURED from the DTB, not assumed from the sources.
2. **What is *not* correct is the physical path to the UART.** Lightning carries no UART pins, so
   the console is only reachable via board-level test points or an Apple DCSD-class cable. Treat
   UART output as an upside, not a dependency.
3. **The panel is rung 2, not rung 1.** Filling `framebuffer0` is six properties; making the panel
   actually display anything means `a9boot` initialises MIPI DSI + the display controller + the
   panel init sequence — and there is neither a driver nor a device-tree node for an A9 display
   controller to bind to (INSPECTED: no match in `drivers/gpu/drm/` for
   `s8000`/`s5l8960x`/`apple,dpc`/`apple,dcp`; `CONFIG_DRM_ADP` matches only
   `apple,h7-display-pipe`; and `s800-0-3.dtsi`/`s800x-se.dtsi` contain no display controller node).
4. **The cheapest genuinely new observable channel is a USB gadget console** over the cable that is
   already plugged in. Its blocker is four PHY properties that are *readback-able from live
   registers* — see §7 and §12 step 2. Ranked above the panel.
5. **The bootargs string is not the obvious one.** It is
   `console=ttySAC0 console=ttyGS0 nokaslr clk_ignore_unused pd_ignore_unused panic=20` (§4.1).
   `console=ttyGS0` must be **last** (that is what makes it `/dev/console`), and **`earlycon` must be
   absent** — it registers a boot console, which clears `CON_PRINTBUFFER` on the gadget and makes it
   replay nothing at all (§4.3). Do not "improve" either choice without reading §4.
6. **The measurements that would remove the remaining unknowns are written down as a numbered
   procedure** in §12, to be run immediately after the first `PWND:[checkm8]`.

The minimum viable rung-1 DTB is: **`memory` filled, `bootargs` added, and nothing else changed.**
That is what [n69-loader-target.dtb](n69-loader-target.dtb) is.

---

## 1. The handoff is bigger than the device tree

A DTB that is perfect in every property still fails if the CPU state at entry is wrong. These are
the loader's obligations that **no DT property can express**, quoted from
`Documentation/arch/arm64/booting.rst` (pinned at [ref/kernel/arm64-booting.rst](ref/kernel/arm64-booting.rst)).

| Requirement | Source | Note for A9 |
|---|---|---|
| DTB placed on an **8-byte boundary**, ≤ 2 MiB, and not inside a 2 MiB region that must be mapped with specific attributes | `booting.rst:53-56` | our blob is 23,089 B; the *placement address* must be 8-byte aligned, the *size* need not be a multiple of 8 |
| `Image` placed **`text_offset` bytes from a 2 MiB aligned base**, anywhere in usable RAM; `text_offset` is typically `0x80000`; place it as close as possible to the start of RAM | `booting.rst:107`, `:138-146` | the 512 KiB between base and image start is free for other purposes |
| If an initrd is passed it must lie **entirely within a 1 GB-aligned window of ≤ 32 GB that also covers the kernel Image** | `booting.rst:148-150` | constrains the layout in §3 |
| Any described memory not reserved is **available to the kernel** | `booting.rst:152-155` | this is why §6 exists |
| **`x0` = physical address of the DTB**; `x1 = x2 = x3 = 0` | `booting.rst:163-168` | — |
| CPU in **non-secure state, EL2 (recommended) or EL1** | `booting.rst:174-177` | **A9 implements no EL2** (`s800-0-3.dtsi:299`, HANDOFF §8.10) → **entry must be at non-secure EL1** |
| **MMU off**; I-cache may be on or off with no stale entries; D-cache cleaned to the PoC | `booting.rst:179-190` | — |
| **Quiesce all DMA-capable devices** | `booting.rst:159-161` | "This will save you many hours of debug." |
| **If `Image.gz` is used, the loader must decompress it** — "The AArch64 kernel does not currently provide a decompressor" | `booting.rst:64-70` | **this applies to us:** `30-build.sh` builds `Image.gz`. Either `a9boot` gunzips in place, or the build target becomes plain `Image` |
| Secondary CPUs with `enable-method = "spin-table"` must be spinning **in a reserved region**, polling a naturally-aligned 64-bit zero-initialised location, converting the read value to native endianness | `booting.rst:589-601` | only if SMP is attempted — see §5 |

**That last row is the whole SMP story.** If `a9boot` cannot park the secondaries, do not fill
`cpu-release-addr`; see §5.

---

## 2. The A9 / n69ap DRAM map

| Item | Value | Label | Source |
|---|---|---|---|
| DRAM base | **`0x8_0000_0000`** | INSPECTED | It is the unit-address of the `memory@800000000` node (`s800-0-3-common.dtsi:33`) — a memory node's unit-address is its base |
| Nominal size | **2 GiB (`0x8000_0000`)** | INSPECTED (product spec, not measured on this device) | [iPhone SE benchmark/teardown reporting](https://wccftech.com/iphone-se-benchmarks-reveals-2gb-ram/) |
| DRAM end | `0x8_8000_0000` | INFERRED | base + nominal size |
| **Usable extent** | **UNKNOWN** | — | see below |
| Addressable by the AP | `0x8_0000_0000 … 0x8_8000_0000` — entirely **above 4 GiB** | INSPECTED | arithmetic |

**The single most dangerous number in this document is the memory size.** Declaring *more* RAM
than exists makes the kernel hand out pages that do not respond; the failure is not a clean panic,
it is corruption that surfaces arbitrarily later. Declaring *less* merely wastes RAM.

The two things that would settle the usable extent, in order of preference:

1. **Read the on-device ADT.** The Apple Device Tree that iBoot/SecureROM leaves in DRAM contains
   the real DRAM region entries for this board. If the Lead's DFU session can locate it, that is a
   MEASURED answer and beats any inference here. This is the same route that would settle the
   framebuffer format and the AUSB tunables (§7) — **one on-device read settles three open items.**
2. **A walk test from `a9boot`:** write/verify a pattern from `0x8_0000_0000` upward and report the
   last address that round-trips. Slower and destructive, but it is a measurement rather than a
   specification citation.

Until one of those happens, **declare 2 GiB** — it is the nominal part size — and add a
`/reserved-memory` child for anything the loader must keep. Do **not** invent a smaller "safe" size;
a wrong small size silently halves the machine.

---

## 3. The fill contract — exact writes

Six properties. `a9boot` writes these into the DTB it already has in memory, before setting `x0` to
the blob's physical address and branching to the kernel.

### 3.1 Mandatory for any boot

| # | Node path | Property | Cell layout | Value |
|---|---|---|---|---|
| 1 | `/memory@800000000` | `reg` | 2 addr + 2 size | `<0x08 0x00 0x00 0x80000000>` — base `0x8_0000_0000`, size 2 GiB |
| 2 | `/chosen` | `bootargs` | string (NUL-terminated) | §4 |
| 3 | `/chosen` | `linux,initrd-start` | **2 cells** (one u64) | PA where the loader placed the initramfs |
| 4 | `/chosen` | `linux,initrd-end` | **2 cells** (one u64) | `start + size` |

**Cell counts are load-bearing and easy to get wrong.** `reg` is 4 cells because the root node is
`#address-cells = <2>` / `#size-cells = <2>`. `linux,initrd-*` are **2** cells each because
`drivers/of/fdt.c:817-825` reads `len/4` cells as one 64-bit number — writing four cells silently
truncates the address to its low half. (I made exactly this mistake while drafting this contract and
caught it in read-back; see §9.)

If a property does not exist yet, appending it is simpler and safer than resizing the existing
property block. `bootargs` and `linux,initrd-*` are all **absent** in the as-built DTB, so each
needs a new property inserted into `/chosen` — which may require relocating the FDT's structure
block. Budget for that in the patcher.

### 3.2 Worked layout — PROPOSED

`a9boot` chooses the addresses; this is one worked example that satisfies every constraint in §1.
Swap in real sizes.

| Region | Address | Size | Why here |
|---|---|---|---|
| DRAM base (2 MiB aligned ✓) | `0x8_0000_0000` | — | — |
| **kernel `Image`** | `0x8_0008_0000` | `image_size` | base + `text_offset` `0x80000` (`booting.rst:138-146`) |
| **DTB** | `0x8_0400_0000` | 23,089 B (this one) | 8-byte aligned, own 2 MiB region, ≤ 2 MiB (`booting.rst:53-56`) |
| **initramfs** | `0x8_1000_0000` | ≤ ~256 MiB | must sit in the same 1 GB window as the Image — `0x8_0000_0000 … 0x8_4000_0000` covers both (`booting.rst:148-150`) |
| **framebuffer** (rung 2 only) | `0x8_4000_0000` | `0x400000` (4 MiB) | 2 MiB aligned; needs a matching `/reserved-memory` child |

`0x8_4000_0000` for the framebuffer is **INFERRED**. The display controller's real addressability
and alignment constraints are UNKNOWN. What is known: **all** DRAM on this SoC is above 4 GiB, and
iOS itself renders into this DRAM — so the controller necessarily addresses this range. That
argument does not pin the alignment; 2 MiB is a guess chosen to be conservative.

---

## 4. The bootargs string

### 4.1 THE string

```
console=ttySAC0 console=ttyGS0 nokaslr clk_ignore_unused pd_ignore_unused panic=20
```

That is the exact value carried in [n69-loader-target.dts](n69-loader-target.dts) and its compiled
`.dtb`, and `a9boot` should write it verbatim. Everything below is a decision with a reason: the two
`console=` tokens are **ordered**, and one token that looks obvious is **deliberately missing**.
Getting either wrong produces a silent device with no way to tell which choice failed — which is the
specific failure this section exists to prevent.

Nothing is missing from the DTB today, so the kernel currently boots with an **empty** command line
— INSPECTED at `drivers/of/fdt.c:1124-1145`: `bootargs` is read first, and with `CONFIG_CMDLINE=""`
and neither `CONFIG_CMDLINE_EXTEND` nor `CONFIG_CMDLINE_FORCE` set, there is no fallback.

### 4.2 Why `console=ttyGS0` is LAST and `console=ttySAC0` is first

Multiple `console=` tokens are allowed — up to `MAX_CMDLINECONSOLES = 8` (`printk.c:365`) — and every
console that registers and matches gets printk output. What the *order* decides is which one is
`/dev/console`: `__add_preferred_console()` sets `preferred_console` to the entry it has just added,
and `try_enable_preferred_console()` grants `CON_CONSDEV` only when `i == preferred_console`. So the
**last** `console=` becomes the head of the console list, i.e. `/dev/console`
(`kernel/printk/printk.c`).

| Position | Token | What it gets |
|---|---|---|
| first | `console=ttySAC0` | enabled, receives printk, **not** `/dev/console` — a passive observer |
| last | `console=ttyGS0` | enabled, receives printk, **and** is `/dev/console` |

**Gadget last is what makes the USB link interactive.** The initramfs `init` opens `/dev/console` for
stdin/stdout, so a shell on the host over `/dev/ttyACM0` drives the device — not just a log we can
read, but one we can type into. Gadget first would put `/dev/console` on the invisible UART.

**What a captured host-side log lets you conclude.** Because the gadget console registers during
configfs setup, output arriving on the host proves all of: Linux reached userspace, configfs mounted,
the ACM function was instantiated, and dwc2 plus the AUSB PHY enumerated successfully. Absence
proves none of that — and §4.4 is explicit about what absence cannot distinguish.

### 4.3 Why there is NO `earlycon` — and why adding it would silently blind us

**This is the least intuitive line in the contract.** `earlycon` looks like the safest token to add.
It is the one that costs us the most.

`earlycon` registers its console with `CON_PRINTBUFFER | CON_BOOT`
(`drivers/tty/serial/earlycon.c:29-33`). `register_console()` then contains:

```c
	if (bootcon_registered &&
	    ((newcon->flags & (CON_CONSDEV | CON_BOOT)) == CON_CONSDEV)) {
		newcon->flags &= ~CON_PRINTBUFFER;
	}
```

`ttyGS0` *is* the `CON_CONSDEV` console, so **adding `earlycon` clears the gadget console's
`CON_PRINTBUFFER` flag.** That flag is precisely what decides whether a late-registering console
replays the boot log — `get_init_console_seq()`, `kernel/printk/printk.c:3959`:

```c
	if (newcon->flags & (CON_PRINTBUFFER | CON_BOOT)) {
		init_seq = syslog_seq;          /* replay the log from the beginning */
	} else {
		init_seq = prb_next_seq(prb);   /* skip the backlog entirely */
	}
```

`ttyGS0` hard-codes `flags = CON_PRINTBUFFER` (`drivers/usb/gadget/function/u_serial.c:1105`). So
**without `earlycon` it replays the boot log; with `earlycon` it replays nothing** and shows only
messages logged after it registers — which is after userspace has already started, i.e. after the
interesting part.

Since the UART is almost certainly unreachable ([CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) Q1), that
trade is *invisible* early output in exchange for *the entire boot log*. Verdict: **no `earlycon` on
boot 1.** It returns in phase 3 (§4.5) the moment a UART is actually attached — at which point the
UART console, which carries its own `CON_PRINTBUFFER`, replays everything itself and nothing is lost.

`earlycon` is also the *only* token that can trigger this on A9. The other consoles in this tree that
can set `CON_BOOT` are Xen (`hvc_xen.c:751`), SuperH (`sh-sci.c:3532`), MIPS EJTAG
(`mips_ejtag_fdc.c:1137`) and xHCI debug capability (`xhci-dbc.c:926`) — none reachable here.
`dummycon` (`drivers/tty/vt/vt.c`) and the Samsung UART console (`samsung_tty.c`) both set
`CON_PRINTBUFFER` only, with no `CON_BOOT`.

### 4.4 What the gadget can carry, and what it cannot — read before the first boot

`gs_console_write()` does not write to USB. It queues into a **`GS_CONSOLE_BUF_SIZE = 8192`** kfifo and
only pushes when a host request exists (`u_serial.c:85`, and the write path at `:1024-1060`).
Consequences, all of which bound what we can conclude:

- the backlog replay is capped at **~8 KiB**; the remainder is counted as `missed` and is
  unrecoverable — and `cons->missed` is not exposed to userspace, so you cannot even see how much was
  lost;
- the replay starts from the **oldest** still-buffered message, so with a busy log the delivered
  8 KiB may stop short of the failure;
- until the host opens `/dev/ttyACM0` the fifo does not drain, and live messages are dropped into it.

This is exactly why `ignore_loglevel` and `initcall_debug` are **not** in the boot-1 string. They are
excellent tokens and they inflate the log; against a 128 KiB ring (`CONFIG_LOG_BUF_SHIFT=17`,
`.config:159`) feeding an 8 KiB window, inflating the log directly reduces the chance that the
delivered slice contains the failure. They belong in phase 2 (§4.5), after the channel is proven.

**What this channel cannot tell you.** A hang or panic *before* userspace sets the gadget up produces
**nothing at all**, because the console never registers. `CONFIG_SOFTLOCKUP_DETECTOR`,
`CONFIG_HARDLOCKUP_DETECTOR` and `CONFIG_DETECT_HUNG_TASK` are all **unset** in `.config`, so a hang
is silent forever. No `console=` token fixes that, which is why Rung B — `a9boot` re-enumerating USB
with a distinctive descriptor — still matters in [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) Q3.

### 4.5 The remaining tokens, and the phase-2 / phase-3 strings

| Token | Why | Verified how |
|---|---|---|
| `nokaslr` | `CONFIG_RANDOMIZE_BASE=y`. Deterministic addresses during bring-up, so a fault address in a log can be matched to a symbol by hand instead of by luck | `kernel-parameters.txt:4584`; `.config:562` |
| `clk_ignore_unused` | Stops the clock framework gating clocks no driver claims — **exactly our situation**, since the DT says "Use the bootloader-enabled clocks for now" (`s800-0-3.dtsi:85`) | `drivers/clk/clk.c:1586`; `kernel-parameters.txt:793` |
| `pd_ignore_unused` | Same, for generic power domains | `drivers/pmdomain/core.c:1362`; `kernel-parameters.txt:5368` |
| `panic=20` | `CONFIG_PANIC_TIMEOUT=-1` means "reboot immediately", which gives the gadget no time to flush a panic **and** makes a panic indistinguishable from a power event. 20 s to capture, then a reboot the host can observe | `kernel-parameters.txt:4869`; `.config:4861` |

**Phase 2** — add only once the gadget channel is proven to work at all:

```
console=ttySAC0 console=ttyGS0 ignore_loglevel initcall_debug log_buf_len=1M nokaslr clk_ignore_unused pd_ignore_unused panic=20
```

`log_buf_len=n` (`kernel-parameters.txt:3705`) raises the ring above 128 KiB so more history is still
in it when the gadget registers. It does **not** widen the gadget's 8 KiB window, but it makes the
recovered slice reach further back.

**Phase 3** — only when a UART is physically attached and readable:

```
earlycon console=ttySAC0 console=ttyGS0 ignore_loglevel initcall_debug log_buf_len=1M nokaslr clk_ignore_unused pd_ignore_unused panic=20
```

> **Accept the trade explicitly.** Per §4.3, `earlycon` clears `CON_PRINTBUFFER` on `ttyGS0`, so in
> this configuration the gadget shows only live output from its registration onward. With a *visible*
> UART that costs nothing, because the UART console replays the whole log itself. Without one, it
> costs the log — which is why phase 3 is written down but not used on boot 1.

### 4.6 Do NOT put a baud after `ttySAC0` — and this is not a style preference

`s3c24xx_serial_console_setup` starts from `int baud = 9600;`. With no `,baud` it calls
`s3c24xx_serial_get_options()`, which **reads the live `UBRDIV` register back** and derives the baud
as `rate / (16 * (ubrdiv + 1))` (`samsung_tty.c:2284-2334`), then re-programs from that. The two
errors cancel, so **the loader's baud round-trips unchanged** — whatever the loader set, the console
keeps, and it matches what `earlycon` inherited.

Forcing `,115200` instead makes the console trust the DT's `clkref` (24 MHz fixed clock,
`s800-0-3.dtsi:21-26`). **If A9's real UART input clock is not 24 MHz, forcing the baud produces
garbage.** Omitting it cannot.

> **Testable prediction, worth writing down before the first boot:** `earlycon` never programs the
> baud divisor (`samsung_early_console_setup`, `samsung_tty.c:2767-2776`, only installs write/read
> callbacks). So in a phase-3 configuration, if the log is **clean at first and turns to garbage** at
> the moment the real console takes over, the DT's `clkref` is wrong and the loader's baud was right.
> `keep_bootcon` would then preserve the readable early console.

Also deliberately **absent**: `keep_bootcon` (only meaningful when a boot console exists — with no
`earlycon` there is none, and a no-op token in a contract is a liability); `maxcpus=`/`nr_cpus=` (§5
shows they are unnecessary); `console=tty0` (rung 2, once the panel is lit); and no `root=` — an
initramfs passed via `linux,initrd-*` becomes the initial rootfs by itself.

---

## 5. CPU release — fill it only if you mean it

`enable-method = "spin-table"` on both CPUs; `cpu-release-addr = <0 0>` on both.

**Leaving it at `<0 0>` is safe and yields a clean single-CPU boot.** Verified in the kernel source,
not assumed:

- `arch/arm64/kernel/smp_spin_table.c:71-72` — `if (!cpu_release_addr[cpu]) return -ENODEV;`
  **No write to physical address 0 happens.** Without that guard this would be a corruption bug.
- `smp_spin_table.c:55-59` — reading `<0 0>` *succeeds* (well-formed value), so `cpu_init` returns 0
  and `arch/arm64/kernel/smp.c:494-503` marks cpu1 possible without an error.
- `arch/arm64/kernel/smp.c:810-818` — `err = ops->cpu_prepare(cpu); if (err) continue;` — cpu1 is
  simply never marked present. **One CPU. No hang, no warning storm.**

**Rung-1 recommendation: leave both at `<0 0>`.** One core is enough for a console and an initramfs
userland.

If SMP is attempted later, `booting.rst:589-601` is the spec and it is stricter than it looks:
a naturally-aligned 64-bit zero-initialised location, **inside a reserved region** (a
`/reserved-memory` child or `/memreserve/`), with the secondaries actually spinning there. A
plausible address with nothing behind it converts a working single-CPU boot into a dead SMP
bring-up. **This is the highest-risk value in the contract precisely because filling it looks like
progress.**

---

## 6. What the loader must do that is not a DT property

The UART is the case that matters. **The DT for the console is already correct, and the console can
still be silent** — because none of the following is expressible as a property:

| Obligation | Why | Evidence |
|---|---|---|
| **Enable the UART clock** | The DT says, in a comment, "Use the bootloader-enabled clocks for now." `clocks = <&clkref>, <&clkref>` are *references to a fixed-clock model*, not a power-on | `s800-0-3.dtsi:85-87` |
| **Ungate `ps_uart0`** | `power-domains = <&ps_uart0>` on the serial node | `s800-0-3.dtsi:88` |
| **Mux the UART pins** | **The serial node has no `pinctrl-0` at all.** Nothing in the DT muxes them; on this boot path nobody else does either | MEASURED — absent from the DTB |
| **Program 115200 8N1** | `earlycon` inherits the divisor and never sets it | `samsung_tty.c:2767-2776` |
| Leave the AIC live | The serial node's interrupt is `<AIC_IRQ 192 …>`; earlycon polls, but the real console uses the IRQ | `s800-0-3.dtsi:83-84` |

The safest assumption about pinmux: **SecureROM already muxed the UART**, because Apple's own boot
chain initialises it early. That is INFERRED, and it is cheap to verify — write a byte to
`0x2_0A0C0000` and look. What would settle it definitively: read the pinctrl state at `0x2_0F100000`
and compare against Apple's ADT, or simply observe whether anything appears on a UART adapter.

**Also not a DT property: the `Image.gz` decompression from §1.** `a9boot` must gunzip, or the build
should ship uncompressed `Image`.

---

## 7. USB console — the cheapest new observable channel

Not rung 1, but ranked above the panel in [CONSOLE-SIGNALS.md](CONSOLE-SIGNALS.md) Q3, and it needs
a DTB change, so it belongs in this contract.

**FILLED — no longer blocked (2026-10-03, `task-13`).** `drivers/phy/apple/ausb.c:149-156` returns
`-ENODEV` from the AUSB PHY probe unless the node carries **four** properties — `apple,cfg0-device`,
`apple,cfg1-device`, `apple,cfg0-host`, `apple,cfg1-host`. Without them the PHY never registers,
`phys = <&ausbphy0 PHY_TYPE_USB2>` never resolves, and the dwc2 controller probe defers forever. The
DTS marked this with a bare comment: `/* Tunables to be filled by loader */` (`s800-0-3.dtsi:150`).
The two device values were then **measured** on hardware and written into the loader target; the fill
and its verification are in [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md).

**How they were filled without guessing:**

| Property | Where the value comes from | Label |
|---|---|---|
| `apple,cfg0-device` | live contents of **`0x20C000038`** = **`0x373723F3`** | MEASURED |
| `apple,cfg1-device` | live contents of **`0x20C00003C`** = **`0x00020E04`** | MEASURED |
| `apple,cfg0-host`, `apple,cfg1-host` | unused in peripheral mode, but must be **present** for the probe to proceed — set to **`0`** by recorded decision, since host-mode tunables were not measured | DECISION |

The register mapping is INSPECTED, not guessed: `ausb.c:102-103` writes `cfg0_device`/`cfg1_device`
straight to `AUSB_CFG0`/`AUSB_CFG1`, which are offsets `0x08`/`0x0c` (`ausb.c:31-32`) from the PHY
base `0x2_0C000030` (MEASURED, DTB).

The reasoning that this works was INFERRED and is now **MEASURED**: in pwned DFU the SecureROM has
already programmed this PHY, because that is how the DFU session is talking to the host. The values
were read back twice in two separate runs, byte-identical (`f3 23 37 37 04 0e 02 00`), and
`AUSB_CTL` read `0x00000010` — RESET/PWRDOWN/SIDDQ clear, meeting §12 step 2's stated precondition,
though **not** proving "the PHY is up" (bit 4 is set and unnamed; the capture's own note calls the
read "context, not a tunable"). See [`RUNG2-EVIDENCE.md`](../../RUNG2-EVIDENCE.md) §2 and
[AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §1.1.

**The DTS is not what the device receives.** `a9boot plan` writes these four properties into the DTB
it stages, from `--ausb-cfg0`/`--ausb-cfg1` (`bundle.rs:382-393`), and it refuses a half-configured
console in both directions (`bundle.rs:461-480`). Its own host pair currently mirrors the device pair
(`bundle.rs:76-78`), which **disagrees** with the `0` decided here; both satisfy the probe, and the
conflict is recorded in [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2.1 rather than resolved
silently. `--dump-dtb` is how the staged blob is checked — currently blocked on the Image-header
size bug (Image header check), quoted in the same record §4.

With the PHY up, the rest is already compiled in: `apple,s8000-dwc2`/`apple,dwc2` on
`usbdev@20c100000` matches `drivers/usb/dwc2/params.c:369`; `CONFIG_USB_DWC2_DUAL_ROLE=y`,
`CONFIG_USB_GADGET=y`, `CONFIG_USB_CONFIGFS=y`, `CONFIG_USB_CONFIGFS_ACM=y`,
`CONFIG_USB_CONFIGFS_SERIAL=y`. Add `console=ttyGS0` to bootargs and the host sees a serial port on
the cable it already has.

---

## 8. INFERRED items, ranked by how badly they would hurt a boot

Ranked by *damage if wrong*, not by confidence.

| # | Item | Label | If it is wrong | What settles it |
|---|---|---|---|---|
| 1 | **Usable DRAM extent** (§2) | INFERRED (nominal 2 GiB) | **Worst case.** Over-declaring hands out dead pages; corruption, not a panic | **§12 step 4** — a cache-disciplined write/verify walk from `0x8_0000_0000` |
| 2 | **UART clock / pinmux / baud enabled by the loader** (§6) | INFERRED obligation | **Total loss of the UART signal.** DT is perfect and nothing prints | Byte at `0x2_0A0C0000`; scope a candidate pad; or read pinctrl at `0x2_0F100000` |
| 3 | **`cpu-release-addr` if filled** (§5) | HIGH RISK if non-zero | Dead SMP bring-up that looks like a hang. *Harmless if left at 0* | Leave at 0 for rung 1. Only fill after `booting.rst:589-601` is satisfied and tested |
| 4 | **`linux,initrd-*` values** (§3.1) | EXAMPLE values in the target DTB | Wrong → kernel unpacks garbage or panics; or reserves the wrong RAM | a9boot computes them; never copy the example |
| 5 | **Framebuffer base address** (§3.2, §10) | INFERRED | Pixels written over live memory — corruption, not a blank screen | **§12 step 5** (needs the step-1 anchor); keep `status = "disabled"` until then |
| 6 | **Framebuffer `format`** | INFERRED | Wrong colours only. Cosmetic, and cheap to iterate | **§12 step 5**; or a known-pattern experiment on the panel |
| 7 | **Framebuffer `stride`** | INFERRED (2560 = 640×4) | Sheared/skewed image | Must equal the real scanout stride — **§12 step 5** |
| 8 | **AUSB `apple,cfg*` tunables** (§7) | **MEASURED — device pair done.** Host pair still a decision, not boot-fatal | USB stays dead if absent; **not boot-fatal** | **DONE** — `RUNG2-EVIDENCE.md` §2; fill in [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) |
| 9 | **`clkref` = 24 MHz is the UART's real input** | INSPECTED (from the DT) | Garbled real-console output after a clean `earlycon` — see the prediction in §4.6 | The one-line symptom above is the test |
| 10 | **DPC addressability / alignment** (§3.2) | UNKNOWN | rung 2 only | Hardware experiment; the DPC base itself is unknown (§12 step 5) |

**One session settles items 1, 5, 6, 7 and 8** — the AUSB registers, the display power domains, and a
DRAM walk, with the ADT read as the conditional bonus. The numbered procedure is **§12**, and it is
written to be executed mechanically rather than re-derived under pressure.

Note what item 2 no longer threatens: with the gadget console (Rung C) the UART is no longer the
*only* success signal, so a loader that forgets the UART clock loses the UART and not the whole
verification story. It does still lose us the earliest boot messages.

---

## 9. How to verify a patched DTB (do not skip this)

```bash
# inside the VM
bash a9linux/dts/build/build-dtb.sh verify   # recipe reproduces the tree's DTB byte-for-byte
bash a9linux/dts/build/build-dtb.sh target   # builds and read-back checks the target DTB
```

`verify` MEASURES that this recipe reproduces `cbb79a14…` exactly, so a diff against anything built
with it is meaningful. `target` rebuilds from the DTS and **decompiles the result again** rather
than trusting the build — which is how I caught two cell-count errors in my own first draft.

To check a DTB that `a9boot` produced at runtime, decompile it and diff against the target:

```bash
dtc -I dtb -O dts -o /tmp/got.dts <the-blob-a9boot-produced>
dtc -I dtb -O dts -o /tmp/want.dts n69-loader-target.dtb
diff -u /tmp/want.dts /tmp/got.dts
```

For the target DTB the expected diff is **exactly four properties** — `bootargs`,
`linux,initrd-start`, `linux,initrd-end`, and `memory/reg` — and nothing else. MEASURED:

```
--- parent (as-built)
+++ target
+		bootargs = "console=ttySAC0 console=ttyGS0 nokaslr clk_ignore_unused pd_ignore_unused panic=20";
+		linux,initrd-start = <0x08 0x10000000>;
+		linux,initrd-end = <0x08 0x1028c000>;
-		reg = <0x08 0x00 0x00 0x00>;
+		reg = <0x08 0x00 0x00 0x80000000>;
```

Any other difference is a bug in the patcher. Note that a `dtc` round-trip emits cosmetic
`clocks_property`/`power_domains_property` warnings ("cell 0 is not a phandle reference") because
phandles are plain numbers instead of `&label` references — those are an artefact of the round-trip
form and are **not** real problems. The DTB's content is unchanged for those properties, which the
diff above proves.

---

## 10. Framebuffer contract (rung 2 — do not start here)

Only if `a9boot` has actually lit the panel. Note that the loader must **not** do the backlight:
`drivers/video/backlight/apple_dwi_bl.c:105` matches `apple,dwi-bl`, the node is already
`status = "okay"`, and `CONFIG_BACKLIGHT_APPLE_DWI=y`. Linux handles the lamp; `a9boot` only needs
the display pipeline.

| Property | Value | Label |
|---|---|---|
| `reg` | `<base_hi base_lo size_hi size_lo>` — 4 cells; example `0x8_4000_0000`, size 4 MiB | INFERRED |
| `status` | `"okay"` — **mandatory**; `drivers/of/platform.c:161` refuses a device for a non-available node | INSPECTED |
| `width` | `640` | INSPECTED (iPhone SE panel) |
| `height` | `1136` | INSPECTED (iPhone SE panel) |
| `stride` | `2560` (= 640 × 4 at 32 bpp) | INFERRED — **must equal the real scanout stride** |
| `format` | one of `a8b8g8r8` / `x8r8g8b8` / `a8r8g8b8` / `x8b8g8r8` | INFERRED — see below |
| `/reserved-memory` child | a **plain** child (not `no-map`) covering the same range | INSPECTED requirement |

All four mode properties are mandatory in practice: `simpledrm.c:674-686` errors out on any missing
one, and `drivers/gpu/drm/sysfb/drm_sysfb.c:23-31` rejects `width`/`height` of **0** specifically.
The binding itself only *requires* `compatible`
(`Documentation/devicetree/bindings/display/simple-framebuffer.yaml:158-161`) — "usually they will
be filled by the bootloader".

**On `format`:** the value is a string, from the enum in the binding
(`simple-framebuffer.yaml:94-119`). I will not guess which one A9 uses. The honest path is a
two-minute experiment once the panel is lit: fill the buffer with pure red as `0x00FF0000`, then as
`0xFF0000`, then as `0x0000FF`-first, and note which channel appears where; that identifies the byte
order immediately. The value that would avoid the experiment is the one in `boot_args.video` /
the ADT on a live device.

**Node naming:** the binding says simplefb nodes "must be named `framebuffer@<address>`", and ours
is `framebuffer@0` while `reg` will say something else. Harmless in practice — Linux matches on
`compatible` and reads `reg` — and fixing it means re-inserting a differently-named node, which is
DTB surgery for no runtime benefit. **Leave the name alone; know it is a conformance wart.**

Finally: **verify nothing else changes.** If the kernel can see a framebuffer it has not been told
about, or the display is running from a region the allocator also hands out, the panel is the least
of the problems.

---

## 11. Provenance of every cited source

All kernel citations are against `/build/linux-a9` (Linux 7.3.0-rc1) inside the a9build VM. Pinned
under [`ref/`](ref/MANIFEST.md) with SHA-256 for each file, so a citation can be checked against the
exact bytes I read. The five `.dts`/`.dtsi` inputs are byte-identical to `a9linux/src/dts-ref/`,
which confirms that earlier reference work was faithful.

| Artefact | SHA-256 |
|---|---|
| `s8003-n69.dtb` (as built, parent) | `cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` |
| `n69-loader-target.dtb` (**23,193 B**, after the `ausbphy0` fill) | `1b0ff193c104f0b198ba97bc4e1f5615baac630c106c8c88d5d3f8066e3c9088` |
| `n69-loader-target.dtb` (23,061 B, before — superseded) | `f63bc33c77771d5489b2e4903987210a0e3be43c8390082269c0b184b3ca4cb9` |
| `n69-loader-target.dts` (**41,086 B**, after the `ausbphy0` fill) | `a7dacd54ee0e34c40d026a3b1fdd69dc8da7d16256014432f1cff8b433dcb072` |
| `n69-loader-target.dts` (37,417 B, before — superseded) | `6ca35ad5e5b8f8d66f4f809841b04dfa1f086f2acacc9ae522ecc8368e956eab` |
| `ref/dts/s8003-n69.decompiled.dts` (as-built, decoded) | `32cf17ea5f93e5df987a32a3de65474566fc8c4030d4794fe370ae8962fd97f` |

Kernel-side drift worth knowing: `a9linux/artefacts/config_16k` is byte-identical to the tree's
**`.config.old`** (`a5cbcb0d…`), while the live `.config` is `eaee02be…` and differs in 82 symbol
lines — **zero** of them console- or framebuffer-relevant, so every conclusion above holds for both.
MEASURED.

**No m1n1 source was read** in producing any of this (HANDOFF §0.5, §9.9). Nothing here depends on
it: every value is either cited from the kernel tree, measured from the DTB, or explicitly labelled
INFERRED with the measurement that would settle it.

---

## 12. APPENDIX — the first-pwned-session procedure

**Execute this immediately after the first `PWND:[checkm8]`, before any loader work.** It is
deliberately mechanical: every step is an address and a read, so it can be run under pressure
without re-deriving anything. Independently converged on from the `a9boot` side (a DRAM
write/verify walk), which is why it is ranked first.

**It settles INFERRED items 1, 5, 6, 7 and 8 from §8 — five of ten.**

Record every result with its **raw** value and a MEASURED label, in a plain text file, so it can be
pasted directly into §2 (DRAM), §5 (framebuffer) and §7 (USB) without a second pass.

### Preconditions

- Device is pwned and a payload can read physical memory / MMIO (a9pwn's payload context).
- The host is logging, with a timestamped serial/USB capture running **before** the device is touched.
- Do **not** reboot the phone between steps; a fresh session invalidates the anchors from step 1.
- **All MMIO reads are 32-bit and little-endian.** Read each address twice with ~100 ms between and
  record both values — a value that changes between reads is not a tunable, it is a moving target.

### Procedure

**0. Host-side baseline, before touching the device.** Record the DFU device's presence, VID/PID
(`05AC:1227`), and USB port path (`Port_#0008.Hub_#0001`, HANDOFF §3). Later, `absent` vs
`same VID/PID` vs `different VID/PID` is what distinguishes "payload ran", "device died" and "gadget
came up".

**1. Anchor hunt — CPU state at payload entry.** Dump `X0`–`X30`, `SP`, `PC`, `SPSR`, and the first
4 KiB at `SP`. *Why:* the ADT / `boot_args` pointer that steps 4 and 5 need is passed in a register
or on the stack at handoff. **This dump is what makes those steps possible**, and I could not derive
the pointer's location from any permitted source — so we take it empirically rather than guess.
Label: the dump is MEASURED; *which* register holds the pointer is UNKNOWN until we look at it.

**2. AUSB PHY tunables — settles item 8 (and unblocks the USB console, `CONSOLE-SIGNALS.md` Q3).**
Read, from base `0x2_0C000030` (MEASURED, DTB):

| Address | Register | Use |
|---|---|---|
| `0x20C000038` | `AUSB_CFG0` (`AUSB_CFG0 = 0x08`, `ausb.c:31`) | → `apple,cfg0-device` |
| `0x20C00003C` | `AUSB_CFG1` (`AUSB_CFG1 = 0x0c`, `ausb.c:32`) | → `apple,cfg1-device` |
| `0x20C000030` | `AUSB_CTL` | context: bit0 `RESET`, bit2 `PWRDOWN`, bit3 `SIDDQ` (`ausb.c:20-23`) — all should read 0 in DFU |
| `0x20C000034` | `AUSB_SIG` | context: bit1 `VBUSDET_FORCE_EN`, bit8 `CABLE_CONNECTED` (`ausb.c:25-28`) |

Interpretation: `ausb.c:102-103` writes these two config words into exactly those registers, so the
values read back **are** the tunables. Pass condition: both `CFG` words non-zero and stable across the
two reads. If `AUSB_CTL` shows `RESET` or `PWRDOWN` set, the PHY is not up and the read is not yet
meaningful — report that instead of the numbers.
`apple,cfg0-host`/`cfg1-host` are required to be *present* by `ausb.c:149-156` but are not consumed
in peripheral mode: write the same pair, or zero, and say which you chose.

> **STATUS: COMPLETE — 2026-10-03, `task-13`.** Executed on hardware; results in
> [`RUNG2-EVIDENCE.md`](../../RUNG2-EVIDENCE.md) §2 and written into `ausbphy0` in the loader target:
> `cfg0-device = 0x373723F3`, `cfg1-device = 0x00020E04`, read twice in two separate runs and
> byte-identical, with `AUSB_CTL = 0x00000010` meeting this step's stated precondition (RESET/PWRDOWN
> clear) — not a claim that the PHY is up. The host pair was chosen as **`0`** (not measured — `-host`
> is `#if 0`-dead in this driver), and the choice with its reasoning is in
> [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2. The fill is verified in the compiled blob (same
> record, §5). Remaining from this step: nothing that a read can settle; a *host-mode* session would
> be needed to give the `-host` pair a real value. Note also that `AUSB_CTL`/`AUSB_SIG` were read once,
> not twice — recorded in the same record, §6.

**3. Display power domains — settles whether any scanout can exist at all (feeds items 5/6/7).**
A9 pmgr base is `0x2_0E000000` (`s800-0-3.dtsi:196-201`, `reg = <0x2 0xe000000 0 0x8c000>`).
The driver takes the offset from the node's `reg` (`pmgr-pwrstate.c:221`), so the absolute addresses
are base + offset:

| Domain | Node | Address | What it tells us |
|---|---|---|---|
| `ps_dwi` | `power-controller@80110` | **`0x20E80110`** | backlight rail |
| `ps_disp0` | `power-controller@802b0` | **`0x20E802B0`** | display controller |
| `ps_mipi_dsi` | `power-controller@802b8` | **`0x20E802B8`** | DSI |

Decode with the driver's own field layout (`pmgr-pwrstate.c:20-35`):
`APPLE_PMGR_PS_ACTUAL = GENMASK(7,4)`, `APPLE_PMGR_PS_TARGET = GENMASK(3,0)`,
`APPLE_PMGR_PS_ACTIVE = 0xf`. **A domain is up when `(reg >> 4) & 0xF == 0xF`.** Also record bit31
`RESET`, bit10 `DEV_DISABLE`, bit9 `WAS_CLKGATED`, bit8 `WAS_PWRGATED`.
Expected: all three **down** in DFU (DFU shows nothing on screen). If they are *up*, a scanout may
already exist and steps 4/5 become much more valuable.

**4. DRAM usability walk — settles item 1, the highest-damage unknown.**
Walk physical `0x8_0000_0000` → `0x8_8000_0000` in 2 MiB steps: write a walking pattern, clean and
invalidate the data cache around the access, read back, record pass/fail.
- **Cache discipline is not optional.** With the MMU/caches on and the region mapped cacheable, a
  write-then-read can be served entirely by the cache and "succeed" on absent memory. Either clean +
  invalidate by VA around every probe, or use a non-cacheable mapping. A walk that skips this will
  report 2 GiB of working RAM on a device that has less — which is exactly the corruption failure §2
  warns about.
- **Do not stop at the first failure.** Record *all* failing intervals, including any hole inside an
  otherwise-working range. The usable map is the set of passing intervals, not one number.
- Report: total usable bytes, every hole, and where a reservation would have to start.

**5. ADT / video parameters — settles items 5, 6, 7 (framebuffer base, format, stride).**
**CONDITIONAL on step 1 yielding a plausible pointer.** Frame these honestly:
- An Apple Device Tree and a `boot_args`-style structure carry the DRAM region and the video mode.
  I have **no permitted source** for the structure's magic, layout or a fixed address — m1n1 is
  forbidden (HANDOFF §0.5) and the kernel tree contains no Apple ADT/boot_args parser (checked).
- **It is also not certain an ADT exists in SecureROM DFU at all.** iBoot normally builds it; in
  DFU we may be before that. That is a real possibility, not a fallback.
- So: if step 1 gives a pointer, follow it and dump the surrounding structure; if not, **record
  "framebuffer parameters UNMEASURED" and stop.** The fallback is reading the display controller's
  own registers — but the A9 DT has **no display node**, so its base address is UNKNOWN (§8 item 10)
  and must not be invented. A guessed DPC base is worse than no answer.

**6. Feed the results back.** Write the measured values into §2, §5 and §7, re-run
`bash build/build-dtb.sh target`, and re-run `bash build/verify-bootargs-claims.sh`. Only then does
`a9boot` have a contract it can implement without guessing.

### What this procedure deliberately does NOT do

It does not write to any SoC register. Steps 2–3 are reads, step 1 is a dump, step 4 writes only to
DRAM inside the range we are trying to characterise. Nothing here can brick a device that is already
pwned, and nothing here depends on a value from a forbidden source.

