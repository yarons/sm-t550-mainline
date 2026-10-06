#!/usr/bin/env python3
# gp2regs.py — read the MSM8916 GCC GP2 clock registers (CBCR 0x1809000, CMD/CFG RCGR, M, N, D) via /dev/mem (root).
import mmap, os, struct
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x1809000)
r = lambda off: struct.unpack_from("<I", m, off)[0]
cbcr, cmd, cfg, M, N, D = r(0x0), r(0x4), r(0x8), r(0xc), r(0x10), r(0x14)
print("CBCR=%08x (en %d, off %d)  CMD=%08x (root_en %d root_off %d)  CFG=%08x (src %d div %d mode %d)" % (cbcr, cbcr & 1, cbcr >> 31, cmd, (cmd >> 1) & 1, cmd >> 31, cfg, (cfg >> 8) & 7, cfg & 0x1f, (cfg >> 12) & 3))
n = (~N + M) & 0xff; d = (~D & 0xff) >> 0
print("M=%x N=%x D=%x -> m=%d n=%d (N-M decoded) d_raw=%d" % (M, N, D, M & 0xff, n, d))
