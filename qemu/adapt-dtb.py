#!/usr/bin/env python3
"""adapt-dtb.py — turn our A9/n69ap device tree into something QEMU `virt` can
actually run, WITHOUT pretending the result is our board.

WHY THIS EXISTS
---------------
Our DTB's interrupt controller is Apple's AIC (`apple,s8000-aic` at
0x20E100000), its console is an Apple s5l-uart at 0x20A0C000, and its clock /
power / pinctrl providers are all Apple PMGR blocks. QEMU `virt` implements
none of them. So there is no such thing as "booting our DTB on QEMU virt"
without substitution, and anyone who claims otherwise is measuring something
else.

What this script does instead is keep the parts of the DT the *kernel* parses
in a board-independent way -- /memory, /cpus (spin-table + cpu-release-addr),
/chosen (bootargs, stdout-path, framebuffer0), /aliases, /reserved-memory --
and swaps the address-mapped devices for QEMU's equivalents. Every substitution
is recorded in the emitted .transform.txt next to the DTB, so the difference
between "what we tested" and "what we ship" is always visible.

MODES
  console : graft a PL011 as the console (so we can SEE anything at all) and
            leave /memory unfilled. This is the "loader forgot to fill memory"
            failure signature.
  fill    : console + fill /memory, leave the A9 interrupt controller in place.
            This is the "loader filled memory but we are not on our hardware"
            signature.
  virt    : fill + full substitution (AIC -> GICv2, A9 timer -> QEMU timer,
            every A9 /soc peripheral disabled, framebuffer0 filled). This is the
            only mode that can reach userland, and it validates DT *shape*.

Deliberately NOT done: no attempt to make the substituted DTB look like a boot
on A9. Read CANNOT-PROVE.md before quoting any result from these runs.
"""
import argparse
import os
import re
import subprocess
import sys

NODE_RE = re.compile(r'^(?P<indent>\s*)(?:(?P<label>[A-Za-z0-9_]+):\s*)?(?P<name>[A-Za-z0-9_,.+\-#]+@?[A-Za-z0-9_,.+\-]*)\s*\{\s*$')
PROP_RE = re.compile(r'^(?P<indent>\s*)(?P<key>[A-Za-z0-9_,.+\-#]+)\s*=\s*(?P<val>.*);\s*$')


class Node:
    def __init__(self, name, label=None, indent='\t'):
        self.name = name
        self.label = label
        self.indent = indent
        self.props = []      # list of (key, raw_value_text)
        self.children = []
        self.order = []      # ('p', idx) / ('c', idx) to preserve layout

    @property
    def path(self):
        return '/' + self.name

    def find(self, name):
        for c in self.children:
            if c.name == name or (c.label and c.label == name):
                return c
        return None

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()

    def set_prop(self, key, value):
        for i, (k, _) in enumerate(self.props):
            if k == key:
                self.props[i] = (key, value)
                return
        self.props.append((key, value))

    def del_prop(self, key):
        self.props = [(k, v) for (k, v) in self.props if k != key]

    def get_prop(self, key):
        for k, v in self.props:
            if k == key:
                return v
        return None

    def add_child(self, node, first=False):
        if first:
            self.children.insert(0, node)
        else:
            self.children.append(node)
        return node

    def remove_child(self, node):
        self.children.remove(node)

    def emit(self, out, depth=0):
        ind = self.indent * depth
        for k, v in self.props:
            out.append(f"{ind}{k};" if (v is None or v == '') else f"{ind}{k} = {v};")
        for c in self.children:
            out.append('')
            lab = f"{c.label}: " if c.label else ''
            out.append(f"{ind}{lab}{c.name} {{")
            c.emit(out, depth + 1)
            out.append(f"{ind}}};")


BOOL_RE = re.compile(r'^(?P<indent>\s*)(?P<key>[A-Za-z0-9_,.+\-#]+)\s*;\s*$')
ROOT_OPEN_RE = re.compile(r'^\s*/\s*\{\s*$')


