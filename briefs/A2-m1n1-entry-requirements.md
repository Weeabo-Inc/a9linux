# Task: entry requirements and load address of the m1n1 bootloader on an Apple A9 SoC

I am writing **host-side tooling in Rust on Windows** that packages and loads boot images for
embedded ARM64 boards. I need a precise, source-cited answer to a bring-up design question. Please
do not write code — I want the analysis.

## The component

**m1n1** — `github.com/HoolockLinux/m1n1`, derived from `AsahiLinux/m1n1`. It is a small aarch64
bare-metal payload: it initialises the SoC, fills in placeholders in a device tree, and branches to a
Linux kernel. It is used to bring Linux up on Apple Silicon and Apple mobile SoCs.

## The tree on disk

`<REPO_ROOT>\a9linux\src\m1n1\` — fork `HoolockLinux/m1n1`, commit `d5a10ac`. Files that
matter: `src/main.c`, `src/adt.c`, `src/xnuboot.h`, `src/payload.c`, `src/chainload.c`,
`src/devicetree.c`, `src/soc.h`, `m1n1.ld`, `m1n1-raw.ld`, `Makefile`.

## The target SoC

Apple **A9**, SoC variant `s8003`, board `n69ap` (the 2016 iPhone SE: 2 GB RAM, 640x1136 panel).
m1n1 supports it — `src/soc.h` defines `S8000 0x8000` and `S8003 0x8003`, `src/smp.c:286-293`
handles its SMP bring-up, `src/cpufreq.c` has matching cases, and `src/chickens/twister.c` has its
CPU errata workaround.

## Background on how it is normally started

The project's own documentation describes two supported ways to start m1n1:
(a) from `pongoOS`, using `m1n1.bin`; or (b) from `iBoot`, using `m1n1-idevice.macho` and sometimes
`monitor-stub.macho`. Both are large pre-existing components that hand m1n1 a prepared environment.

I would like to start m1n1 from a **minimal loader of my own** instead, so that the boot chain is
just: small loader → m1n1 → Linux. This is a bring-up simplification, not a modification of m1n1.

## Questions

1. **Entry requirements.** Trace from m1n1's entry point. Which structure does it expect to find, at
   which address or register? Name the struct (the `boot_args` / `xnuboot` lineage) and separate the
   fields it genuinely dereferences from those it ignores. Cite each read.

2. **Does it require an Apple Device Tree (ADT)?** `src/adt.c` walks an `IODeviceTree` property tree
   that a previous stage normally supplies. Determine what happens when no ADT is present: which
   subsystems fail, which still work from compile-time constants (note `src/soc.h` defines an early
   UART base for S8000/S8003 at compile time), and whether m1n1 can still reach the point of handing
   a **supplied** device tree to a Linux kernel. This is the crux of my question.

3. **Load address and relocatability.** What address is `m1n1.bin` linked to run at? Check
   `m1n1.ld` and `m1n1-raw.ld` and the `Makefile`. Is the resulting code position-independent
   (`ADR`-relative / `-fPIC`), or does it assume it was placed at its link address? If a loader must
   place it at a fixed address, say which address and where the number comes from.

4. **The minimum shim.** If m1n1 cannot run with nothing in front of it, specify the *smallest
   possible* thing that would satisfy it — for example a stub that constructs a minimal boot-args
   structure and a minimal device tree in memory, then branches to m1n1. Describe the minimum
   contents required for this SoC. I want to know how small "small" is, in bytes and in concepts.

5. **The appended payload container.** The documented way to build a boot image is:
   `cat m1n1.bin <(echo 'chosen.bootargs=<cmdline>') dtb Image.gz initramfs.gz > m1n1-linux.bin`.
   Find the parser for this. What is the container format — magic value(s), header layout, alignment
   or padding rules, how each payload's type is identified, and how the end of the list is detected?
   Is the `chosen.bootargs=...` line a raw ASCII append or a framed item, and does it need a trailing
   newline or NUL? Give `file:line`.

6. **Device tree patching.** Which code fills in the placeholders in a supplied DTB before branching
   to Linux — specifically the `memory` node's `reg`, the `framebuffer0` node's `reg` and `status`,
   and the CPU `cpu-release-addr`? The DTS for this board marks all three `/* To be filled by
   loader */`. Trace the writes in call order.

## Output

Numbered answers, each citing `file:line`, plus URLs where you go upstream. The single most valuable
thing you can tell me is a clear answer to **3 and 4**: can `m1n1.bin` be placed at its link address
by a minimal loader and branched to, or does it structurally require something larger in front of it?
If it requires more, say so plainly and explain why in one paragraph. Mark inference as inference,
and say explicitly where you could not determine something from the source.
