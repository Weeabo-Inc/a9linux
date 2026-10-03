#!/usr/bin/env python3
"""check-dtb.py <dtb> [<dtb> ...] — STATIC device-tree gate for the a9boot hand-off.

No QEMU, no hardware. Reads the DTB with fdtget (structured, not text-scraped)
and checks the properties the loader must supply for a Linux runtime to come up.
On the phone these defects do not print an error, they hang silently; here they
print FAIL.

Verdicts
  FAIL = with this DTB as it stands, a Linux runtime cannot boot.
  WARN = boots, but something we will want (screen, second CPU, console) is missing.
  PASS = checked and present.

Exit status is non-zero if any DTB produced a FAIL.
"""
import subprocess
import sys
import os
import re

FAILS = 0
WARNS = 0


class Dt:
    """Thin fdtget wrapper. fdtget syntax is: fdtget [options] <dtfile> [<node> [<prop>]]."""

    def __init__(self, path):
        self.path = path

    def _run(self, opts, *positional):
        r = subprocess.run(['fdtget', *opts, self.path, *positional],
                           capture_output=True, text=True)
        # fdtget can exit non-zero while still printing what we asked for (it
        # appends "Unknown tag 0x.." diagnostics to stdout on some DTBs), so
        # judge on the output, not the exit status.
        out = r.stdout.strip()
        return out or None

    def children(self, node):
        out = self._run(['-l'], node)
        if not out:
            return []
        return [w for w in out.split()
                if re.match(r'^[A-Za-z0-9_,.+\-]+(@[0-9a-fA-F]+)?$', w)
                and w not in ('Unknown', 'tag')]

    def props(self, node):
        out = self._run(['-p'], node)
        return out.split() if out else []

    def s(self, node, prop):
        return self._run(['-t', 's'], node, prop)

    def x(self, node, prop):
        out = self._run(['-t', 'x'], node, prop)
        return [int(v, 16) for v in out.split()] if out else None

    def exists(self, node):
        return self._run(['-p'], node) is not None or self._run(['-l'], node) is not None

    def find(self, parent, prefix):
        return [c for c in self.children(parent) if c.startswith(prefix)]

    def walk(self, node='/'):
        yield node
        for c in self.children(node):
            yield from self.walk(node.rstrip('/') + '/' + c)


def verdict(tag, msg):
    global FAILS, WARNS
    if tag == 'FAIL':
        FAILS += 1
    elif tag == 'WARN':
        WARNS += 1
    print(f"  {tag:<4} {msg}")


def cells(reg):
    """Decode a <hi lo> address pair list into [(addr, size)] using 2/2 cells."""
    if not reg or len(reg) % 4:
        return []
    return [((reg[i] << 32) | reg[i + 1], (reg[i + 2] << 32) | reg[i + 3])
            for i in range(0, len(reg), 4)]


FMT_BPP = {'r5g6b5': 2, 'x8r8g8b8': 4, 'a8r8g8b8': 4, 'x8b8g8r8': 4, 'a8b8g8r8': 4,
           'r8g8b8': 3, 'x2r10g10b10': 4, 'a2r10g10b10': 4}