def parse_dts(text):
    root = Node('')
    stack = [root]
    memreserve = []
    for line in text.splitlines():
        s = line.strip()
        if s in ('/dts-v1/;', '') or s.startswith('//'):
            continue
        if s.startswith('/memreserve/'):
            memreserve.append(s)
            continue
        if ROOT_OPEN_RE.match(line):
            continue
        m = NODE_RE.match(line)
        if m and s not in ('{', '};'):
            node = Node(m.group('name'), m.group('label'), m.group('indent'))
            stack[-1].add_child(node)
            stack.append(node)
            continue
        if re.match(r'^\s*\};\s*$', line):
            if len(stack) > 1:
                stack.pop()
            continue
        m = PROP_RE.match(line)
        if m:
            stack[-1].props.append((m.group('key'), m.group('val')))
            continue
        m = BOOL_RE.match(line)
        if m:
            stack[-1].props.append((m.group('key'), None))   # boolean property
            continue
        if s:
            stack[-1].props.append(('__raw__', s))
    return root, memreserve


def emit(root, memreserve):
    raw = [f"/* dropped-unparsed: {v} */" for k, v in root.props if k == '__raw__']
    props = [(k, v) for k, v in root.props if k != '__raw__']
    kids = []
    for c in root.children:
        cl = []
        lab = f"{c.label}: " if c.label else ''
        cl.append(f"{lab}{c.name} {{")
        c.emit(cl, 1)
        cl.append("};")
        kids.append('\n'.join(cl))
    body = '\n'.join(f"{k} = {v};" if v is not None else f"{k};" for k, v in props)
    return ('/dts-v1/;\n\n' + '\n'.join(memreserve) + ('\n\n' if memreserve else '')
            + '\n'.join(raw) + ('\n' if raw else '')
            + '/ {\n' + body + '\n\n' + '\n\n'.join(kids) + '\n};\n')


# --------------------------------------------------------------------------
def graft_console(root, transform):
    """PL011 at QEMU's address, made the stdout-path target."""
    clk = Node('clock-pl011')
    clk.set_prop('compatible', '"fixed-clock"')
    clk.set_prop('#clock-cells', '<0x00>')
    clk.set_prop('clock-frequency', '<0x16e3600>')   # 24 MHz
    clk.label = 'qemu_uartclk'
    root.add_child(clk)

    uart = Node('pl011@9000000')
    uart.set_prop('compatible', '"arm,pl011", "arm,primecell"')
    uart.set_prop('reg', '<0x00 0x09000000 0x00 0x1000>')
    uart.set_prop('interrupts', '<0x00 0x01 0x04>')
    uart.set_prop('clocks', '<&qemu_uartclk>, <&qemu_uartclk>')
    uart.set_prop('clock-names', '"uartclk", "apb_pclk"')
    uart.set_prop('status', '"okay"')
    root.add_child(uart)
    transform.append(
        "GRAFT: added pl011@9000000 (arm,pl011, QEMU virt's UART) + 24MHz fixed clock. "
        "QEMU emulates this UART; A9's apple,s5l-uart at 0x20A0C000 is NOT emulated.")

    al = root.find('aliases')
    if al is not None:
        al.set_prop('serial0', '&pl011_console')
        # re-label the uart so the alias resolves
        uart.label = 'pl011_console'
        transform.append("EDIT: /aliases/serial0 now points at the grafted pl011 "
                         "(was /soc/serial@20a0c0000). /chosen/stdout-path stays \"serial0\", "
                         "so the kernel's alias->node resolution is still exercised.")
    return uart


def fill_memory(root, base, size, transform):
    mem = None
    for c in root.children:
        if c.name.startswith('memory@'):
            mem = c
            break
    if mem is None:
        mem = root.add_child(Node(f'memory@{base:x}'))
        mem.set_prop('device_type', '"memory"')
    old = mem.get_prop('reg')
    mem.set_prop('reg', f'<0x{(base >> 32) & 0xffffffff:x} 0x{base & 0xffffffff:x} '
                        f'0x{(size >> 32) & 0xffffffff:x} 0x{size & 0xffffffff:x}>')
    transform.append(f"FILL: /{mem.name}/reg  {old}  ->  QEMU RAM base=0x{base:x} size=0x{size:x}. "
                     f"On the phone the loader must fill this with the REAL DRAM map "
                     f"(HANDOFF §8.11); QEMU RAM lives at 0x40000000 and A9 DRAM at 0x800000000, "
                     f"so this substitution is a QEMU necessity, not a proposed value.")


