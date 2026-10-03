# BUILD-LOG — mainline Linux `Image` for Apple A9 / s8003 / n69ap

**Task:** `task-6` · **Owner:** `kernel-engineer` · **Date:** 2026-10-03
**Status:** ✅ **BUILD COMPLETE AND VERIFIED.** Artefacts copied to `E:`.
Includes the QEMU-only test instrument `Image-16k-qemu-pl011` (§1.1) — **that one is not
for the device.**

Every fact below is labelled **MEASURED** (observed from a command's output),
**INSPECTED** (read in source/config), or **INFERRED** (reasoning, not observed).
This project has paid seven times for a plausible-looking wrong value; two of the
errors caught in this session were in *my own* verification tooling, and both are
recorded in §10 so the next person does not repeat them.

---

## 1. Artefacts (the deliverables)

All under `E:\Reverseing\Arlo\a9linux\artefacts\kernel\`.

| File | Bytes | SHA-256 | Role |
|---|---|---|---|
| **`Image`** | 19,755,520 | `39a270676141f42575cbadffbac085cc120aa1e0f6e61af0b6db8ad5b0c7e228` | **THE DEVICE KERNEL** — sanctioned `config_16k` build |
| `Image.gz` | 8,427,837 | `3eef7ffa5197846a033bf66f5b0dad38d70b7f45e10c95be6b74ce1b06da4051` | same kernel, gzipped; needs loader gunzip (§7.6) |
| ⚠️ `Image-16k-qemu-pl011` | 19,757,568 | `2697e77d901d44844cb8871400ee59119148be08182ccf57bbb6df9b766fde88` | **QEMU TEST INSTRUMENT — NEVER FLASH TO THE DEVICE** (§1.1) |
| `s8003-n69.dtb` | 22,880 | `cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` | device tree |
| `System.map` | 4,592,199 | `821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c` | device kernel symbol table — A/B baseline |
| `System.map-qemu-pl011` | 4,596,104 | `07408377308361cb8d91d35e24857325c98c698c5c0703dd476b3bb7ee46c6ab` | variant symbol table — makes the A/B citable from `E:` alone |
| `config.used` | 138,789 | `eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041` | config the device kernel was built from |
| `config-qemu-pl011.used` | 138,813 | `cba511654f00320d4530813fa4def2c83ec8f8ff60a4271097ba50c580500de5` | config for the QEMU instrument |
| `kbuild-clean.log` | 111,696 | (3,011 lines) | device kernel build log |
| `kbuild-qemu-pl011.log` | 110,647 | | QEMU instrument build log |

**MEASURED** — every binary artefact was hashed twice, by two independent
implementations: `sha256sum` inside the VM (source, ext4) and `Get-FileHash` on
Windows (destination, NTFS). **All match.** The copy out of the VM did not corrupt
anything. The three kernel images have three **distinct** hashes, which is the point.

`Image` **and** `Image.gz` are both shipped deliberately — see §7.6. `Image` is the
one that removes loader work.

**Both builds were structurally identical (MEASURED).** An earlier incremental
build was kept aside and compared: `System.map` symbol sets differ by **0 lines
across 104,189 symbols**, and `Image` size is byte-for-byte the same
(19,755,520). The delivered artefact is nevertheless the **clean** build (§6).

Build identity embedded in the delivered `Image` (**MEASURED**):

```
Linux version 7.3.0-rc1 (root@9ccdc4284c73) (Debian clang version 19.1.7 (3+b1), Debian LLD 19.1.7) #2 SMP PREEMPT Sat Oct  3 10:33:02 UTC 2026
```

`include/generated/utsversion.h` → `#define UTS_VERSION "#2 SMP PREEMPT Sat Oct  3 10:33:02 UTC 2026"`

---

## 1.1 ⚠️ `Image-16k-qemu-pl011` — QEMU-only test instrument. **NOT FOR THE DEVICE.**

**What it is FOR:** `qemu-validator`'s harness could not previously tell *"the kernel is
stuck"* apart from *"the kernel is idle with nowhere to print"* — because the shipping
kernel has **no console driver that QEMU's `virt` machine provides**
(`# CONFIG_SERIAL_AMBA_PL011 is not set`, MEASURED). This variant adds that one console
and nothing else, so a silent QEMU run becomes an interpretable result. It converts a
blind harness into an instrument.

**It must never be written to the iPhone.** It is not the sanctioned configuration; it
exists only so the arm64 hand-off contract can be observed under QEMU.

| | |
|---|---|
| File | `Image-16k-qemu-pl011` |
| Bytes | 19,757,568 (device kernel: 19,755,520 — **+2,048**) |
| SHA-256 | `2697e77d901d44844cb8871400ee59119148be08182ccf57bbb6df9b766fde88` |
| Config | `config-qemu-pl011.used`, 138,813 B, sha256 `cba511654f00320d4530813fa4def2c83ec8f8ff60a4271097ba50c580500de5` |
| Build | `EXIT=0`, 440 s, **2,058** `CC` invocations, 0 warnings, 0 errors |
| `UTS_VERSION` | `#1 SMP PREEMPT Sat Oct  3 11:19:53 UTC 2026` |

### The delta is exactly two symbols — nothing else

`diff config.used  config-qemu-pl011.used` in full (**MEASURED**):

```diff
2072c2072,2073
< # CONFIG_SERIAL_AMBA_PL011 is not set
---
> CONFIG_SERIAL_AMBA_PL011=y
> CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
```

**One line removed, two added. That is the entire delta.** No incidental drift, no
dependency creep. `CONFIG_SERIAL_CORE_CONSOLE=y` and `CONFIG_SERIAL_EARLYCON=y` were
*already* set in the shipping config and therefore do not appear. The `CC` count differs
by exactly **one object** (2,058 vs 2,057) — the PL011 driver. A test kernel that differs
in more ways than the test needs would be a new variable, not a control; this one is a
control.

### It is a control in the BINARIES too — two instruments, explicitly reconciled

`qemu-validator` independently confirmed the delta from the binaries. Their count and
mine looked different at first (`20` vs `62`), so both were re-derived here rather than
left as an apparent disagreement. **They are not in conflict — they measure different
things:**

| Instrument | Shipping | Variant | What it reads |
|---|---|---|---|
| `System.map` lines matching `pl011` | **0** | **62** | the linker's symbol table — uncompressed |
| plain `strings` in the `Image` matching `pl011` | **0** | **20** | literal strings only; **kallsyms names are compressed** |

Both are **decisive** (0 vs non-zero), so the A/B holds under either instrument. The gap
is explained and verified rather than waved away: `pl011_early_write` **is** in the
variant's `System.map` and is **not** findable as a plain string in the variant's
`Image` — exactly what kallsyms compression predicts. The 20 strings are driver identity
and messages, e.g. `Serial: AMBA PL011 UART driver`, `Failed to register AMBA-PL011
driver`, `amba_pl011`, `arm,pl011`, `uart-pl011`.

**Both `System.map` files are shipped in §1 so either figure can be re-derived from `E:`
alone** — previously only the shipping one was reachable, which is why the `62` was not
independently checkable.

**The variant *adds* a console; it does not remove the device one.** Samsung/`s5l` counts
are identical in both kernels under both instruments (`System.map` 23 vs 23; `strings`
36 vs 36). That invariance is what makes this a control rather than a different kernel.

### Independently validated off-device by `qemu-validator`

They ran it under QEMU and reached **userland**, including run 14: **our kernel + our
adapted DT delivered by our own hand-off stub + our initramfs → a shell**, with
`Machine model: Apple iPhone SE (TSMC)`, cmdline sourced from `/chosen/bootargs` only,
initramfs from `/chosen/linux,initrd-*` only, and `printk: console [ttyAMA0] enabled`.
They confirm the identity hash, the two-line config delta, and the header page-size field
independently. `-cpu max` worked with the 16K granule on QEMU 8.2.2, so **no 4K sibling
was needed** — the granule was never dropped.

**Still untested, and it matters:** CPU1 never comes online in any QEMU run, because QEMU
keeps secondaries powered off and only PSCI releases them. So the `spin-table` half of the
contract (§7.3) remains unexercised on the QEMU side. What *was* measured is the kernel's
own behaviour: it writes `0x426d4348` (`secondary_holding_pen`) into the
`cpu-release-addr` that our DT names. That confirms the kernel's side works given a valid
address — which sharpens §7.3 rather than weakening it.

### 16K granule preserved (so it tests the same part we ship) (MEASURED)

```
444:# CONFIG_ARM64_4K_PAGES is not set
445:CONFIG_ARM64_16K_PAGES=y          (count 1; 4K count 0; 64K count 0)
763:CONFIG_PAGE_SIZE_16KB=y
flags = 0xc   -> bits[2:1] = 2 = ARM64_IMAGE_FLAG_PAGE_SIZE_16K
page-table stride reserved_pg_dir -> swapper_pg_dir = 0x4000 = 16K
CONFIG_ARM64_VA_BITS=48
```

**QEMU needs `-cpu max` for a 16K granule.** `qemu-validator` measured that
`a57`/`a53`/`a72` park in `__no_granule_support` (status `0x202`). Do not "fix" that by
switching the variant to 4K — it would then be testing a different part than the one we
ship, which defeats the purpose of the instrument.

### Built in a pristine clone so the device kernel could not be contaminated

The variant was **not** built in `/build/linux-a9`. It was built in a pristine
`git clone` at the identical commit (`/build/linux-a9-qemu`), so the shipping tree's
`.config` and `Image` could not be touched. Verified **after** the clone, the configure,
the build and the copy-out (**MEASURED**):

| | expected | observed |
|---|---|---|
| shipping `.config` | `eaee02be…053b8e1041` | `eaee02be…053b8e1041` ✅ |
| shipping `Image` | `39a27067…5b0c7e228` | `39a27067…5b0c7e228` ✅ |

A method note for anyone repeating this: `make O=…` is not reliably available here,
because the shipping tree already contains in-tree build output (`.config` **and**
`include/config/auto.conf` present). A clone at the same commit is the clean way, and it
also guarantees the variant came from byte-identical sources.

---

## 1.2 Initramfs sizing — MEASURED, and the figures moved while we were talking

This is recorded because a size mismatch here produces a **misleading VFS error**, not a
"the size was wrong" error.

The loader-target DTB carries **example** initrd values
(`a9linux/dts/n69-loader-target.dts`, MEASURED):

```
linux,initrd-start = <0x08 0x10000000>;
linux,initrd-end   = <0x08 0x1028c000>;
```

⇒ window = `0x0028c000` = **2,670,592 bytes**.

Against that window (**MEASURED**, hashed independently and cross-checked against
`debian-ios/dist/*.sha256`, which agrees):

| File | Bytes | vs the 2,670,592 B window |
|---|---|---|
| `arlo-initramfs-debian.cpio` | 20,523,520 | ❌ over by 17,852,928 |
| `arlo-initramfs-debian.cpio.gz` | **7,504,935** | ❌ **over by 4,834,343** |
| `arlo-initramfs-min.cpio` | 1,906,688 | ✅ fits |
| `arlo-initramfs-min.cpio.gz` | 997,191 | ✅ fits |
| `a9linux/artefacts/initramfs.gz` (the old example) | 2,669,875 | ✅ fits, 717 B spare |

**Two findings worth acting on:**

1. **The Debian initramfs does not fit the DTB template's example window.** dt-engineer's
   own `LOADER-FILL.md:408` already says these are EXAMPLE values and *"a9boot computes
   them; never copy the example"* — this is the arithmetic that shows why. If the example
   `initrd-end` were used with the Debian image, the kernel would see roughly the first
   third of a 7.5 MB archive and fail with a cpio/VFS error that points nowhere near the
   real cause.
2. ⚠️ **The figure I was given (7,503,864 B) is not what is on disk now (7,504,935 B).**
   No file of 7,503,864 bytes exists anywhere in the workspace. `arlo-initramfs-debian.cpio.gz`
   has mtime **13:00:04**, i.e. rootfs-engineer rebuilt it *after* that measurement was
   taken. **Any size baked into a DTB or a manifest must be pinned to a hash and
   re-measured at the moment of use** — otherwise the "plausible-looking wrong value"
   injury happens again, and this time it presents as a VFS panic.

**Independently reproduced, three ways.** The mismatch above is not a lone reading:

- `dt-engineer`'s DTB declares the 2,670,592 B window, and their `LOADER-FILL.md:408`
  warns that these are example values.
- `rootfs-engineer`'s guard `debian-ios/scripts/check-loader-window.sh` reproduces it
  independently: **min FITS; dash/debian TRUNCATED**.
- `qemu-validator`'s runs confirm which images are affected and which are not.

**Important scope limit on that last point (worth not over-reading):** the QEMU runs pass
`-initrd` to QEMU, so **QEMU writes `/chosen` on its own device tree** — the window is not
exercised there. The mismatch belongs to the **loader path**, where `a9boot` must compute
the window from what it actually staged. QEMU reaching a shell therefore does **not** clear
this hazard, and should not be read as if it did.

**Two ways to avoid the window problem entirely:**

- **Bake it in.** `usr/Makefile` (**INSPECTED**) shows that a single
  `CONFIG_INITRAMFS_SOURCE` ending `.cpio.*` is used **directly**, with
  `compress-y := copy` — *"avoid double compression"*. So pointing
  `CONFIG_INITRAMFS_SOURCE` at `arlo-initramfs-debian.cpio.gz` embeds **exactly the bytes
  whose SHA-256 we already have**: no recompression, no size ambiguity, and the
  `linux,initrd-*` window stops mattering. (A plain `.cpio` source is likewise used
  directly.)
  **INFERRED, NOT VERIFIED:** if the loader *also* passes `linux,initrd-*`, the external
  initrd is processed by the generic initrd path in addition to the embedded one
  (`init/initramfs.c:745 do_populate_rootfs()` unpacks the embedded set; the external
  region is freed afterwards at `:756`). To keep the baked initramfs authoritative,
  `a9boot` should simply not populate `linux,initrd-*`. Confirm before relying on it.
- **Or use the `min` variant** (997,191 B gz), which fits the existing window.

Both kernels' hashes are distinct and recorded above, so neither can be mistaken for the
other.

### DECISION (Lead, 2026-10-03): **no bake — hold as a fallback, not a plan**

Recorded so this is not re-litigated. **`Image` remains built with
`CONFIG_INITRAMFS_SOURCE=""` and no initramfs is baked into any artefact.**

The bake was offered and declined, and the reason is worth keeping: the size hazard this
section describes is **already retired at the loader**. `a9boot` computes
`linux,initrd-start`/`-end` from the byte count it actually staged, overwrites whatever
the template said (the template's 2,670,592-byte pair is now itself a hazard test in
their suite), and **refuses by name** with `HANDOFF_INITRD_SIZE_UNKNOWN` rather than
guessing. So baking would buy a **second** mechanism for a guarantee we already have —
and it would add an interaction: per the INFERRED caveat above, a baked kernel would
require a `a9boot` change to suppress `linux,initrd-*`, i.e. a change to a component that
is currently tested and frozen. **Two mechanisms, one of which needs a change to frozen
code, is the wrong trade.**

The bake becomes the right answer only if the loader's window handling fails on real
hardware — and at that point we will know why. If it is ever done: point
`CONFIG_INITRAMFS_SOURCE` at the `.cpio.gz`, pin the size to its hash, and record the
resulting `Image` hash here next to the other three.

---

## 2. Which VM holds the tree (HANDOFF §5 was ambiguous)

**MEASURED. It is the Podman machine — NOT the `Ubuntu-24.04` WSL distro.**

| | |
|---|---|
| Machine | `podman-main` — **Podman machine, WSL2-backed** |
| Image | `E:\podman-main\ext4.vhdx` |
| OS | Fedora Linux 44 (Container Image), kernel `6.18.40.1-microsoft-standard-WSL2` |
| Tree | `/build/linux-a9` on `/dev/sdd`, **1,007 G ext4** |
| HEAD | `6831bc701a6ce059e71e5aaa9488c9195bea6927` — **exactly the commit HANDOFF claims** |
| Branch | `hoolock` |
| Remote | `https://github.com/HoolockLinux/linux.git` |
| Work tree | clean (0 modified files) |
| CPU / RAM | 16 cores / 15.9 GiB |

**`Ubuntu-24.04` holds no kernel tree at all** — `ls /build` there returns
`No such file or directory`. Any future session looking for the tree should go
straight to `podman-main`.

### 2.1 One correction to HANDOFF §5: the toolchain is not on the VM host

**MEASURED.** The `podman-main` rootfs has **no toolchain whatsoever** — no
`clang`, `make`, `bc`, `flex`, `bison`, or `dtc`. HANDOFF §5 calls `/build/linux-a9`
a "Podman VM" tree and implies you build there directly; you cannot.

The real build environment is a **container**:

| | |
|---|---|
| Container | `a9build` (created 2026-10-03 11:44) |
| Image | `docker.io/library/debian:stable` → **Debian GNU/Linux 13 (trixie)** |
| Mount | `bind:/build → /build` |
| Command | `sleep infinity` (so `podman exec` works) |

The tree's own `.config` proves this was the environment used previously:
`CONFIG_CC_VERSION_TEXT="Debian clang version 19.1.7 (3+b1)"`. By contrast
`/build/config_16k` records `clang version 22.1.8 (Fedora 22.1.8-4.fc44)` — that
file was authored on a different, Fedora machine. **HANDOFF should be corrected**:
the toolchain is in the `a9build` container, not on the Fedora host.

---

## 3. Which config the shipped `Image` was built from ⚠️

**This matters, and it is not `config_16k`.** dt-engineer raised it; I verified it
independently (**MEASURED**).

| File | Bytes | SHA-256 | Role |
|---|---|---|---|
| `E:\…\a9linux\artefacts\config_16k` | 138,506 | `a5cbcb0d…06b208` | the **input** recipe |
| `/build/config_16k` | 138,506 | `a5cbcb0d…06b208` | same bytes |
| tree `.config.old` | 138,506 | `a5cbcb0d…06b208` | same bytes — **all three identical** |
| **tree `.config` (the build input)** | **138,789** | **`eaee02be…e1041`** | **what the `Image` was built from** |

The relationship is exactly reproducible (**MEASURED**):

```sh
cp /build/config_16k .config
make LLVM=1 ARCH=arm64 olddefconfig     # under clang 19.1.7
#  -> sha256 eaee02be48bf36516e0be7fbb678ed7034598a99bea4faddb5a01a053b8e1041
```

I ran that derivation and it produced a file **byte-identical** to the `.config`
already in the tree, so the pipeline is deterministic and was not hand-tuned.

**`config_16k` differs from the build input in 111 changed symbol lines**
(54 `<`, 57 `>`; 176 lines of `diff` output). Two causes, both benign:

1. **Toolchain version drift** — `config_16k` records Fedora clang 22.1.8, the build
   used Debian clang 19.1.7, so every `CONFIG_CC_HAS_*` / `CONFIG_CLANG_VERSION` /
   `CONFIG_LLD_VERSION` / `CONFIG_PAHOLE_VERSION` capability probe resolves differently.
2. **Upstream version drift** — `config_16k` is a **Linux 7.2.0** config
   (its own header says so); the `hoolock` tree is **7.3.0-rc1**. `olddefconfig`
   added defaults for the new symbols 7.3-rc1 introduced
   (`CONFIG_VDSO_DATASTORE`, `CONFIG_SWIOTLB_DEFAULT_SIZE_MB=64`,
   `CONFIG_HAS_SEPARATE_PREEMPT_RESCHED_BITS`, …).

**MEASURED: zero page-size, console or framebuffer symbols differ** between the two
files. I grepped the full diff for
`PAGE_SHIFT|PAGE_SIZE|ARM64_4K|ARM64_16K|ARM64_64K|SERIAL|SAMSUNG|CONSOLE|DRM_SIMPLEDRM|FB_SIMPLE|SYSFB|DRM_SYSFB|FRAMEBUFFER|EARLYCON`
— **no hits**. So the 16K proof and the console/framebuffer conclusions below hold
for both.

> **Read `config_16k` as the input recipe, never as a description of the build.**
> The authoritative record of what was built is
> `a9linux/artefacts/kernel/config.used`.

---

## 4. The 16K page-size proof (four independent layers)

A9 is a 16K-page part. A 4K kernel that links is a wasted device round trip, so this
is proven at four levels — config, generated header, **the artefact's own header**,
and the linked binary's layout.

### Layer 1 — the config (INSPECTED)

```
444:# CONFIG_ARM64_4K_PAGES is not set
445:CONFIG_ARM64_16K_PAGES=y
446:# CONFIG_ARM64_64K_PAGES is not set
763:CONFIG_PAGE_SIZE_16KB=y
```
Counts: `CONFIG_ARM64_16K_PAGES=y` → **1**; `CONFIG_ARM64_4K_PAGES=y` → **0**;
`CONFIG_ARM64_64K_PAGES=y` → **0**; `CONFIG_PAGE_SIZE_4KB` → **absent**.

### Layer 2 — the generated header the C code actually compiles against (MEASURED)

`include/generated/autoconf.h`:
```
15:#define CONFIG_ARM64_16K_PAGES 1
374:#define CONFIG_PAGE_SIZE_16KB 1
```

### Layer 3 — **the produced artefact's own Image header** (MEASURED) ✅

The arm64 `Image` begins with a 64-byte header. Decoded from the delivered file:

| Field | Value |
|---|---|
| `code0` | `0xfa405a4d` |
| `code1` | `0x143f5419` |
| `text_offset` | `0x0` |
| `image_size` | `0x1370000` = 20,381,696 |
| **`flags`** | **`0xc`** (`0b1100`) |
| `magic` | `0x644d5241` — `"ARM\x64"` ✅ |

The meaning of `flags` is **not recalled — it is read from this tree**:

`arch/arm64/include/asm/image.h`:
```c
#define ARM64_IMAGE_FLAG_BE_SHIFT          0
#define ARM64_IMAGE_FLAG_PAGE_SIZE_SHIFT   (ARM64_IMAGE_FLAG_BE_SHIFT + 1)   /* = 1 */
#define ARM64_IMAGE_FLAG_PHYS_BASE_SHIFT   (ARM64_IMAGE_FLAG_PAGE_SIZE_SHIFT + 2) /* = 3 */
#define ARM64_IMAGE_FLAG_PAGE_SIZE_4K      1
#define ARM64_IMAGE_FLAG_PAGE_SIZE_16K     2
#define ARM64_IMAGE_FLAG_PAGE_SIZE_64K     3
```
`arch/arm64/kernel/image.h`:
```c
#define __HEAD_FLAG_PAGE_SIZE  ((PAGE_SHIFT - 10) / 2)   /* 16K -> (14-10)/2 = 2 */
#define __HEAD_FLAG_PHYS_BASE  1
#define __HEAD_FLAGS  (__HEAD_FLAG(BE) | __HEAD_FLAG(PAGE_SIZE) | __HEAD_FLAG(PHYS_BASE))
```

Decoding `flags = 0xc` against those macros:

| Bits | Field | Value | Meaning |
|---|---|---|---|
| `[0:0]` | BE | `0` | little-endian ✅ |
| **`[2:1]`** | **PAGE_SIZE** | **`0b10` = 2** | **`ARM64_IMAGE_FLAG_PAGE_SIZE_16K`** ✅ |
| `[3:3]` | PHYS_BASE | `1` | `__HEAD_FLAG_PHYS_BASE` is a literal `1` in `image.h`, so this bit is always set and says nothing about this build |

Expected value computed *from the tree's macros* with `PAGE_SHIFT=14` (=16K):
`(0 << 0) | (2 << 1) | (1 << 3)` = **`0xc`** — **observed `0xc`. Exact match.**
For contrast: a 4K kernel would emit **`0xa`**, a 64K kernel **`0xe`**.
**`0xc` can only be a 16K little-endian arm64 kernel.**

`image_size` (20,381,696) > file size (19,755,520) by 626,176 bytes, which is
**expected and correct**: `image.h` defines `_kernel_size_le` as `_end - _text`,
and `.bss` is `NOBITS` so it is not present in the file.

### Layer 4 — page-table size baked into the linked binary (MEASURED) ✅

Independent of any header. `SWAPPER_DIR_SIZE` equals one page:

```
idmap_pg_dir     @ 0xffff800080fd8000   16K-aligned=YES
reserved_pg_dir  @ 0xffff800080fe0000   16K-aligned=YES
swapper_pg_dir   @ 0xffff800080fe4000   16K-aligned=YES
stride reserved_pg_dir -> swapper_pg_dir = 0x4000  (== 16K PAGE_SIZE)
_end             @ 0xffff800081370000   16K-aligned=YES
```

The three early page tables sit exactly `0x4000` apart and are all 16K-aligned. With
4K pages they would be `0x1000` apart. **The 16K page size is in the binary, not
just in the config.**

> ### ⚠️ If this kernel misbehaves somewhere, do **NOT** "fix" it by dropping the granule
>
> `qemu-validator` measured that QEMU's `a57`, `a53` and `a72` CPU models park in
> `__no_granule_support` with status `0x202`, because they cannot do 16K pages. The fix
> for that is **`-cpu max`** — **not** `CONFIG_ARM64_4K_PAGES`. Switching this kernel to
> a 4K granule would stop it testing the part we actually ship, cost a device attempt,
> and produce a wrong diagnosis. The QEMU-only test instrument `Image-16k-qemu-pl011`
> (§1.1) is deliberately left at 16K for exactly this reason.
>
> This note lives here, at the 16K proof, on purpose: it is aimed at whoever is about to
> conclude the kernel is broken.

### `Image.gz` integrity (MEASURED)

`gzip -dc Image.gz` is **byte-identical** to `Image` (19,755,520 bytes, `cmp` clean).

---

## 5. Exact build commands

The command is upstream's own documented one. `HoolockLinux/docs@master`
`tutorials/SETUP.md` step 5 says verbatim:

```
$ make -j$(nproc) LLVM=1 ARCH=arm64 Image.gz dtbs
```

That is exactly what was run — **no deviation, no extra flags**. (`LLVM=1` makes
kbuild use `clang`/`ld.lld`/`llvm-ar` rather than gcc/binutils, as HANDOFF §5 says.)
Upstream also states the example config "is fine already on A9–A11, T2 SoCs",
which is what sanctions `config_16k` for this board.

Full sequence, reproducible from a clean checkout:

```sh
# --- on the podman-main VM host ---
podman start a9build

# --- inside the a9build container (Debian 13), working in /build/linux-a9 ---
cd /build/linux-a9
cp /build/config_16k .config
make LLVM=1 ARCH=arm64 olddefconfig            # -> .config sha256 eaee02be…
make LLVM=1 ARCH=arm64 clean                   # discard a previous session's partial build
make -j"$(nproc)" LLVM=1 ARCH=arm64 Image.gz dtbs
```

The scripts that actually did this are shipped alongside the artefacts in
`a9linux/artefacts/kernel/scripts/` — `20-configure.sh`, `50-cleanrebuild.sh`,
`40-verify-image.sh`, `60-copyout.sh`, and the diagnostics.

### 5.1 Where it was built — the §9.3 rule was honoured (MEASURED)

```
/dev/sdd       ext4 1055762868 29443720 972615676   3% /
```

**`ext4`, not 9p/drvfs.** The tree lives on the VM's own ext4 root; nothing was
built over `/mnt/*`. Only *finished* artefacts were copied out to `E:`.

The scripts were staged by copying them to `/build/a9scripts/` (ext4) and executing
them from there, never from `/mnt/e`. Reading `initramfs.gz` off `E:` into
`/build/inputs/` before inspecting it kept the same rule (§7.5).

---

## 6. Build result

| | Clean build (delivered) | Incremental (discarded) |
|---|---|---|
| `EXIT` | **0** | 0 |
| Wall time | **428 s** (~7 min) | 210 s |
| `CC` invocations | **2,057** | 957 |
| `LD` invocations | 9 | 4 |
| Warnings | **0** | 0 |
| Errors | **0** | 0 |
| Log lines | 3,011 | 1,496 |

**Why a clean rebuild was done (MEASURED).** The tree arrived holding **1,321 `.o`
files** from a previous session — consistent with HANDOFF §7 blocker 5, "`Image.gz`
never built". The first build completed in 210 s having run only 957 `CC`
invocations, i.e. it had *reused* roughly 1,100 objects. kbuild's `.cmd` dependency
tracking makes that safe in principle, and in fact the two builds proved
structurally identical (§1) — but "kbuild is probably right" is an inference, and
this project's recurring injury is shipping an inference to the device. `make clean`
+ full rebuild converts it into a measurement: **the delivered `Image` comes from a
single coherent compile of exactly one config.**

**`CONFIG_WERROR` is not set**, so a warning could not have aborted the build; the
zero warning count is a real observation, not a consequence of suppression.

### 6.1 Toolchain as resolved (MEASURED)

| Tool | Version |
|---|---|
| `clang` | Debian clang version **19.1.7** (`3+b1`) |
| `ld.lld` | Debian LLD **19.1.7** (compatible with GNU linkers) |
| `llvm-ar` | Debian LLVM version **19.1.7** |
| `llvm-nm` | llvm-nm, compatible with GNU nm |
| `make` | GNU Make **4.4.1** |
| `dtc` | **DTC 1.7.2** |
| `gcc` (host cc for kbuild tools) | Debian 14.2.0-19 |
| `python3` | 3.13.5 · `flex` 2.6.4 · `bison` 3.8.2 · `bc` 1.07.1 · `gzip` 1.13 |
| Container | Debian GNU/Linux 13 (trixie), hostname `9ccdc4284c73`, 16 cores |

Tools that are **absent** and **not needed** (recorded so nobody hunts for them —
their absence is explained by the config, not a gap):

| Absent | Why it is fine |
|---|---|
| `pahole` | `CONFIG_DEBUG_INFO_BTF` is not in `.config` at all → no BTF generation |
| `rustc` | `CONFIG_RUST` is not in `.config` at all → no Rust code |
| `lz4` | `CONFIG_KERNEL_GZIP=y` → the compressed target is gzip, not lz4 |
| `git` | kbuild does not need it; git operations ran on the VM host |

### 6.2 The DTB is byte-reproducible (MEASURED)

`s8003-n69.dtb` was **regenerated** by `make dtbs` during the clean build (mtime
moved to 12:26) and its SHA-256 is **unchanged** at
`cbb79a148fec1377b7187a4c9514a968e519f3c2ee796818d41f08fde1dc1dfc` — the same value
observed before any build ran. The shipped DTB is therefore demonstrably the product
of this source revision.

**Caveat (MEASURED):** the `Image` is **not** bit-reproducible — it embeds a build
timestamp (`#2 … Sat Oct 3 10:33:02 UTC 2026`) and the build hostname. Only the DTB
is stable across rebuilds. Verify the `Image` by hash; verify the *source* by the
pinned config and commit.

---

## 7. What would stop this kernel booting on A9 — **the unsoftened list**

Everything here is **MEASURED from the built `s8003-n69.dtb`** (decoded with `dtc`),
not from source comments. Items 1–4 are HANDOFF §8.11's "loader specification",
now confirmed present in the compiled artefact.

### 7.1 🔴 `/memory` declares **zero usable RAM** — hard blocker

```
memory@800000000 {
    device_type = "memory";
    reg = <0x08 0x00 0x00 0x00>;
};
```
With `#address-cells=2, #size-cells=2` this is base `0x8_0000_0000`, **size 0**.
The kernel will find no RAM and cannot boot. **The loader must rewrite this node
with the real bank.** This is the single hardest requirement on `a9boot`.

### 7.2 🔴 No `/chosen/bootargs` — the kernel gets an **empty command line**

There is no `bootargs` property, and `CONFIG_CMDLINE=""`, so unless the loader
injects `/chosen/bootargs` the kernel receives nothing: no `console=`, no
`earlycon`, no `root=`.

Not as bad as it looks: `/chosen/stdout-path = "serial0"` **is** present and Linux
honours it as the default console, and `serial@20a0c0000` is `status = "okay"`. So
console output should work — but there will be **no `earlycon`** (you get nothing
until the real driver probes, which makes early faults invisible) and no root device.

### 7.3 🔴 `cpu-release-addr = <0x00 0x00>` with `enable-method = "spin-table"`

Both CPU nodes have a **zero** release address. Linux's `smp_spin_table_cpu_init`
(`arch/arm64/kernel/smp_spin_table.c:55`) reads `cpu-release-addr` and, on failure,
errors; with a valid-but-zero address the secondary cannot be released. **Expect
single-CPU boot at best; SMP will not work until the loader fills this in.**

**Sharpened by an off-device measurement (qemu-validator, via QEMU monitor):** the
kernel's *own* side of this contract works. Given a `cpu-release-addr` that our DT names,
the kernel writes `0x426d4348` (`secondary_holding_pen`) into it — verified by reading the
address through QEMU's monitor. So the kernel behaves correctly when handed a valid
address, and the blocker is **purely** "the loader must supply one" — not a kernel defect.

**Caveat, stated so this is not over-read:** CPU1 never actually comes online in any QEMU
run, because QEMU keeps secondaries powered off and only PSCI releases them. So the
`spin-table` release path itself remains **unexercised**. What is proven is the write; what
is not proven is that A9's second core leaves the holding pen when it sees that write. That
still needs hardware.

### 7.4 🟠 `/chosen/framebuffer@0` is `disabled` and empty — no screen yet

```
framebuffer@0 {
    compatible = "apple,simple-framebuffer", "simple-framebuffer";
    reg = <0x00 0x00 0x00 0x00>;
    status = "disabled";
    power-domains = <0x19 0x28>;
};
```
Three things are missing: `status = "okay"`, a real `reg` (base/size), and the
`width` / `height` / `stride` / `format` properties. `drivers/of/platform.c:581`
creates the platform device from `/chosen`, but `of_platform_device_create()`
skips unavailable nodes, so **`status = "disabled"` alone is enough to yield no
framebuffer.** The loader must enable *and* populate it.

**The good news, and it is genuinely good (INSPECTED):** this kernel *can* drive it.
`drivers/gpu/drm/sysfb/simpledrm.c:953` has
`of_device_id simpledrm_of_match_table[] = { { .compatible = "simple-framebuffer" } }`
and is enabled (`CONFIG_DRM_SIMPLEDRM=y`, `CONFIG_DRM_SYSFB_HELPER=y`). So the
"Linux on the screen" rung needs **no A9 display-pipe driver** — only a
loader-populated framebuffer node. HANDOFF §4's "plausible, unphotographed" is
correct as far as the kernel is concerned.

### 7.5 🟠 `CONFIG_INITRAMFS_SOURCE=""` — the kernel carries **no userland**

The delivered `Image` has no built-in initramfs and there is no `root=`, so it will
panic at the end of init with no root device. Something must supply an initrd:
either `a9boot` passes one, or the kernel is rebuilt with it baked in.

**MEASURED — a usable initramfs already exists** at
`a9linux/artefacts/initramfs.gz` (2,669,875 B, sha256
`5381e470b0c2cf821e6d9ebeaa5b1c4ab2409b7adc4862502915247d76bd7876`). It is a real
gzip'd `newc` cpio (`initramfs.cpio`, 3,380,224 B uncompressed, 16 members)
containing `/init` (mode 0755), `bin/busybox` (aarch64, 919,296 B),
`lib/ld-musl-aarch64.so.1`, `init_functions.sh`, and `extract.cpio.lzma`. Upstream
documentation for this image says it spawns a shell on the serial console. So there
**is** a real path to observing a boot — see the recommendation in §9.

### 7.6 🟢 `Image.gz` needs the loader to gunzip — **so ship `Image`**

`Documentation/arch/arm64/booting.rst`: *"The AArch64 kernel does not currently
provide a decompressor and therefore requires decompression (gzip etc.) to be
performed by the boot loader if a compressed Image target (e.g. Image.gz) is used."*
There is no self-decompressing stub. **Both artefacts are shipped**, and `Image`
(19,755,520 B, uncompressed) is the one that removes an entire piece of gunzip
work from `a9boot`.

### 7.7 🟠 No loadable modules

`make Image.gz dtbs` builds the kernel only — **no modules**, and
`CONFIG_MODULES=y` means the config *expects* some. Anything not built in is simply
absent at runtime. For a RAM-backed bring-up this is mostly fine, but there is
nothing loadable later without a further build.

### 7.8 🟡 `CONFIG_ARM64_VA_BITS=48` / `PA_BITS=48` — inherited, not independently verified

Both come from `config_16k` unchanged. **INSPECTED:** with the 16K granule the
Kconfig choice offers 36, 47 and 48 bits, so 48 is legal and `ARM64_VA_BITS_48` has
no `depends on` clause. **INFERRED, NOT VERIFIED:** I did not confirm that A9's MMU
accepts a 48-bit VA with a 16K granule. `PA_BITS=48` is the Kconfig default and is
needed anyway (RAM sits at `0x8_0000_0000`, i.e. bit 35).

If the kernel faults very early in `__create_page_tables`/MMU enable with no
console output, **`CONFIG_ARM64_VA_BITS_36` is the first thing to change** — it is
the other 16K-granule option. Recorded as a suspect, not as a known problem.

### 7.9 🟢 Verified NOT blockers (checked, because they looked like ones)

| Concern | Finding | Evidence |
|---|---|---|
| Console / UART | **Fine.** `serial@20a0c0000` is `compatible = "apple,s5l-uart"`, handled by the Samsung-derived driver | `CONFIG_SERIAL_SAMSUNG=y`, `CONFIG_SERIAL_SAMSUNG_CONSOLE=y`, `drivers/tty/serial/samsung_tty.c:2640` (`.compatible = "apple,s5l-uart"`), `OF_EARLYCON_DECLARE(s5l, "apple,s5l-uart", …)` at `:2851` |
| Framebuffer driver | **Fine.** simpledrm matches the DT node | `drivers/gpu/drm/sysfb/simpledrm.c:953-962`; device created at `drivers/of/platform.c:581` |
| Board support | **Present.** `ARCH_APPLE=y`; the DTB is a first-class build target | `arch/arm64/boot/dts/apple/Makefile:29` → `dtb-$(CONFIG_ARCH_APPLE) += s8003-n69.dtb` |
| Timers / interrupt controller | **Present.** `arm,armv8-timer` and AIC (`interrupt-controller@20e100000`) in the DTB | `CONFIG_ARM_ARCH_TIMER=y`, `CONFIG_APPLE_AIC=y` (selected by `ARCH_APPLE`) |

**Context, stated plainly:** `ARCH_APPLE`'s own help text says *"such as the Apple
M1"*. This port is M1-centric and A9 is bring-up-level, exactly as HANDOFF §4 says.
The kernel side is ready; the loader side (§7.1–7.5) is the remaining work.

---

## 8. Changes made to the VM (for the next person)

| Change | Detail |
|---|---|
| Container started | `podman start a9build` (was `Exited (0)`) — left running |
| `.config` rewritten | identical bytes to what was already there, so kbuild state stayed valid |
| `make clean` run | removed a previous session's 1,321-object partial build |
| Written to `/build/a9scripts/` | the build/verify scripts, staged on ext4 |
| Written to `/build/inputs/` | a copy of `initramfs.gz` for inspection |
| Written to `/build/kb-incremental/` | the discarded incremental build, kept for the cross-check in §1 |
| Logs | `/build/kbuild.log`, `/build/kbuild-incremental.log`, `/build/kbuild-clean.log` |

**Nothing under `/mnt/*` was built in. Nothing was written to `D:`. The iPhone was
never touched** — no `a9pwn`, no `a9drv`, no `irecovery`, no USB access. The only
hardware interaction was starting/stopping VM and container, which the task allows.

---

## 9. Recommended next steps (in order)

1. ~~Decide how the initramfs reaches the kernel.~~ **DECIDED — see §1.2.** The loader
   sizes `linux,initrd-*` from what it actually staged and fails loudly
   (`HANDOFF_INITRD_SIZE_UNKNOWN`), so the kernel is **not** modified: `Image` stays at
   `CONFIG_INITRAMFS_SOURCE=""`. The bake is **held as a fallback**, to be used only if
   the loader's window handling fails on real hardware. Do not re-open this by reflex;
   read §1.2 for why two mechanisms was judged the worse trade.
   The distinction still matters for §7.5: "boots and we see a shell" vs "boots and we
   see nothing" is a real risk, and it is now the **loader's** risk to carry.
2. **`a9boot` must satisfy §7.1–7.4**: real `/memory`, `/chosen/bootargs`,
   `cpu-release-addr`, and an enabled+populated framebuffer node. That list *is* the
   loader's specification (HANDOFF §8.11) and is now confirmed in the binary DTB.
3. **Load the plain `Image`, not `Image.gz`** (§7.6) to avoid implementing gunzip.
4. If nothing appears on the serial console at all, revisit `CONFIG_ARM64_VA_BITS`
   (§7.8) before suspecting the exploit or the loader.
5. **Correct HANDOFF §5**: the tree/build live in the Podman machine's `a9build`
   Debian container, not on the Fedora host, and `Ubuntu-24.04` has no tree.

---

## 10. Errors caught in this session — recorded, not hidden

Both of these were in **my** tooling, and both were caught by checking source
instead of trusting a recalled constant. They are written down because the next
person will hit the same traps.

### 10.1 My Image-flags decode table was wrong (caught before reporting)

My first verification script decoded the page-size field with the table
`{0:4K, 1:16K, 2:64K}` and therefore printed **"FAIL — NOT 16K"** for a kernel that
is a correct 16K build. The real field value is `(PAGE_SHIFT - 10) / 2`, so
`1 = 4K, 2 = 16K, 3 = 64K` (`arch/arm64/kernel/image.h:50`,
`arch/arm64/include/asm/image.h`). `flags = 0xc` is **right**; the table was wrong.

The same script also wrongly asserted that `image_size > file_size` was
"INCONSISTENT"; that relationship is correct and expected, because `.bss` is
`NOBITS`. The corrected script now **derives** the expected flags from the tree's
macros rather than hardcoding them, and adds an independent check that does not
involve the header at all: the 16K stride of the early page tables in the linked
binary (§4, Layer 4).

**Lesson: near-miss averted by reading the definition, exactly as HANDOFF §9.4
requires.** Had I reported the first output, this project would have discarded a
correct kernel — the same class of error as the seven already paid for, in the
opposite direction.

### 10.2 `CONFIG_SERIAL_APPLE` does not exist in this tree (dt-engineer / Lead)

An early revision of `scripts/15-bootcheck.sh` grepped for `CONFIG_SERIAL_APPLE`,
`CONFIG_SERIAL_8250_APPLE` and `CONFIG_DRM_SIMPLE`. **None of those symbols exist**,
so the check printed empty strings and could have produced a confident false
"no console support". The real symbols are `CONFIG_SERIAL_SAMSUNG` /
`CONFIG_SERIAL_SAMSUNG_CONSOLE` and `CONFIG_DRM_SIMPLEDRM` (§7.9).

I had in fact discovered this mid-session and recorded it in my report to the Lead,
but **I left the broken symbol list in the shipped script** — a real defect, caught
by dt-engineer reviewing the tree. `15-bootcheck.sh` is now corrected and no longer
prints a bare empty string: it distinguishes
`=y` / `is not set` / **`SYMBOL DOES NOT EXIST in this tree`** / `exists in Kconfig
but dependency unmet`. `scripts/16-verify-symbols.sh` is the cross-check script that
found the trap and is kept as-is.

**Lesson: a wrong check in a *verification script* is worse than a wrong check in a
build, because it manufactures false confidence later.** Fixing the report is not
enough — the tool has to be fixed too.

---

## 11. Reproducing / verifying this build

All scripts are in `a9linux/artefacts/kernel/scripts/`, numbered in execution order.

| Script | Purpose |
|---|---|
| `10-inspect-dtb.sh` | decode the DTB; report `/memory`, `/chosen`, cpus, framebuffer |
| `15-bootcheck.sh` | boot-readiness audit with **correct** symbol names (§10.2) |
| `16-verify-symbols.sh` | cross-check claimed symbols against the tree's Kconfig |
| `17-console-fb.sh` | console + framebuffer binding audit |
| `20-configure.sh` | derive `.config` from `config_16k`; prove 16K survived |
| `25-configdiff.sh` | exact `config_16k` → `.config` diff; prove no boot-relevant change |
| `30-build.sh` | first (incremental) build, detached |
| `35-wait.sh` / `55-waitclean.sh` / `90-status.sh` | waiters / poll helper |
| `40-verify-image.sh` | **final artefact verification** — header, layout, hashes, warnings |
| `41-flags-truth.sh` | read the authoritative flags definition out of the tree |
| `42-imageflags.sh` | the `ARM64_IMAGE_FLAG_*` constants |
| `45-toolchain.sh` | resolved toolchain versions |
| `50-cleanrebuild.sh` | `make clean` + full rebuild, with the incremental cross-check |
| `60-copyout.sh` | copy artefacts out to `E:` and verify hashes across the copy |
| `70-initramfs.sh` | inspect the bundled initramfs |
| `75-qemu-pl011-preflight.sh` | is PL011 already on? what would the delta pull in? |
| `76-initramfs-semantics.sh` | can a `.cpio.gz` be baked in? how does it interact with an external initrd? |
| `80-clone-for-qemu.sh` | pristine clone at the same commit, so the device kernel cannot be contaminated |
| `81-qemu-pl011-build.sh` | build the QEMU-only instrument; assert the base config hash first |
| `82-verify-qemu-pl011.sh` | exact delta, 16K preserved, header, shipping tree untouched |
| `85-wait-qemu.sh` | waiter for the variant build |
| `86-copyout-qemu.sh` | copy the variant out under an unambiguous name; check all three hashes differ |
| `83-pl011-ab-check.sh` | A/B the PL011 symbols across the two kernels (System.map) |
| `84-pl011-reconcile.sh` | reconcile the `System.map` vs `strings` counts so `62` vs `20` is not mistaken for a disagreement |
| `87-copyout-sysmap.sh` | copy both `System.map` files out so the A/B is citable from `E:` alone |
| `88-verify-artefact-pairing.ps1` | **Windows-only, no VM needed** — prove each `System.map` belongs to its `Image`; self-tests all four pairings every run |
| `89-syntax-check.sh` | `bash -n` + CRLF + shebang hygiene pass over the shipped scripts |
| `95-finalcheck.sh` | stage every shipped script from `E:` and re-run the verification end-to-end |

### Guarding the `Image` ↔ `System.map` pairing (added after handover)

`qemu-validator`'s `resolve-pc.sh` resolves crash PCs against the maps shipped here, which
created a dependency with **no guard**: a stale map would silently mis-resolve every symbol
into a confident wrong answer. `88-verify-artefact-pairing.ps1` closes it, runnable from
Windows with no VM:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& E:\Reverseing\Arlo\a9linux\artefacts\kernel\scripts\88-verify-artefact-pairing.ps1
```

It tests the structural link in `arch/arm64/kernel/image.h`
(`_kernel_size_le = _end - _text`), so `image_size` in the `Image` header must equal
`_end - _text` in its map — for the device kernel that is `0x1370000` on both sides.

**A limit found by reading the actual numbers instead of assuming.** Both kernels report
`_end - _text = 0x1370000`, because `image_size` is **page-granular** and the added PL011
driver fits inside the existing rounded footprint. So the footprint rule is a **necessary**
condition, not a sufficient one — a stale map from a sibling build passes it. The check
therefore adds a second rule: **the map's `pl011` symbol count must agree with the `Image`'s
own `pl011` literal count** (0/0 for the device kernel, 62/20 for the instrument).

**Rule 2 is *derived from the artefacts*, not from a table typed into the script.**
`qemu-validator`'s version cross-checks the map against the Image's own contents, and their
reasoning was better than my first attempt, which compared against a hardcoded profile: *a
typed table is the thing that rots, and a typo in it would silently disable the guard.*
Their design is adopted. It also catches a case mine could not — a map that is internally
consistent but comes from a third build.

**Proven to have teeth — and the proof now runs every time.** The mis-pairings are
evaluated **on every invocation**, not by a separate hand-run control. An earlier version
only demonstrated the failure mode via a temp-directory exercise, and `qemu-validator`
objected, correctly: *a check whose failure is only ever shown by hand tends to stop being
shown*. The header field and the map fields are read independently, so all four
combinations can be evaluated with no file copying. Actual output:

```
  IMAGE                  MAP                    RULE 1   RULE 2   VERDICT
  Image                  System.map             PASS     PASS     CORRECT PAIR (accepted)
  Image                  System.map-qemu-pl011  PASS     FAIL     mis-pair correctly rejected
  Image-16k-qemu-pl011   System.map             PASS     FAIL     mis-pair correctly rejected
  Image-16k-qemu-pl011   System.map-qemu-pl011  PASS     PASS     CORRECT PAIR (accepted)
```

Both mis-pairings **pass** the footprint rule and are caught only by the discriminator.
That is the whole argument for having both rules, and it is now visible on one screen
rather than in a prose warning.

**Third-party negative control.** `qemu-validator` tested the "cannot rot" claim rather
than accepting it: they built a scratch directory whose two pairs have their **contents
swapped** (`Image` holding the variant binary and vice versa) and ran this script through
its own `-Dir` parameter. Result — both mis-pairs accepted by rule 1, both rejected by
rule 2, `RESULT: FAIL (4 problems)`, `GUARD_EXIT=4`. Teeth confirmed independently.

### ⚠️ The residual limit of rules 1+2, and the pinning that closes it

**Rule 2 is two-valued** — `pl011` present or absent. It separates *these two builds* and
nothing more. `qemu-validator` named the consequence and were right to insist it be written
down rather than implied: a **stale map from an earlier *device*-kernel revision** also has
zero `pl011` symbols, so it passes rule 2; and it passes rule 1 whenever the page-rounded
`image_size` happens to match. **Rules 1+2 cannot catch that case.**

They could not construct it from the artefacts available, so they recorded it as a limit. It
**is** constructible, and I demonstrated it rather than leaving it as a caveat: append a
single comment line to a copy of the device map (changing nothing that rules 1+2 read):

```
  Image                  System.map             PASS     PASS     CORRECT PAIR (accepted)
  Image                  System.map-qemu-pl011  PASS     FAIL     mis-pair correctly rejected
  Image-16k-qemu-pl011   System.map             PASS     FAIL     mis-pair correctly rejected
  Image-16k-qemu-pl011   System.map-qemu-pl011  PASS     PASS     CORRECT PAIR (accepted)
  System.map               *** CHANGED ***
RESULT: FAIL (1 problem(s))
```

**All four combinations stayed green on a modified map.** Rules 1+2 are structurally blind
to it. What catches it is **hash pinning**: the script records the SHA-256 of all four
artefacts and fails if any moves. A stale map has a different hash, full stop. So the guard
now has **two independent verdicts and both must pass**:

- **(A) pairing** — rules 1+2 across all four combinations → catches **swaps**.
- **(B) pinning** — every artefact hash matches the recorded pin → catches **staleness**.

The cost of (B) is that a deliberate regeneration must be re-pinned by hand — which is the
correct workflow, because re-pinning is precisely the moment someone re-decides that the new
pair is the pair to cite.

**So "the guard cannot rot silently" is now earned, but only because of (B), not because of
rules 1+2.** Correctly stated: **(A) is sufficient for the artefact set we cite, not in
general.** If these maps are ever regenerated, the safety comes from re-running this check
against the *new* pair, not from it having passed once.

### (C) Doc agreement — the pins must not live in two places unguarded

**(B) introduced a fresh instance of the very fault this guard exists to catch, one level
up.** The same four hashes now existed in two places — `$pins` in the script and the §1 table
in this document — with nothing detecting a disagreement between them. `qemu-validator` found
exactly this drift in their own fix, and their formulation is the right one: *if the README
and the enforcement can disagree, the README is decoration.* The defect existed here too, by
the same cause, introduced minutes earlier.

So the guard has a third verdict: **every pin in the script must also appear in this document,
next to the artefact name.** The script is the source of truth; editing either side alone
fails the check.

```
  Image                    ok pin 39a270676141f425... present in BUILD-LOG.md
  Image-16k-qemu-pl011     ok pin 2697e77d901d4484... present in BUILD-LOG.md
  System.map               ok pin 821a3f3aee0b2cc2... present in BUILD-LOG.md
  System.map-qemu-pl011    ok pin 07408377308361cb... present in BUILD-LOG.md
```

**Shown to fail**, by corrupting one hash in a *copy* of this document and nothing else:

```
  System.map               *** DOC DISAGREES ***
      script pin: 821a3f3aee0b2cc23ea3f11a4ac927bb8c78f148e8a597e86d3ef33b4e57e64c
      doc says  : 0000000000000000000000000000000000000000000000000000000000000000
RESULT: FAIL (1 problem(s))
```

**Three verdicts, each demonstrated to fail, all three must pass:**

| | verdict | catches | how it was shown to fail |
|---|---|---|---|
| **(A)** | pairing | swaps within this set | `qemu-validator`'s swapped-content scratch dir, `GUARD_EXIT=4`, plus the built-in four-combination table |
| **(B)** | pinning | staleness — any artefact change | modified map copy → `*** CHANGED ***`, exit 1 |
| **(C)** | doc agreement | document drifting from enforcement | corrupted hash in a doc copy → `*** DOC DISAGREES ***`, exit 1 |

The pattern in that table is the point: **(A) had already been negative-controlled for swaps
and still missed staleness**, because "shown to fail" only ever covered the failure mode I had
in mind. Each verdict here exists because a *different* question was asked of the same
artefacts — and each was made to fail before it was trusted.

Had I stopped at the footprint rule I would have shipped a guard that green-lights exactly
the failure it exists to prevent — the same shape of error as §10.1 and the `arlo:/#` grep
case `qemu-validator` recorded in their README §6.9. **The generalisable rule: a check
earns trust by having been shown to fail.** Four times in this task a check returned a
confident answer while measuring the wrong thing; in every case the missing step was a
negative control, not care.

### Script hygiene pass (`89-syntax-check.sh`)

`qemu-validator` built a `selfcheck.sh` after breaking one of their own scripts with an
in-place edit. Same exposure here, so the same pass was run over the 29 shipped scripts:

```
shell scripts: 29   python: 0   problems: 0
RESULT: PASS -- every shell script parses, is LF-only, and has a shebang.
```

It checks `bash -n` per file, **CRLF per file**, and shebang presence. The CRLF check is
not paranoia: this session repeatedly had CRLF injected when a script was staged through a
PowerShell pipe (`cat > file`), which is what produced the mysterious
`sed: extra characters after command` and `tail: invalid number of lines` errors early on.
A `.sh` with CRLF can pass `bash -n` and still fail at runtime. All 29 delivered scripts are
clean, confirming the corruption was confined to ad-hoc pipes and never reached a shipped
file. The `88-…ps1` PowerShell guard is checked on Windows instead (it is deliberately not
a shell script, so it also runs without a VM).

Quick re-verification of the delivered artefacts, from Windows:

```powershell
Get-FileHash E:\Reverseing\Arlo\a9linux\artefacts\kernel\Image                -Algorithm SHA256
Get-FileHash E:\Reverseing\Arlo\a9linux\artefacts\kernel\Image.gz             -Algorithm SHA256
Get-FileHash E:\Reverseing\Arlo\a9linux\artefacts\kernel\Image-16k-qemu-pl011 -Algorithm SHA256
Get-FileHash E:\Reverseing\Arlo\a9linux\artefacts\kernel\s8003-n69.dtb        -Algorithm SHA256
```
```sh
# re-run the full provenance chain inside the container:
cp /mnt/e/Reverseing/Arlo/a9linux/artefacts/kernel/scripts/*.sh /build/a9scripts/
podman exec a9build bash /build/a9scripts/40-verify-image.sh   # device kernel
podman exec a9build bash /build/a9scripts/82-verify-qemu-pl011.sh  # QEMU instrument
```

### QEMU variant: what to hand the harness

The harness wants the **uncompressed** `Image-16k-qemu-pl011` (QEMU does not gunzip), and
needs **`-cpu max`** so the 16K granule is usable (§1.1). `console=ttyAMA0` and
`earlycon=pl011,0x9000000` both now have a driver behind them. This artefact exists
solely so a silent run can be told apart from a stuck one — **never write it to the
iPhone.**
