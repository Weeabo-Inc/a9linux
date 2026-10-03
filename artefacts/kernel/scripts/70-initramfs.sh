#!/bin/bash
# Runs INSIDE the a9build container. Inspects the bundled example initramfs:
# is it a cpio.gz this kernel can consume, and does it provide /init?
set -u
cp /build/inputs/initramfs.gz /tmp/ir.gz 2>/dev/null || { echo "no /build/inputs/initramfs.gz"; exit 1; }

echo "=== gzip metadata ==="
ls -la /tmp/ir.gz
file /tmp/ir.gz 2>/dev/null || true
python3 - <<'PY'
import gzip, struct
raw = open('/tmp/ir.gz','rb').read()
head = raw[:10]
print("magic      :", head[:2].hex(), "(1f8b == gzip)")
flg = head[3]
print("FLG        : 0x%02x  FNAME=%s" % (flg, bool(flg & 0x08)))
if flg & 0x08:
    end = raw.index(b'\0', 10)
    print("orig name  :", raw[10:end].decode('latin1'))
d = gzip.decompress(raw)
print("uncompressed size:", len(d))
print("first 6 bytes    :", d[:6].hex(), "(070701 == newc cpio)")
PY

echo ""
echo "=== cpio member census ==="
python3 - <<'PY'
import gzip, io
d = gzip.decompress(open('/tmp/ir.gz','rb').read())
i = 0; names = []; total = 0
while True:
    if d[i:i+6] != b'070701':
        print("stopped at offset", i, "magic=", d[i:i+6]); break
    def f(o, n): return int(d[i+o:i+o+n], 16)
    ino, mode, uid, gid, nlink, mtime, filesize = (f(6,8), f(14,8), f(22,8), f(30,8), f(38,8), f(46,8), f(54,8))
    namesize = f(94,8); name = d[i+110:i+110+namesize-1].decode('latin1')
    total += 1
    if name == 'TRAILER!!!': break
    names.append((name, mode, filesize))
    i += 110 + namesize
    i = (i + 3) & ~3
    i += (filesize + 3) & ~3
print("members:", total)
print()
print("--- /init and top-level entries ---")
for n, m, s in names:
    if n in ('init', '.', 'bin', 'sbin', 'etc', 'usr', 'dev', 'proc', 'sys') or n.count('/') == 0 or n == 'init':
        isdir = (m & 0o170000) == 0o040000
        print(f"  {n:<40} mode={oct(m)} size={s} {'DIR' if isdir else 'FILE'}")
print()
ini = [n for n, m, s in names if n.lstrip('./') == 'init']
print("has /init :", bool(ini), ini)
print()
print("--- executable-looking top-level files ---")
for n, m, s in names:
    if (m & 0o170000) == 0o100000 and n.count('/') <= 1 and (m & 0o111):
        print(f"  {n:<40} size={s}")
print()
print("--- anything mentioning shell/telnet/busybox ---")
hits = [n for n, m, s in names if any(k in n for k in ('busybox','sh','telnet','network'))]
for h in hits[:25]: print("  ", h)
PY
echo "=== END ==="
