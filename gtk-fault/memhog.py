#!/usr/bin/env python3
"""memhog.py <MB> <secs> — allocate and touch <MB> of anonymous memory, hold it <secs> (memory-pressure lever)."""
import sys, time
mb, secs = int(sys.argv[1]), float(sys.argv[2])
chunks = []
for _ in range(mb // 16):
    b = bytearray(16 << 20)
    for i in range(0, len(b), 4096):
        b[i] = 1
    chunks.append(b)
time.sleep(secs)
