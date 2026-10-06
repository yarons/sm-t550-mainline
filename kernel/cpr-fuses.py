#!/usr/bin/env python3
# cpr-fuses.py — read the MSM8916 CPR fuse row 27 from the CORRECTED QFPROM mirror (0x5c000, the region mainline's
# nvmem driver maps; the raw 0x58000 region downstream reads is not touched) via /dev/mem (root), and decode it with
# the downstream msm8916-regulator.dtsi layout: open-loop init voltage = ref + value * 10 mV per fuse corner, 6-bit
# sign-magnitude fields at bits 36 (SVS), 18 (NOM), 0 (TURBO); target quotients 12 bits at 42/24/6; ro-sel at 54.
import mmap, os, struct
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x5c000)
row = lambda n: struct.unpack_from("<Q", m, n * 8)[0]
r27 = row(27)
print("row 27 = 0x%016x" % r27)
field = lambda v, lsb, w: (v >> lsb) & ((1 << w) - 1)
def sm(v, w):  # sign-magnitude
    return -(v & ((1 << (w - 1)) - 1)) if v & (1 << (w - 1)) else v
for name, lsb, ref, qlsb in (("SVS", 36, 1050000, 42), ("NOM", 18, 1150000, 24), ("TURBO", 0, 1375000, 6)):
    raw = field(r27, lsb, 6)
    uv = ref + sm(raw, 6) * 10000
    print("%-5s init field 0x%02x (%+d) -> %.4f V   target quot %d" % (name, raw, sm(raw, 6), uv / 1e6, field(r27, qlsb, 12)))
print("ro-sel %d, cpr-disable bit57 %d" % (field(r27, 54, 3), field(r27, 57, 1)))
