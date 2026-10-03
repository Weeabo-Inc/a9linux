# Task: can a bootloader be started directly from a bootrom that accepts unsigned images, and what does it need?

I am building **host tooling in Rust for Windows** to put a Linux bootloader onto an Apple A9 phone.
I need a precise, source-cited answer to a design question. Please do not write code — I need the
analysis.

## The situation

- Device: iPhone SE 1st generation — Apple A9, SoC variant **s8003**, chip id `0x8003`, board `n69ap`,
  panel 640x1136, 2 GB RAM.
- It is attached in **DFU mode** on USB `VID_05AC / PID_1227`.
- **A separate, already-completed step has put the bootrom into the state where it accepts unsigned
  images.** That step works and is entirely out of scope — treat it as a given precondition, like
  "the cable is plugged in". Nothing about it needs to be designed, described, or revisited here.
- The goal is deliberately minimal: get **plain mainline Linux and a Debian userland** running on the
  device. I do **not** want an intermediate pre-boot environment in the chain. The established
  tooling for this hardware routes through one (`pongoOS`), and I am trying to remove it.

## The bootloader

**m1n1** — `github.com/HoolockLinux/m1n1`, and the AsahiLinux/m1n1 it derives from. It is a small
aarch64 bare-metal payload that sets up the SoC, patches a device tree for the kernel, and jumps to
Linux. Its build produces `m1n1.bin` (a flat binary, 1,196,032 bytes in the CI artifact) and
`m1n1-idevice.macho`.

The documented ways to start it are: (a) via `pongoOS`, using `m1n1.bin`; or (b) via `iBoot`, using
`m1n1-idevice.macho` and sometimes `monitor-stub.macho`. I want neither. I want to load `m1n1.bin`
into a bootrom that accepts unsigned images and jump to it.

## The source

I have the tree on disk at `<REPO_ROOT>\a9linux\src\m1n1\` (fork `HoolockLinux/m1n1`, commit
`d5a10ac`). Key files: `src/main.c`, `src/adt.c`, `src/xnuboot.h`, `src/payload.c`,
`src/chainload.c`, `src/devicetree.c`, `src/soc.h`, `m1n1.ld`, `m1n1-raw.ld`, `Makefile`.

## Questions

1. **What does m1n1 read at entry?** Trace from its entry point: which structure does it expect to
   find, at which address or register, and which fields does it actually dereference? Name the struct
   (the `boot_args` / `xnuboot` lineage) and list the fields that are load-bearing versus optional.

2. **Does it hard-require an Apple Device Tree (ADT)?** m1n1's `adt.c` walks an `IODeviceTree`
   property tree normally supplied by iBoot. Determine whether m1n1 can run when no ADT is present:
   which subsystems would fail, which would still work from compile-time constants (note
   `src/soc.h` defines an early UART base for S8000/S8003 at compile time), and whether it can still
   reach the point of handing a supplied device tree to a Linux kernel. This is the crux: if m1n1
   needs the ADT, something must provide it.

3. **Load address.** What address is `m1n1.bin` linked to run at? Check the linker scripts. Then
   compare against where a bootrom in "accepts unsigned images" mode places an uploaded image on A9
   (the iBSS/iBoot-stage load address for `s8003`). **Do they match?** If not, can m1n1 be relocated
   (is the code position-independent, `-fPIC`/`ADR`-relative), or would the loader have to place it at
   m1n1's preferred address and jump there?

4. **What is the minimum shim, if one is needed?** If m1n1 cannot run with nothing in front of it,
   specify the *smallest possible* thing that would satisfy it — for example, a stub that constructs
   a minimal boot args struct and a minimal device tree in memory and jumps to m1n1. Describe the
   minimum contents of that structure and tree for this SoC. I want to know how small "small" is.

5. **How the kernel gets its device tree.** In the documented flow the host concatenates
   `m1n1.bin`, a `chosen.bootargs=` line, a `s8003-n69.dtb`, an `Image.gz` and an initramfs into one
   blob. Confirm how m1n1 finds and parses those appended payloads (container format, magic,
   alignment) and what m1n1 patches in the supplied DTB before jumping to Linux — specifically the
   `memory` node, the `framebuffer0` node's `reg` and `status`, and `cpu-release-addr`, all of which
   the DTS marks `/* To be filled by loader */`.

## Output

Answer each question with `file:line` citations from the tree, and URLs where you go to upstream. The
single most valuable thing you can tell me is a clear **yes or no on question 3/4**: can `m1n1.bin`
be loaded directly and executed, or is an intermediate stage structurally required? If it is required,
say so plainly and explain the reason in one paragraph — that answer redirects the entire project, and
I would much rather have it now than discover it at the hardware. Mark inference as inference.
