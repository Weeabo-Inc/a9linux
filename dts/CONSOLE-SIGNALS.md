# Where will console output actually be visible on an iPhone SE 1st gen?

**Task:** `task-7` · **Author:** `dt-engineer` · **Date:** 2026-10-03
**Updated:** `task-13` (2026-10-03) — rung C's PHY-tunable blocker is resolved by measurement; the
**ranking is unchanged** (rung C was already above the panel), only its status is. See
[AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md).
**Question asked by `lead`:** a green boot with nothing observable is unfalsifiable. Where does
output actually appear?

**Labels** (HANDOFF §9.5): **MEASURED** = read from bytes on disk · **INSPECTED** = read from a
cited source · **INFERRED** = reasoned, not confirmed · **UNKNOWN** = nobody has established it.

---

## Bottom line

| # | Channel | Reachable today? | Cost | Verdict |
|---|---|---|---|---|
| 1 | **UART console** (SoC UART @ `0x2_0A0C0000`) | **No, not without hardware work.** Lightning carries no UART pins | Low **if** you have the hardware; impossible otherwise | Best channel, blocked on physical access |
| 2 | **Panel** via `simple-framebuffer` + fbcon | Only if **a9boot lights the panel first** | **Very high** — a9boot becomes a display driver | Not a rung-1 signal |
| 3 | **USB gadget console** over the existing Lightning cable | **Values in hand; DTB filled.** Still needs the boot to reach userspace | Medium, and *measured* | The most promising cheap channel — **no longer blocked on unknowns**. Fill + verification: [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) |
| 4 | **DFU descriptor changes** (`PWND:[checkm8]`) | **Yes, already working** | Already paid | Proves the exploit only, not Linux |

The honest summary: **on this device, at this stage, we cannot yet see Linux boot.** The two
channels that would show it — UART and panel — each need something we do not have. The cheapest
genuinely new capability is the USB gadget console, and its blocker was **four 32-bit numbers that
are readback-able from hardware** — not a research programme. **As of `task-13` those numbers are
measured and the `ausbphy0` node is filled and verified in the compiled blob**
([AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)); what is left for rung C is the boot and the userspace
gadget, not an unknown. That remains the recommendation, with rung B still needed to cover a
pre-userspace hang.

---

## Q1 — Is the A9/n69ap debug UART physically reachable?

### What is established

**The UART exists in silicon and the kernel can drive it.** INSPECTED, three independent ways:

| Fact | Source |
|---|---|
| UART at physical `0x2_0A0C0000`, `apple,s5l-uart`, `reg-io-width = <4>`, `status = "okay"` | MEASURED in the built DTB — see [PLACEHOLDER-INVENTORY.md](PLACEHOLDER-INVENTORY.md) §1 |
| Driver matches it | `drivers/tty/serial/samsung_tty.c:2640` — `{ .compatible = "apple,s5l-uart", .data = S5L_SERIAL_DRV_DATA }` |
| Console driver compiled in | `.config` — `CONFIG_SERIAL_SAMSUNG=y`, `CONFIG_SERIAL_SAMSUNG_CONSOLE=y`, `CONFIG_SERIAL_CORE_CONSOLE=y` |
| Early console declared | `drivers/tty/serial/samsung_tty.c:2851` — `OF_EARLYCON_DECLARE(s5l, "apple,s5l-uart", apple_s5l_early_console_setup)` |
| Kernel is told to use it | DTB `/chosen/stdout-path = "serial0"` + `/aliases/serial0 = "/soc/serial@20a0c0000"` |

So the **software** side is complete and needs no patch. That is the good news and it is solid.

### What is NOT established: how to physically get at it

**The Lightning connector does not carry a UART.** INSPECTED — the full pinout is eight pins:

| Pin | Signal | Function |
|---|---|---|
| 1 | GND | Ground |
| 2 | L0p | Lane 0 positive |
| 3 | L0n | Lane 0 negative |
| 4 | ID0 | Identification / control 0 |
| 5 | PWR | Power |
| 6 | L1n | Lane 1 negative |
| 7 | L1p | Lane 1 positive |
| 8 | ID1 | Identification / control 1 |

