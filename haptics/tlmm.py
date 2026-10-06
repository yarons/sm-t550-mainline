#!/usr/bin/env python3
# tlmm.py <gpio> [get | static-high | restore <cfg> <io>] — MSM8916 TLMM pad config via /dev/mem (root, test use).
import mmap, os, struct, sys
g = int(sys.argv[1]); act = sys.argv[2] if len(sys.argv) > 2 else "get"
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0x1000000 + 0x1000 * g)
r = lambda o: struct.unpack_from("<I", m, o)[0]
w = lambda o, v: struct.pack_into("<I", m, o, v)
cfg, io = r(0), r(4)
if act == "static-high":
    w(4, io | 2); w(0, (cfg & ~(0xf << 2)) | (1 << 9))  # out=1, then func 0 (GPIO) + OE
elif act == "restore":
    w(0, int(sys.argv[3], 0)); w(4, int(sys.argv[4], 0))
print("gpio%d cfg=0x%x (func %d, oe %d) io=0x%x (in %d out %d)" % (g, r(0), (r(0) >> 2) & 0xf, (r(0) >> 9) & 1, r(4), r(4) & 1, (r(4) >> 1) & 1))
