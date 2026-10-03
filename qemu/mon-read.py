#!/usr/bin/env python3
"""mon-read.py <unix-socket> <hex-phys-addr> — read guest physical memory through
QEMU's monitor.

Why from outside: the kernel's spin-table code writes the secondary CPU's entry
address to the cpu-release-addr our DTB names. Reading that address from inside
the guest needs /dev/mem, which CONFIG_STRICT_DEVMEM blocks for System RAM
(measured: "read failed"). QEMU's monitor reads the same RAM without asking the
guest, which turns "the kernel probably wrote there" into an observation.
"""
import socket
import sys
import time

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.settimeout(2.0)
time.sleep(0.5)
try:
    s.recv(65536)                       # banner / prompt
except socket.timeout:
    pass

addr = sys.argv[2]
s.sendall(f"xp /1gx {addr}\n".encode())
time.sleep(1.0)
out = b""
try:
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        out += chunk
except socket.timeout:
    pass

text = out.decode(errors="replace")
for line in text.splitlines():
    if addr.lower().lstrip("0x") in line.lower() or "0x" in line:
        print(line.strip())