Source: [Lightning (connector) — Wikipedia](https://en.wikipedia.org/wiki/Lightning_(connector)).
Ground, power, one or two differential USB lanes, and two ID/control lines. **There is no TX, no
RX, no debug pin.** The phone's Lightning receptacle is a USB device port plus a proprietary
accessory link — not a serial port.

Therefore the SoC's debug UART can only be reached one of two ways, and **both are INFERRED**:

1. **Board-level test points.** The UART is almost certainly brought out to pads on the n69ap
   logic board (Apple routes it for factory test). Finding them needs the iPhone8,4 boardview or
   schematic, then microsoldering a 1.8 V UART adapter. **What settles it:** the iPhone8,4
   boardview/schematic, or a continuity/scope hunt on a scrap board, or an X-ray/teardown source
   that names the pads. None of these is in this workspace. Note the "almost certainly" — I have
   **not** verified that n69ap exposes UART pads at all; that is an assumption from how Apple
   boards are generally built, not a measurement.
2. **An Apple DCSD-class engineering cable.** These tunnel a serial console over Lightning's
   ID/lane protocol. A vendor listing describes DCSD cables covering the **A7–A11** generations
   ([JC B-BOX Pro / DCSD engineering cable](https://www.quecoo.com/products/jc-b-box-pro-dfu-tool-windows-dcsd-cable-engineering-cable-one-key-purple-mode-for-for-ios-a7-a11-nand-syscfg-data-read-write)),
   which includes A9. But the cable only works when the device is in the mode that routes its
   debug UART to the connector — a mode **iBoot enables**, not our loader. Our boot path is
   checkm8 → pwned DFU → a9boot; iBoot never gets to run its normal boot. **What settles it:**
   obtain a DCSD-class cable and test whether it produces output during a *stock* DFU session at
   all. If it does not print during stock DFU, it will not print for us either, because the
   routing is set up before our code runs.

The [Hitchhacker's Guide to iPhone Lightning and JTAG Hacking](https://av.tib.eu/media/62254) is
the right starting point for the board-level route.

### Why m1n1 does not answer this

m1n1's source is off-limits (HANDOFF §0.5, §9.9), so its per-board bring-up tables cannot be
consulted. That does not matter here: **this is a hardware-routing question, not a software one.**
No source tree can tell us whether a pad exists on a board. It is settled with a scope and a
schematic, or with a cable and an experiment — not by reading code.

### Verdict on Q1

> **INFERRED (high confidence, from the Lightning pinout): the A9 debug UART is NOT reachable
> through the Lightning connector as a plain serial port.** Reaching it requires either
> board-level probing/soldering or an Apple DCSD-class cable with iBoot-side routing that our
> boot path never sets up. **UNKNOWN:** whether n69ap exposes UART test pads, and whether a DCSD
> cable prints during stock DFU on this exact model. **What settles both:** a boardview/schematic,
> a scope, or one DCSD cable and ten minutes.

---

## Q2 — Is `simple-framebuffer` the only remaining visible signal? And what does it really cost?

**Yes — for on-device visible output, the panel is the only alternative to the UART.** And the
cost is not what the phrase "fill three DT properties" suggests. Here is the precise obligation.

### The panel signal is 100% a loader obligation

INSPECTED: **there is no Linux driver that can drive the A9 display pipeline, and no node in the A9
device tree for one to bind to.**

```
grep -rln "s8000\|s5l8960x\|apple,dpc\|apple,dcp" drivers/gpu/drm/          ->  no matches
grep -c  "dpc\|adp\|dispc\|display" s800-0-3.dtsi s800x-se.dtsi            ->  0 and 0
```

Two independent reasons, either of which would be sufficient:

1. **No driver.** `CONFIG_DRM_ADP=y` is the Apple Display Pipe driver, and its match table is
   `{ .compatible = "apple,h7-display-pipe" }` / `apple,h7-display-pipe-mipi`
   (`drivers/gpu/drm/adp/adp_drv.c:594-597`, `adp-mipi.c:263-266`). Its own Kconfig help says
   "Chose this option if you have an Apple Arm laptop with a touchbar" — it is the T2/H7 touchbar
   pipe, not A9. My first draft of this document called it "M1/M2-class DCP hardware"; that was
   wrong and is corrected here. Either way it does not match A9.
2. **No node.** The A9 device tree contains **no display controller node at all** — no `dpc`, no
   `adp`, no `display-subsystem`. The only display-adjacent nodes are the backlight (`dwi_bl`) and
   the `framebuffer0` placeholder itself. Even a driver that existed would have nothing to probe.

So nothing in the kernel will initialise MIPI DSI, the display controller, the panel power rails, or
the panel's own init sequence on this SoC.

`simple-framebuffer` is a **consumer** of an already-running scanout, by definition:

> "A simple frame-buffer describes a frame-buffer setup by firmware or the bootloader, with the
> assumption that the display hardware has **already been set up** to scan out from the memory
> pointed to by the reg property."
> — `Documentation/devicetree/bindings/display/simple-framebuffer.yaml:12-16`

And simpledrm does exactly three things with it: parse `reg`/`width`/`height`/`stride`/`format`,
map that memory, and expose it as a DRM device
(`drivers/gpu/drm/sysfb/simpledrm.c:674-686`, `:774-776`, `:954`). It never touches display
hardware.

**So the real rung-2 obligation on a9boot is: initialise and light a 640×1136 MIPI DSI panel on an
A9 with no documentation.** That is the same class of work as writing a display driver, and it is
*not* something the DT contract can carry. Ranking it honestly:

| Piece | Who | Difficulty |
|---|---|---|
| Fill `framebuffer0` reg/mode/status in the DTB | a9boot | trivial — it is 6 properties |
| Reserve the scanout region so the allocator cannot reuse it | a9boot | trivial (see LOADER-FILL §5) |
| Bring up the AUSB/MIPI-DSI PHY + DPC scanout + panel init sequence | **a9boot** | **hard — undocumented, hardware-specific, previously unmeasured** |
| Backlight | **Linux** — `apple,s8000-dwi-bl` / `apple,dwi-bl`, `status = "okay"` in the DTB, `CONFIG_BACKLIGHT_APPLE_DWI=y`, driver at `drivers/video/backlight/apple_dwi_bl.c:105` | easy — one thing the loader does *not* have to do |

That last row is a genuine small mercy and worth telling a9boot-engineer: the kernel can turn on
the A9 backlight itself, so the loader only needs the display pipeline, not the lamp.

### Ranked

**The panel is the most expensive of the three channels and it is not a rung-1 signal.** Do not
let a `simple-framebuffer` node create the impression that the screen is nearly free.

---

## Q3 — Feasible first-boot success signals, ranked by cost

Each row: what it *proves*, what it *costs*, and whether it can be faked by a crash.

### Rung A — "the exploit worked" · cost: **already paid** · host-observable

`PWND:[checkm8]` in the USB serial descriptor, read by `a9pwn` from the host (HANDOFF §6.3).
Already MEASURED by the Lead's tool. **Proves:** code execution in the SecureROM context.
**Does not prove:** anything about Linux. Not affected by this document.

### Rung B — "a9boot executed" · cost: **low** · host-observable, but weak

When the payload takes over, the DFU device stops responding and typically re-enumerates or drops
off. The host sees `USB\VID_05AC&PID_1227` disappear. **Proves:** the payload ran and did not
immediately fault. **Weakness:** "the phone vanished" is indistinguishable from "the phone
crashed". To make it falsifiable, a9boot should actively drive the USB controller and re-enumerate
with a distinctive descriptor (its own VID/PID, or a fixed serial string). That needs a small USB
device stack — real work, but far less than a display pipeline, and it is reusable.

### Rung C — "Linux is running, over the existing cable" · cost: **medium** · host-observable

**A CDC-ACM USB gadget, giving the kernel console on `ttyGS0`.** This uses the device's own USB
device controller and the cable that is already plugged in. Everything on the kernel side is
already enabled:

| Requirement | State |
|---|---|
| USB device controller node | INSPECTED — `usbdev@20c100000`, `apple,s8000-dwc2`, `apple,dwc2`, `dr_mode = "peripheral"` |
| Controller driver | INSPECTED — `drivers/usb/dwc2/params.c:369` matches the generic `apple,dwc2` |
| Gadget + configfs + ACM/serial | INSPECTED — `CONFIG_USB_GADGET=y`, `CONFIG_USB_DWC2_DUAL_ROLE=y`, `CONFIG_USB_CONFIGFS=y`, `CONFIG_USB_CONFIGFS_ACM=y`, `CONFIG_USB_CONFIGFS_SERIAL=y` |
| Console on it | `console=ttyGS0` **last** in bootargs — see [LOADER-FILL.md](LOADER-FILL.md) §4.2 for why the position is load-bearing |

**It needs userspace, and that is a real cost.** `CONFIG_USB_G_SERIAL` (the legacy built-in gadget
that would create `ttyGS0` at kernel init) is **not set**, so `ttyGS0` only exists after an
initramfs `init` script creates the configfs gadget:

```sh
mount -t configfs none /sys/kernel/config
cd /sys/kernel/config/usb_gadget
mkdir -p g1 && cd g1
echo 0x1d6b > idVendor; echo 0x0104 > idProduct
mkdir -p strings/0x409 configs/c.1/strings/0x409
echo a9boot > strings/0x409/serialnumber
echo n69ap-linux-console > strings/0x409/product
mkdir -p functions/acm.gs0          # <-- ttyGS0's console REGISTERS here
ln -s functions/acm.gs0 configs/c.1/
echo "$(ls /sys/class/udc | head -n1)" > UDC   # <-- bind; the fifo starts draining
```

**Two hard limits to plan around** (both derived in [LOADER-FILL.md](LOADER-FILL.md) §4.4):

1. **The console's write path is an 8 KiB kfifo** (`GS_CONSOLE_BUF_SIZE`,
   `drivers/usb/gadget/function/u_serial.c:85`), and it only drains once the host has the port open.
   So the backlog replay is capped at ~8 KiB and starts from the *oldest* buffered message — expect
   the beginning of the boot log, then a gap, then live output. It is a log, not a transcript.
2. **A hang before userspace produces nothing at all**, because the console never registers. And
   `CONFIG_SOFTLOCKUP_DETECTOR`/`CONFIG_HARDLOCKUP_DETECTOR`/`CONFIG_DETECT_HUNG_TASK` are all
   **unset**, so a hang is silent forever. `panic=20` (in the final string) at least turns a *panic*
   into a host-visible reboot instead of a freeze.

So Rung C is a strong signal that Linux reached userspace — and, because of the replay, it also
recovers the earliest part of the boot log. It is **not** a cure for pre-userspace blindness; Rung B
is the only thing that covers that.

**It was blocked, and the blocker was a loader placeholder nobody had listed:**
`drivers/phy/apple/ausb.c:149-156` fails the AUSB PHY probe with `-ENODEV` unless the DT supplies
**four** properties — `apple,cfg0-device`, `apple,cfg1-device`, `apple,cfg0-host`,
`apple,cfg1-host`. Without them `phys = <&ausbphy0 PHY_TYPE_USB2>` never resolves and the dwc2
probe defers forever. The DTS marked exactly this with a comment: `/* Tunables to be filled by
loader */` (`s800-0-3.dtsi:150`).

**Why this was cheap anyway — and this is the useful part.** Those four values are not secrets;
they are the contents of two memory-mapped registers:

```
drivers/phy/apple/ausb.c:102-103
        writel(aphy->cfg0_device, aphy->base + AUSB_CFG0);
        writel(aphy->cfg1_device, aphy->base + AUSB_CFG1);
drivers/phy/apple/ausb.c:31-32
        #define AUSB_CFG0   0x08
        #define AUSB_CFG1   0x0c
```

The PHY node's base is `0x2_0C000030` (MEASURED, DTB). So `cfg0_device`/`cfg1_device` are
**literally the values sitting in `0x20C000038` and `0x20C00003C`.** In pwned DFU the SecureROM
has *already* configured this PHY for USB — that is how the exploit session is talking to the
host at all. **So a9boot can read those two registers and use what it reads.** No guessing, no
m1n1 table, no forbidden source: a readback of live hardware.

**RESOLVED — the readback happened, and the node is filled. `task-13`, 2026-10-03.** The predicted
settling measurement was taken through the pwned payload's MEMC read
([`RUNG2-EVIDENCE.md`](../../RUNG2-EVIDENCE.md) §2, captures `a9pwn-traces/linux/rung2-fresh-1.json`
and `-2.json`): `AUSB_CFG0` = **`0x373723F3`**, `AUSB_CFG1` = **`0x00020E04`**, read twice in two
separate runs and byte-identical, with `AUSB_CTL` = `0x00000010` — RESET/PWRDOWN/SIDDQ clear, which
meets §12 step 2's stated precondition for treating the CFG reads as meaningful. (It does **not**
establish "the PHY is up": bit 4 is set and unnamed by the driver, and the capture's own note reads it
as "not in the DFU-idle state … context, not a tunable" — see [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)
§1.1.) The `ausbphy0` node now carries all four properties, the host pair is `0` by recorded decision,
and the fill was verified **by decompiling the compiled blob**, not
just the source: [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2, §5. The MEASURED-ness caveat above is
discharged: the register mapping was always INSPECTED, and the "SecureROM left the PHY programmed"
step is now MEASURED non-zero and stable rather than inferred from DFU working.

**One trap the fill exposed: the DTS is not what reaches the device.** `a9boot plan` writes these four
properties into the DTB it stages, from `--ausb-cfg0`/`--ausb-cfg1` — a DTS that says the right thing
plus a load-time flag that says nothing is a dead PHY with correct documentation. `plan` refuses that
half-configured case in both directions (`bundle.rs:461-480`), so it is an error, not a silent miss.
Note also that `a9boot`'s own host pair currently **mirrors the device pair** (`bundle.rs:76-78`)
while this DTS uses `0`; both pass the probe (`-host` is never consumed — `ausb.c:63-95` is `#if 0`),
and the conflict is recorded rather than quietly resolved. Details:
[AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md) §2.1 and §4.

**What rung C still needs is no longer a DT unknown:** the boot must reach userspace, where the
initramfs `init` script builds the configfs gadget that creates `ttyGS0` (no
`CONFIG_USB_G_SERIAL`). That is the remaining cost, and it is why rung B remains necessary for the
pre-userspace window.

### Rung D — "Linux is running, on the screen" · cost: **high** · visible on the device

See Q2. Needs the loader to light the panel. Achievable, but it is a project, not a step.

### Rung E — "Linux reached userspace" · cost: **low, but late** · host-observable

Once userspace runs, cheap and unambiguous effects exist that need no display and no UART:
- the Apple watchdog (`watchdog@2102b0000`, `CONFIG_APPLE_WATCHDOG=y`) — arm it and the phone
  visibly resets after the timeout, which the host observes as a re-enumeration;
- a USB gadget that re-enumerates on demand;
- simply **not crashing** for N minutes is *not* a signal and must not be reported as one.

These prove *late* progress. They cannot debug an early hang, which is where the risk is.

---

## What this means for the plan

1. **Do not plan on the UART.** It is the best channel and it is probably not reachable without
   microsoldering. Treat it as an upside, not a dependency. If there is an n69ap board to sacrifice,
   finding the pads is worth a day.
2. **The USB gadget console (Rung C) is the highest-value new capability** — it needs no hardware,
   no soldering, no cable, and its only real blocker was two MMIO readbacks that a9boot does in the
   DFU session it is already running in. **Those readbacks are done and the node is filled
   (`task-13`, [AUSB-FILL-RECORD.md](AUSB-FILL-RECORD.md)).** It should be ranked above the panel.
3. **The panel is rung 2+.** Filling `framebuffer0` is trivial; lighting the panel is not. Do not
   let the trivial part create the impression the hard part is done.
4. Because Rung C lands *after* Linux starts, a9boot still needs its own liveness signal. Rung B
   with a deliberate descriptor is the cheap answer, and it is worth doing before Linux is.
5. **`earlycon` is NOT in the boot-1 string, and adding it is the single most expensive mistake
   available here.** It looks like the safest debug token. But `earlycon` registers a `CON_BOOT`
   console, and `register_console()` then **clears `CON_PRINTBUFFER` on the preferred real console** —
   which is `ttyGS0`. With that flag cleared the gadget replays *nothing* and shows only messages
   logged after it registers. **Adding `earlycon` to a working gadget setup turns a log into silence.**
   Full derivation, and the phase-3 configuration for when a UART actually exists, in
   [LOADER-FILL.md](LOADER-FILL.md) §4.3. The final bootargs string is
   [LOADER-FILL.md](LOADER-FILL.md) §4.1, and it is already in the target DTB.
