# Task: build a bootable Debian arm64 initramfs for a specific embedded ARM64 board

I need a **reproducible build system** that produces a RAM-backed Debian arm64 initramfs for one
specific board. You have shell access; please actually build it and report real measured output.

## Target board

Apple **A9**, SoC variant `s8003`, board `n69ap` — the 2016 iPhone SE. 2 GB RAM, 640x1136 display.
It runs mainline-ish Linux (the `HoolockLinux/linux` tree, `hocklock` branch, kernel 7.3.0-rc1 with
Apple SoC enablement). A kernel `Image.gz` and the board's device tree are being built separately —
your job is the **userland only**.

## What the hardware can and cannot do

Kernel support present: UART, interrupt controller, GPIO/pinctrl, watchdog, power domains, cpufreq,
I2C, backlight, gpio-keys, and a simple linear framebuffer handed over by the loader. **USB2 device
mode** is present in the downstream tree, which matters a lot.

Kernel support **absent**: storage controller, USB *host*, PCIe, IOMMU, PMIC, Wi-Fi, Bluetooth,
touchscreen, GPU.

## The three consequences you must design around

1. **There is no storage driver, so the rootfs must live in RAM as an initramfs.** Budget it against
   2 GB minus kernel and framebuffer. Measure the real compression ratio; do not assume one.
2. **Networking exists only as a USB gadget.** A reference initramfs for this hardware presents:
   a USB serial adapter (host sees `/dev/ttyACM0`), a USB Ethernet adapter (device `172.16.42.1`,
   host `172.16.42.2`, a telnet shell on port 23), and a small FAT16 ramdisk holding log files.
   Anything needing the network must go over that link.
3. **Nothing persists across a reboot.** Say so in the README, and say what it costs the user
   (`apt install` does not survive) and what the mitigations are (rebuild the image; or serve the
   rootfs over the USB Ethernet link from the host).

## Deliverables

Create everything under `<REPO_ROOT>\debian-ios\`:

1. `build.sh` — a `mmdebstrap`- or `debootstrap`-based build producing a Debian arm64 rootfs,
   `--variant=minbase`, plus an explicit package list. Include: an init system (choose between
   `systemd` and a busybox-init and **argue the choice in the README rather than defaulting
   silently**), `ifupdown` or `network-manager`, `dropbear` or `openssh-server`, `usbutils`, `kmod`,
   `dialog`, a shell, and whatever the USB gadget presentation needs.
2. `packages.list` — the explicit package set, committed.
3. `README.md` — what this is, the board, every limitation from the three points above stated without
   softening, and the honest framing of the branding question below.
4. `boot-test.md` — exactly what should appear on first boot, step by step, so a failure localises to
   a stage instead of being a blank screen.

Reproducibility: pin the Debian suite and mirror, record package versions, and record the SHA-256 and
size of the produced `initramfs.gz`.

**On branding, be honest:** this is "a Debian rootfs with our own init and package set", not a new
distribution. Say that. Describe what would have to be true before it could honestly be called a fork
— own repository, own kernel packaging, own installer — and do not overclaim in the README.

## Environment

- Use **Podman** for the build. A VM is running: `podman machine ssh main` gets you a shell,
  `podman` works from Windows directly.
- **Build inside the VM's own filesystem, never under `/mnt/p`.** `/mnt/p` is a `v9fs` mount of the
  Windows `P:` drive: POSIX semantics are degraded (no real hardlinks, poor symlink and permission
  behaviour) and builds break there. Clone sources and build under `/build` or `/root` in the VM, and
  copy only the finished artefact back to `<REPO_ROOT>\debian-ios\`.
- **Do not disturb an existing container named `a9build`** — it is running a kernel build. Use your
  own container name.
- The VM has ~15 GB RAM and ~900 GB free disk.

## Ground rules

- **Do not touch any USB device.** There is a phone attached to this machine; it is off limits. This
  task is file-level only.
- Report **MEASURED** facts (things you ran) separately from **INFERRED** ones. Do not present an
  assumption as a measurement.
- If something does not work, say what failed and what you tried — a clean negative result is worth
  more here than a hopeful summary.
- Final report: under 15 lines. Files created, the exact build command, the measured size and SHA-256
  of the initramfs, and anything you could not do.
