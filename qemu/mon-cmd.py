#!/usr/bin/env python3
"""mon-cmd.py <unix-socket> <hmp-command> [...] — run monitor commands and print the replies."""
import socket
import sys
import time

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.settimeout(2.0)
time.sleep(0.4)
try:
    s.recv(65536)
except socket.timeout:
    pass
for cmd in sys.argv[2:]:
    s.sendall((cmd + "\n").encode())
    time.sleep(0.7)
out = b""
try:
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        out += chunk
except socket.timeout:
    pass
for line in out.decode(errors="replace").splitlines():
    line = line.strip()
    if not line:
        continue
    print(line[:160])