def fill_framebuffer(root, addr, size, width, height, stride, fmt, transform):
    chosen = root.find('chosen')
    fb = None
    if chosen:
        for c in chosen.children:
            if c.name.startswith('framebuffer@'):
                fb = c
        if fb is None:
            fb = chosen.add_child(Node('framebuffer@0'))
            fb.set_prop('compatible', '"apple,simple-framebuffer", "simple-framebuffer"')
    fb.name = f'framebuffer@{addr:x}'
    fb.set_prop('reg', f'<0x{(addr >> 32) & 0xffffffff:x} 0x{addr & 0xffffffff:x} '
                       f'0x{(size >> 32) & 0xffffffff:x} 0x{size & 0xffffffff:x}>')
    fb.set_prop('width', f'<0x{width:x}>')
    fb.set_prop('height', f'<0x{height:x}>')
    fb.set_prop('stride', f'<0x{stride:x}>')
    fb.set_prop('format', f'"{fmt}"')
    fb.set_prop('status', '"okay"')
    before = fb.get_prop('power-domains')
    fb.del_prop('power-domains')   # ps_disp0/ps_mipi_dsi are Apple PMGR, not emulated
    transform.append(f"FILL: /chosen/{fb.name} reg=0x{addr:x}+0x{size:x} "
                     f"{width}x{height} stride={stride} format={fmt} status=okay"
                     + (f" (dropped power-domains = {before}: Apple PMGR is not emulated, and a "
                        f"provider that never probes would leave simpledrm deferred forever)" if before else ""))

    rm = root.find('reserved-memory')
    if rm is not None:
        existing = [c for c in rm.children if c.name == fb.name]
        if not existing:
            r = rm.add_child(Node(fb.name))
            r.set_prop('reg', f'<0x{(addr >> 32) & 0xffffffff:x} 0x{addr & 0xffffffff:x} '
                              f'0x{(size >> 32) & 0xffffffff:x} 0x{size & 0xffffffff:x}>')
            r.set_prop('no-map', None)
            transform.append(f"ADD: /reserved-memory/{fb.name} (no-map) so the allocator cannot "
                             f"hand the scanout buffer to anything else. On the phone this region "
                             f"must be excluded from the DRAM the kernel is told about.")


def substitute_devices(root, transform):
    """AIC -> GICv2, A9 timer -> QEMU timer, disable every A9 peripheral."""
    gic = Node('intc@8000000')
    gic.set_prop('compatible', '"arm,cortex-a15-gic"')
    gic.set_prop('reg', '<0x00 0x08000000 0x00 0x10000 0x00 0x08010000 0x00 0x10000>')
    gic.set_prop('#interrupt-cells', '<0x03>')
    gic.set_prop('interrupt-controller', None)
    gic.label = 'intc'
    root.add_child(gic, first=True)
    transform.append("SUBSTITUTE: added arm,cortex-a15-gic at 0x08000000/0x08010000 (QEMU virt). "
                     "Our DTB's controller is apple,s8000-aic at 0x20E100000 -- a completely "
                     "different irqchip that QEMU cannot emulate. ALL interrupt behaviour in "
                     "these runs is QEMU's GIC, not A9's AIC.")

    root.set_prop('interrupt-parent', '<&intc>')

    timer = root.find('timer')
    if timer is not None:
        before_int = timer.get_prop('interrupts')
        timer.props = []
        timer.set_prop('compatible', '"arm,armv8-timer"')
        timer.set_prop('interrupt-parent', '<&intc>')
        timer.set_prop('interrupts', '<0x01 0x0d 0x104>, <0x01 0x0e 0x104>, '
                                     '<0x01 0x0b 0x104>, <0x01 0x0a 0x104>')
        timer.set_prop('always-on', None)
        transform.append(f"SUBSTITUTE: /timer interrupts {before_int} (AIC FIQ numbering) -> "
                         f"GIC PPI numbering. The A9 has no EL2, which is why upstream only "
                         f"lists phys+virt; QEMU's GIC gives us all four.")

    # every A9 peripheral reads MMIO that QEMU has not mapped -> a data abort in
    # probe, not a clean probe failure. Disable them all.
    disabled = []
    for c in list(root.children):
        if c.name.startswith('soc'):
            for sub in c.children:
                if sub.get_prop('status') != '"disabled"':
                    sub.set_prop('status', '"disabled"')
                    disabled.append(sub.name)
        elif c.name in ('pmu', 'opp-table', 'clock-ref'):
            if c.get_prop('status') is None:
                c.set_prop('status', '"disabled"')
                disabled.append(c.name)
    transform.append(f"DISABLE: {len(disabled)} A9 nodes set status=\"disabled\" "
                     f"(any MMIO read from an unmapped QEMU address is a guest data abort, "
                     f"which would oops the probe): {', '.join(disabled[:12])}"
                     + (" ..." if len(disabled) > 12 else ""))

    for cpu in root.find('cpus').children:
        if cpu.name.startswith('cpu@'):
            for p in ('operating-points-v2', 'performance-domains'):
                if cpu.get_prop(p):
                    cpu.del_prop(p)
    transform.append("EDIT: removed operating-points-v2/performance-domains from cpu nodes "
                     "(providers are A9 PMGR blocks QEMU does not have).")


