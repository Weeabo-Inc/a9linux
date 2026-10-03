# Task: specify the host-side procedure for loading pongoOS onto an Apple A9 device

I am writing **host-side tooling in Rust for Windows**. I need a precise specification to implement
against, taken from real source code — not a tutorial summary.

## The situation

- The device is an iPhone SE 1st generation (Apple A9, SoC variant **s8003**, chip id `0x8003`), sitting
  in DFU mode on USB `VID_05AC / PID_1227`.
- **A separate, already-completed step has put the device's bootrom into the state where it accepts
  unsigned images.** That step is done, it works, and it is explicitly OUT OF SCOPE for this task — do
  not design it, describe it, or concern yourself with it. Treat "the bootrom now accepts unsigned
  images" as a given precondition, exactly like "the device is plugged in".
- What I need is the **next** step: getting a small pre-boot environment (**pongoOS**) onto the device
  and running, from a Windows host.

## Why I am asking you rather than using existing tooling

The established host tools for this step are `palera1n` and `checkra1n`. **Neither ships a Windows
build** — palera1n states "Linux or macOS computer", checkra1n states "only available for macOS and
Linux". So I cannot use them; I must reimplement the host side. I need the wire-level and
image-format facts to do that correctly.

## What to read

Primary sources, in priority order. Cite `file:line` for every claim.

1. `palera1n/palera1n` — how it loads pongoOS onto a device (`-l` / `-lp` modes, the `-k` override
   for a custom pongoOS image). Find the actual USB/serial code path.
2. `palera1n/pongoOS`, branch `iOS15` — the device side. Note that `checkra1n/PongoOS` master is
   frozen at 2021-11-04 and is NOT what current documentation uses.
3. `checkra1n/PongoOS` — `src/shell/usbloader.c` for the USB protocol the loaded environment presents
   afterwards.

## Questions I need answered

1. **Image format.** What form does the pongoOS image take on the wire? Is it raw AArch64 code, or
   wrapped (an iBSS-shaped container, IMG3/IMG4 with a header, or something with a custom prologue)?
   I have `Pongo.bin` (238,096 bytes) and its first bytes are `04 00 00 10 e5 07 61 b2 9f 00 05 eb
   40 01 00 54 ...` — no recognisable container magic, which suggests raw. **Confirm or refute**, and
   if it is raw, state what the loading tool does to it before sending.

2. **Load address.** What physical address does the image get placed at for an A9? State where that
   number comes from in source. Distinguish `dfu_image_base` / `dfu_load_base` / `rom_base` style
   addresses if the tooling uses more than one.

3. **The transfer sequence.** The exact DFU requests: `bmRequestType`, `bRequest`, `wValue` (is it a
   block index?), `wIndex`, `wLength`, and the chunk size. Note where `DFU_GETSTATUS` polling is
   required between chunks and what state machine values are expected. State the terminating request
   (a zero-length `DFU_DNLOAD`? a specific suffix length?) that concludes the upload.

4. **The go/execute step.** How is control transferred to the loaded image? Is there an explicit
   "execute" request, a device reset, a register write, or does the bootrom jump automatically after a
   well-formed upload? If a `DFU_CLRSTATUS` or a state-machine transition (`MANIFEST_WAIT_RESET`) is
   involved, give the exact sequence.

5. **Success criterion.** How does the host know it worked? Does the device re-enumerate on a
   different product id? Does the serial descriptor change? What does pongoOS present as
   (`VID`/`PID`) once running, and how long does that take?

6. **Preconditions and traps.** Anything the host must do first (claiming an interface, a specific
   configuration, an initial request) and anything that silently makes the upload fail. I care most
   about failure modes that produce no error — I have already been bitten by a reset call that
   returned success while doing nothing.

## Output

A numbered implementation specification, each point citing `file:line` or a URL. Where you could not
find the answer in source, say so explicitly and state what would settle it. Mark anything you are
inferring as an inference. Do not pad; I would rather have six precise points than twenty vague ones.