def check(dtb):
    print('=' * 78)
    print(f"DTB AUDIT: {dtb}")
    if not os.path.isfile(dtb):
        verdict('FAIL', 'file not found')
        return
    print(f"  size   : {os.path.getsize(dtb)} bytes")
    print(f"  sha256 : {subprocess.run(['sha256sum', dtb], capture_output=True, text=True).stdout.split()[0]}")
    d = Dt(dtb)
    print(f"  model  : {d.s('/', 'model')}")
    print(f"  compat : {d.s('/', 'compatible')}")
    print('-' * 78)

    # ---- 1. /memory -------------------------------------------------------
    mems = d.find('/', 'memory')
    if not mems:
        verdict('FAIL', '/memory: NO memory node -> the kernel finds no RAM at all')
    for m in mems:
        node = '/' + m
        dt = d.s(node, 'device_type')
        if dt != 'memory':
            verdict('FAIL', f'{node}: device_type is {dt!r}, not "memory" -> kernel ignores the node')
        else:
            verdict('PASS', f'{node}: device_type = "memory"')
        regs = cells(d.x(node, 'reg'))
        for addr, size in regs:
            if size == 0:
                verdict('FAIL', f'{node}: reg size is ZERO (loader placeholder unfilled) '
                                 f'-> kernel is told it has 0 bytes of RAM')
            elif addr % 0x200000:
                verdict('WARN', f'{node}: base 0x{addr:x} is not 2MiB aligned '
                                 f'(arm64 memstart wants 2MiB)')
            else:
                verdict('PASS', f'{node}: base=0x{addr:x} size=0x{size:x} ({size // 1048576} MiB)')

    # ---- 2. console / stdout-path ----------------------------------------
    sp = d.s('/chosen', 'stdout-path')
    if not sp:
        verdict('WARN', '/chosen/stdout-path ABSENT -> console falls back to /dev/tty0; '
                        'no serial console unless cmdline console= names a live tty')
    else:
        first = sp.split(':')[0]
        target = first if first.startswith('/') else None
        if target is None:
            alias = d.s('/aliases', first)
            target = alias
        if not target:
            verdict('FAIL', f'/chosen/stdout-path = "{first}" does not resolve '
                            f'(no /aliases entry and not a path) -> no console')
        elif not d.exists(target):
            verdict('FAIL', f'/chosen/stdout-path -> {target}: node does not exist in this DTB')
        else:
            st = d.s(target, 'status')
            compat = d.s(target, 'compatible')
            if st == 'disabled':
                verdict('FAIL', f'/chosen/stdout-path -> {target}: status="disabled" -> no console')
            else:
                regs = cells(d.x(target, 'reg'))
                where = f"0x{regs[0][0]:x}" if regs else 'no reg'
                verdict('PASS', f'/chosen/stdout-path -> {target} '
                                f'(compatible="{compat}", reg {where}, status={st or "okay(default)"})')

    # ---- 3. cpus / secondary bring-up ------------------------------------
    cpus = d.find('/cpus', 'cpu@')
    if not cpus:
        verdict('FAIL', '/cpus: no cpu@ nodes')
    for c in cpus:
        node = f'/cpus/{c}'
        em = d.s(node, 'enable-method') or d.s('/cpus', 'enable-method')
        if em == 'spin-table':
            rel = d.x(node, 'cpu-release-addr') or d.x('/cpus', 'cpu-release-addr')
            if not rel:
                verdict('FAIL', f'{node}: enable-method=spin-table but cpu-release-addr is ABSENT')
            else:
                addr = (rel[0] << 32) | rel[1] if len(rel) == 2 else rel[0]
                if addr == 0:
                    verdict('FAIL', f'{node}: cpu-release-addr is ZERO -> the kernel writes the '
                                    f'entry address to PA 0 and this CPU never comes online '
                                    f'(silent SMP hang / data abort)')
                elif addr % 8:
                    verdict('WARN', f'{node}: cpu-release-addr 0x{addr:x} is not 8-byte aligned')
                else:
                    verdict('PASS', f'{node}: spin-table, cpu-release-addr = 0x{addr:x}')
        elif em == 'psci':
            verdict('PASS' if d.exists('/psci') else 'FAIL',
                    f'{node}: enable-method=psci, /psci {"present" if d.exists("/psci") else "MISSING"}')
        else:
            verdict('WARN', f'{node}: enable-method {em!r} — not checked by this audit')
    if len(cpus) == 1:
        verdict('WARN', '/cpus: only one CPU node (A9/n69ap has two)')

    # ---- 4. timer ---------------------------------------------------------
    tcompat = (d.s('/timer', 'compatible') or '')
    if 'arm,armv8-timer' in tcompat:
        n = len(d.x('/timer', 'interrupts') or []) // 3
        verdict('PASS' if n >= 2 else 'WARN',
                f'/timer: arm,armv8-timer with {n} interrupt(s)')
    else:
        verdict('FAIL', f'/timer: compatible={tcompat!r} is not arm,armv8-timer -> no clock')

    # ---- 4b. initramfs channel (DT is the only one on arm64) ---------------
    ir = d.x('/chosen', 'linux,initrd-start')
    ire = d.x('/chosen', 'linux,initrd-end')
    bare = d.x('/chosen', 'initrd-start')
    if ir and ire:
        start = (ir[0] << 32) | ir[1] if len(ir) == 2 else ir[0]
        end = (ire[0] << 32) | ire[1] if len(ire) == 2 else ire[0]
        verdict('PASS' if end > start else 'FAIL',
                f'/chosen/linux,initrd-start/end = 0x{start:x}..0x{end:x} '
                f'({end - start} bytes)')
    elif bare:
        verdict('FAIL', '/chosen has bare initrd-start/end but NOT linux,initrd-start/end '
                        '-> the kernel ignores it and later panics "VFS: Cannot open root device"')
    else:
        verdict('WARN', '/chosen: no linux,initrd-start/end -> the kernel will find no initramfs')

    # ---- 5. framebuffer (our only display path) ---------------------------
    fbs = d.find('/chosen', 'framebuffer@')
    if not fbs:
        verdict('WARN', '/chosen: no framebuffer@ node -> no simple-framebuffer, no screen console')
    for fb in fbs:
        node = f'/chosen/{fb}'
        st = d.s(node, 'status')
        regs = cells(d.x(node, 'reg'))
        regsize = regs[0][1] if regs else 0
        if st == 'disabled' or regsize == 0:
            verdict('WARN', f'{node}: status={st}, reg size=0x{regsize:x} -> still a loader '
                            f'placeholder; the panel stays dark')
            continue
        w, h = d.x(node, 'width'), d.x(node, 'height')
        stride, fmt = d.x(node, 'stride'), d.s(node, 'format')
        missing = [k for k, v in (('width', w), ('height', h), ('stride', stride),
                                  ('format', fmt)) if not v]
        if missing:
            verdict('FAIL', f'{node}: status=okay but {", ".join(missing)} missing '
                            f'-> simpledrm refuses the node and the screen stays dark')
            continue
        w, h, stride = w[0], h[0], stride[0]
        bpp = FMT_BPP.get(fmt)
        problems = []
        if bpp and stride < w * bpp:
            problems.append(f'stride {stride} < width {w} x {bpp}B')
        if stride * h > regsize:
            problems.append(f'stride x height = {stride * h} > reg size 0x{regsize:x}')
        if problems:
            verdict('FAIL', f'{node}: ' + '; '.join(problems) + ' -> simpledrm draws outside the '
                            f'buffer (garbage or an oops)')
        else:
            verdict('PASS', f'{node}: {w}x{h} stride={stride} format={fmt} in 0x{regsize:x} bytes'
                            + ('' if bpp else f' (unknown format {fmt!r}: size not cross-checked)'))

    # ---- 6. leftover loader placeholders ---------------------------------
    zeros = []
    for n in d.walk('/'):
        reg = d.x(n, 'reg')
        if reg and len(reg) == 4 and not any(reg):
            zeros.append(n)
    if zeros:
        verdict('WARN', f'{len(zeros)} node(s) still carry the all-zero <0 0 0 0> loader '
                        f'placeholder: {", ".join(zeros[:6])}' + (' ...' if len(zeros) > 6 else ''))
    else:
        verdict('PASS', 'no node carries an all-zero reg placeholder')

    print('-' * 78)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit('usage: check-dtb.py <dtb> [dtb2 ...]')
    before = (FAILS, WARNS)
    for a in sys.argv[1:]:
        check(a)
        print(f"  RESULT for {os.path.basename(a)}: {FAILS - before[0]} FAIL, {WARNS - before[1]} WARN")
        before = (FAILS, WARNS)
    sys.exit(1 if FAILS else 0)