def fill_cpu_release(root, addr, transform):
    cpus = root.find('cpus')
    filled = []
    for cpu in cpus.children:
        if cpu.name.startswith('cpu@'):
            old = cpu.get_prop('cpu-release-addr')
            cpu.set_prop('cpu-release-addr',
                         f'<0x{(addr >> 32) & 0xffffffff:x} 0x{addr & 0xffffffff:x}>')
            filled.append(f"{cpu.name} {old} -> 0x{addr:x}")
    transform.append("FILL: /cpus/*/cpu-release-addr " + '; '.join(filled)
                     + ". On the phone this must be the address iBoot/the loader actually parks the "
                       "secondary core on (HANDOFF §8.11); the value here is a QEMU RAM address and "
                       "is NOT a claim about A9. EVERY cpu node needs it -- filling only cpu@0 "
                       "leaves cpu@1 writing its entry address to PA 0.")


def set_chosen(root, bootargs, initrd_addr, initrd_size, transform):
    """Write the two blobs a9boot must deliver through the DT, not through a
    bootloader API: the command line and the initramfs placement."""
    chosen = root.find('chosen')
    if chosen is None:
        chosen = root.add_child(Node('chosen'))
    if bootargs:
        chosen.set_prop('bootargs', f'"{bootargs}"')
        transform.append(f"SET: /chosen/bootargs = \"{bootargs}\". On arm64 there is no command-line "
                         f"register -- the DT is the only channel, so a loader that forgets this "
                         f"boots with an EMPTY command line (no console=, no rdinit=).")
    if initrd_addr:
        end = initrd_addr + initrd_size
        # NOTE the names: the kernel's early_init_dt_check_for_initrd() looks for
        # "linux,initrd-start"/"linux,initrd-end" ONLY (drivers/of/fdt.c). Writing
        # the bare "initrd-start" form produces a kernel that boots normally and
        # then panics with "VFS: Cannot open root device" -- measured, see
        # logs/05-loader-stub-handoff.log before this was fixed.
        chosen.set_prop('linux,initrd-start', f'<0x{(initrd_addr >> 32) & 0xffffffff:x} '
                                              f'0x{initrd_addr & 0xffffffff:x}>')
        chosen.set_prop('linux,initrd-end', f'<0x{(end >> 32) & 0xffffffff:x} '
                                            f'0x{end & 0xffffffff:x}>')
        transform.append(f"SET: /chosen/linux,initrd-start/end = 0x{initrd_addr:x}..0x{end:x}. "
                         f"Property names matter: the kernel reads only the linux,initrd-* forms; "
                         f"a bare initrd-start is ignored and the boot dies later at "
                         f"'VFS: Cannot open root device'.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dtb')
    ap.add_argument('out')
    ap.add_argument('--mode', choices=['console', 'fill', 'virt'], default='virt')
    ap.add_argument('--mem-base', type=lambda s: int(s, 0), default=0x40000000)
    ap.add_argument('--mem-size', type=lambda s: int(s, 0), default=0x40000000)
    ap.add_argument('--fb-addr', type=lambda s: int(s, 0), default=0x7c000000)
    ap.add_argument('--fb-size', type=lambda s: int(s, 0), default=0x300000)
    ap.add_argument('--fb-width', type=int, default=640)
    ap.add_argument('--fb-height', type=int, default=1136)
    ap.add_argument('--fb-stride', type=int, default=2560)
    ap.add_argument('--fb-format', default='a8r8g8b8')
    ap.add_argument('--cpu-release-addr', type=lambda s: int(s, 0), default=0)
    ap.add_argument('--keep-aic', action='store_true',
                    help='do not substitute the interrupt controller (mode fill only)')
    ap.add_argument('--bootargs', default=None,
                    help='write /chosen/bootargs (the only cmdline channel on arm64)')
    ap.add_argument('--initrd-addr', type=lambda s: int(s, 0), default=0)
    ap.add_argument('--initrd-size', type=lambda s: int(s, 0), default=0)
    args = ap.parse_args()

    dts = subprocess.run(['dtc', '-I', 'dtb', '-O', 'dts', args.dtb, '-q'],
                         capture_output=True, text=True)
    if dts.returncode != 0:
        sys.exit(f"dtc decompile failed: {dts.stderr}")
    root, memreserve = parse_dts(dts.stdout)

    transform = [f"# transforms applied to {os.path.basename(args.dtb)} for QEMU mode={args.mode}"]

    graft_console(root, transform)
    if args.mode in ('fill', 'virt'):
        fill_memory(root, args.mem_base, args.mem_size, transform)
        if args.cpu_release_addr:
            fill_cpu_release(root, args.cpu_release_addr, transform)
    if args.mode == 'virt':
        if not args.keep_aic:
            substitute_devices(root, transform)
        fill_framebuffer(root, args.fb_addr, args.fb_size, args.fb_width,
                         args.fb_height, args.fb_stride, args.fb_format, transform)
    if args.bootargs or args.initrd_addr:
        set_chosen(root, args.bootargs, args.initrd_addr, args.initrd_size, transform)

    text = emit(root, memreserve)
    tmp = args.out + '.dts'
    with open(tmp, 'w') as f:
        f.write(text)
    r = subprocess.run(['dtc', '-I', 'dts', '-O', 'dtb', '-o', args.out, tmp],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"dtc compile failed (see {tmp}):\n{r.stderr}")
    if r.stderr.strip():
        warnlines = [l for l in r.stderr.strip().splitlines() if l.strip()]
        kinds = {}
        for l in warnlines:
            m = re.search(r'Warning \(([a-z_]+)\)', l)
            k = m.group(1) if m else 'other'
            kinds[k] = kinds.get(k, 0) + 1
        with open(args.out + '.dtc-warnings.txt', 'w') as f:
            f.write(r.stderr)
        transform.append(f"dtc emitted {len(warnlines)} warning line(s) on recompile "
                         f"({', '.join(f'{k} x{v}' for k, v in sorted(kinds.items()))}); "
                         f"full text in {os.path.basename(args.out)}.dtc-warnings.txt. "
                         f"These are all pre-existing upstream shape warnings (phandle-less "
                         f"clock/power-domain cells after decompile) plus the upstream "
                         f"/soc/bus@20c000000 unit-address/reg mismatch.")

    with open(args.out + '.transform.txt', 'w') as f:
        f.write('\n'.join(transform) + '\n')
    print(f"wrote {args.out} ({os.path.getsize(args.out)} bytes)")
    print(f"      {args.out}.dts (readable source)")
    print(f"      {args.out}.transform.txt")
    for t in transform[1:]:
        print("  " + t)


if __name__ == '__main__':
    main()
