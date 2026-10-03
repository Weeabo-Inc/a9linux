<div align="center">
	<h2>a9linux</h2>
</div>

[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)]()
[![Platform](https://img.shields.io/badge/platform-arm64%20%2F%20A9-0078D6.svg?style=flat-square)]()
[![Language](https://img.shields.io/badge/language-DTS%20%2B%20docs-orange.svg?style=flat-square)]()
[![Status](https://img.shields.io/badge/status-kernel%20artefacts%20built-yellow.svg?style=flat-square)]()

### Getting mainline Linux onto an iPhone SE 1st gen: the device tree, the kernel artefacts, and the briefs.

Everything about the A9 (`s8003`, board `n69ap`) Linux bring-up that is *not* the loader and not the userland: the device-tree fills the loader depends on, the kernel images built for it, and the written briefs that decided the approach.

---

### What does this do?

The A9's device tree is where the console lives or dies. The `ausbphy0` node is **conditional on USB being wanted**, and without its four `apple,cfg*` properties the PHY never registers and there is no console at all. Those properties were read off a pwned device rather than guessed:

```
  apple,cfg0-device = <0x373723f3>;   apple,cfg1-device = <0x00020e04>;
  apple,cfg0-host   = <0x00000000>;   apple,cfg1-host   = <0x00000000>;
```

MEASURED from `0x20C000038` / `0x20C00003C` on hardware, read twice and byte-identical, and then **verified inside the compiled blob**: the built `n69-loader-target.dtb` grows by exactly 132 bytes (four 16-byte records plus 68 bytes of strings) and the pre→post decompiled diff shows only those four properties.

The host pair is deliberately **zero, recorded rather than defaulted**: their only reader is inside `#if 0`, and copying the measured *device* words into *host* would present an unmeasured guess in the syntax of measured data. Zero is recognisably unset.

---

### The failure this exists to prevent

**A DTS that says the right thing while the blob says nothing.** The properties are verified by decompiling the built `.dtb` two ways — a full-path walk with `exact` property names, and a raw FDT walk with no toolchain at all — because a change that leaves the source correct and the artefact stale is invisible until the console silently never appears.

---

### Layout

| Path | What |
|---|---|
| `dts/` | The loader-target DTS/DTB, the placeholder inventory, the AUSB fill record, and the console-signal ranking |
| `dts/ref/` | The reference DT the target is a round-trip edit of |
| `artefacts/kernel/` | Built kernel images, config, `System.map` and the build log |
| `briefs/` | The written decisions: m1n1 entry requirements, a direct m1n1 load, a pongoOS loader, the m1n1 handoff, and the Debian rootfs |
| `artefacts/monitor-stub.macho` | The monitor stub used to observe a boot |

---

### Status

Device tree: **filled from measurement and verified in the blob**. Kernel: built (`Image`, a 16K-page variant, `Image.gz`) with `System.map` and a build log; the QEMU harness reaches userland with the stand-in, which is what rung 4 proves. What is *not* yet demonstrated is a boot on the phone itself — that is the loader's next milestone, and this repository deliberately does not claim it.
