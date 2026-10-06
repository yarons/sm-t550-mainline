#!/usr/bin/env python3
# gp2set.py <m> <n> <d> — reprogram MSM8916 GCC GP2 M/N/D (dual-edge MND, XO/16 = 1.2 MHz) and latch it (CMD.UPDATE).
# f = 1.2 MHz * m / n, duty = d / n. Root only; touches only GP2 (the vibrator PWM clock). Test use.
import mmap, os, struct, sys, time
m, n, d = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
mm = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x1809000)
w = lambda off, v: struct.pack_into("<I", mm, off, v & 0xffffffff)
r = lambda off: struct.unpack_from("<I", mm, off)[0]
w(0xc, m); w(0x10, ~(n - m) & 0xff); w(0x14, ~(2 * d) & 0xff)
w(0x4, r(0x4) | 1)  # CMD_RCGR.UPDATE
for _ in range(100):
    if not r(0x4) & 1: break
    time.sleep(0.001)
print("GP2: m=%d n=%d d=%d -> %.1f Hz duty %.0f%% (CMD=%08x)" % (m, n, d, 1.2e6 * m / n, 100.0 * d / n, r(0x4)))
