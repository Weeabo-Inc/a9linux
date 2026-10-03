# Task: how m1n1 hands a Linux kernel off on Apple A9, and where the display framebuffer comes from

I am assembling a boot blob and need to know exactly what the bootloader does with it. Answer from the
source tree on disk, with `file:line` citations.

## The tree

`<REPO_ROOT>\a9linux\src\m1n1\` — the `HoolockLinux/m1n1` fork (default branch, commit
`d5a10ac`). It has been confirmed to support this SoC: `src/soc.h` defines `S8000 0x8000` and
`S8003 0x8003`, `src/smp.c:286-293` handles A9 SMP spin-up, `src/cpufreq.c` has A9 cases, and
`src/chickens/twister.c` handles the A9 CPU.

## The target

iPhone SE 1st generation: Apple A9, SoC **s8003**, board `n69ap`, panel **640x1136**.

The kernel device tree for this board is at
`<REPO_ROOT>\a9linux\src\dts-ref\s8003-n69.dts` plus `s800-0-3-common.dtsi`. Note that the DT
contains deliberate loader placeholders:

- `s800-0-3-common.dtsi:25-27` — `framebuffer0: framebuffer@0 { compatible = "apple,simple-framebuffer", "simple-framebuffer"; reg = <0 0 0 0>; /* To be filled by loader */ };` and it appears `status` is not okay.
- `s800-0-3-common.dtsi:33-35` — `memory@800000000 { reg = <0x8 0 0 0>; /* To be filled by loader */ };`
- `s800-0-3-common.dtsi:43` — a `/* To be filled by loader */` near the CPU nodes.

## Questions

1. **The appended-payload container.** The documented way to build the blob is
   `cat m1n1.bin <(echo 'chosen.bootargs=<cmdline>') dtb Image.gz initramfs.gz > m1n1-linux.bin`.
   Find the code in the tree that parses this. What is the container format — magic value(s), header
   layout, alignment/padding rules, how each payload's type is identified, and how a terminator is
   detected? Is the `chosen.bootargs=...` string a raw ASCII append or a framed item, and does it need
   a trailing newline or NUL? Give `file:line`.

2. **What patches the device tree, and in what order.** Which code writes the real values into
   `memory@800000000`, the `framebuffer0` node's `reg`, and the CPU `cpu-release-addr`? Does it also
   flip the framebuffer node's `status` from disabled to okay? Trace the call order from the payload
   parser through to the kernel entry. Cite each write.

3. **The display — the question I care about most.** `src/display.c` appears to be a DCP-based path
   (`display_config_m1`, `dcp`, `dart_search`). But it also contains a check against **640x1136**,
   which is exactly this device's panel. Trace it: on a device that has **no DCP**, what does
   `display_init()` actually do? Does m1n1 **initialise the panel**, or does it consume an
   already-initialised framebuffer out of `boot_args.video`? If the latter, state precisely which
   fields of `boot_args` (or `cur_boot_args`) it requires to be populated by the previous stage, and
   what happens when they are all zero. This decides whether an on-screen console is possible at all
   on a boot path that never runs the normal iOS bootloader.

4. **`src/fb.c` versus `src/display.c`.** Which one owns the console framebuffer, and how does the
   handoff to Linux work — does m1n1 hand the kernel a populated `framebuffer0` node, or does the
   kernel discover the framebuffer some other way?

5. **Entry requirements.** What does m1n1 require to already be set up by whatever ran before it
   (the pre-boot environment stage)? Name the structures it reads (boot args / device tree / a
   handoff struct) and what happens if they are absent.

## Output

Numbered answers, each citing `file:line`. Where the code contradicts the documentation in
`github.com/HoolockLinux/docs`, say so and cite both sides. Where you cannot determine something from
the source, say so explicitly and state what would settle it — do not guess. Flag anything that looks
like it would silently produce a blank screen rather than an error.
