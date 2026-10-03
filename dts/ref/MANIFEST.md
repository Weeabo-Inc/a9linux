# `ref/` — pinned inputs, with hashes

Everything in this directory is a **verbatim copy** of a file I read while producing the documents
one level up. Nothing here was edited. The hashes exist so a citation in
[LOADER-FILL.md](../LOADER-FILL.md) or [PLACEHOLDER-INVENTORY.md](../PLACEHOLDER-INVENTORY.md) can
be checked against the exact bytes I read, rather than against a tree that may have moved on.

**Source tree:** `/build/linux-a9` inside the a9build VM — Linux **7.3.0-rc1**.
**Read:** 2026-10-03.

---

## `ref/dts/` — the device tree

| File | SHA-256 | Bytes | Note |
|---|---|---|---|
| `s8003-n69.dts` | `b40f420fba813faa7b011a34af4d28f79e4cc4bdbb07bd568514f55dd8922350` | 341 | board root; byte-identical to `a9linux/src/dts-ref/` |
| `s8003.dtsi` | `2535ca2eee36fb290214ff3ea999d4b249d094d67171d69e3dc12de903d118d1` | 1,425 | S8003 + OPP table; identical to `src/dts-ref/` |
| `s800-0-3.dtsi` | `7dea8e989e58b12b56a33f127b40b332814fa78d46ae4c11ac57bcc0e2f30525` | 8,738 | UART, CPU placeholders; identical to `src/dts-ref/` |
| `s800-0-3-common.dtsi` | `cf65c0da937e05fa768d775c86f0a5b22dab8c0d1d0f2f4371bc3e8c1f9793ba` | 975 | `/chosen`, `/memory`, `/reserved-memory` placeholders; identical to `src/dts-ref/` |
| `s800x-se.dtsi` | `59ea6569c0049befb394775f761def45650e3c540f52ba87e66a2f263e25457a` | 1,591 | iPhone SE common; identical to `src/dts-ref/` |
| `s800-0-3-pmgr.dtsi` | `dbce98106ed4007d7040e2d415cf31bf29f9be8d2fde9f2f8284e38be50569bf` | 19,531 | power domains incl. `ps_disp0`, `ps_mipi_dsi`, `ps_dwi` |
| `s8003-n69.dtb` | `cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` | 22,880 | **the artefact**: what the tree built |
| `s8003-n69.preprocessed.dts` | `8e867c2f9843503acc90768926e8df4d62164686d16665fc5b443bcd5a096928` | 29,869 | the tree's own `cpp` output (`.s8003-n69.dtb.dts.tmp`) |
| `s8003-n69.decompiled.dts` | `32cf17ea5f93e5df987a32a3de65474566fc8c4030d4794fe370ae8962fd97f` | 29,315 | `dtc -I dtb -O dts` of the above — what every "MEASURED in the DTB" claim was read from |

**The five `.dts`/`.dtsi` sources are byte-identical to `a9linux/src/dts-ref/`.** That was checked
by hash, so the earlier reference work copied into this workspace is faithful and was reused rather
than redone.

The parent DTB hash was confirmed **twice**: once against the tree's existing artefact, and again
after the `make dtbs` that was running during this task regenerated it — same hash both times.

## `ref/kernel/` — the cited kernel sources

| File | SHA-256 | Bytes |
|---|---|---|
| `arm64-booting.rst` | `4312d0ef56380dfedd0e2ed0f4375d158e006affbba269877347b0b1b0b55ea0` | 22,716 |
| `arm64-mm-init.c` | `8aa30ec1e4be871863e46067845b716e632f17782dde76907f08a7bf3d3fd965` | 16,701 |
| `arm64-setup.c` | `83f25f862e44515a04dfcb3729f9296dc39475e7ff6fbd72e0439bdb8d9a0b27` | 11,544 |
| `ausb.c` | `1aead7f495aac2e61b3aa0c77af08694cde4ae4682b508f5e2f7a0451d63f295` | 4,625 |
| `of-platform.c` | `54ddf7979d3f84c936e154894d699160ba3ff2608c12edcffe8b8c5fef37109e` | 22,197 |
| `samsung_tty.c` | `5baab0faaf3fd854a82fed9279f853de8e840d6f8bbe25852eb7089e89aced8f` | 72,332 |
| `simpledrm.c` | `7906262fc93513d4e5adf658a0fce2cdda1b710d255da2b812fcbabf6a793919` | 26,137 |
| `simple-framebuffer.yaml` | `021e9990eb37b83b548a379e218043e1a6c324182e2e16ffc49365f4a807a871` | 6,862 |
| `smp_spin_table.c` | `20071a155b1df92d8f8d55b17cbd0e149a05a5a685283f5d955bd78126697aeb` | 3,114 |

Original paths, for re-checking against a live tree:

| Here | Original |
|---|---|
| `arm64-booting.rst` | `Documentation/arch/arm64/booting.rst` |
| `arm64-mm-init.c` | `arch/arm64/mm/init.c` |
| `arm64-setup.c` | `arch/arm64/kernel/setup.c` |
| `ausb.c` | `drivers/phy/apple/ausb.c` |
| `of-platform.c` | `drivers/of/platform.c` |
| `samsung_tty.c` | `drivers/tty/serial/samsung_tty.c` |
| `simpledrm.c` | `drivers/gpu/drm/sysfb/simpledrm.c` |
| `simple-framebuffer.yaml` | `Documentation/devicetree/bindings/display/simple-framebuffer.yaml` |
| `smp_spin_table.c` | `arch/arm64/kernel/smp_spin_table.c` |

Additional sources cited in the documents but **not** copied here, because they were read only as
short quoted excerpts: `drivers/of/base.c`, `drivers/of/fdt.c`, `drivers/tty/serial/earlycon.c`,
`drivers/tty/serial/serial_core.c`, `drivers/gpu/drm/sysfb/drm_sysfb.c`,
`drivers/pmdomain/apple/pmgr-pwrstate.c`, `drivers/pmdomain/core.c`, `drivers/clk/clk.c`,
`drivers/usb/dwc2/params.c`, `drivers/video/backlight/apple_dwi_bl.c`, `arch/arm64/kernel/smp.c`,
`kernel/printk/printk.c`, `include/linux/console.h`, `init/main.c`,
`Documentation/admin-guide/kernel-parameters.txt`, and — for the bootargs **ordering** analysis in
LOADER-FILL §4 — `drivers/usb/gadget/function/u_serial.c`, `drivers/usb/gadget/function/f_acm.c`
and `drivers/tty/vt/vt.c`.

Every one of those citations is re-checked by
[`build/verify-bootargs-claims.sh`](../build/verify-bootargs-claims.sh), which exits non-zero if a
load-bearing claim stops holding — so a kernel-tree update cannot silently invalidate the bootargs
string.

## Configuration

| File | Note |
|---|---|
| `/build/linux-a9/.config` | `eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041` — the **live** config, 16K pages |
| `/build/linux-a9/.config.old` | `a5cbcb0d3fe655888106672e6fe03477b63d51bd36bbcfc4f5145627d906b208` |
| `a9linux/artefacts/config_16k` | **identical to `.config.old`**, i.e. stale by 82 symbol lines |

The drift contains **zero** console- or framebuffer-relevant symbols, so every config-derived
conclusion in these documents holds for both files. MEASURED — see `PLACEHOLDER-INVENTORY.md` §3.

---

## What is deliberately absent

**No m1n1 source.** HANDOFF §0.5/§9.9 forbids it, and nothing in this directory depends on it. Where
a value would normally come from m1n1's per-board tables, the documents say so and name the
alternative measurement instead — see `LOADER-FILL.md` §8.
