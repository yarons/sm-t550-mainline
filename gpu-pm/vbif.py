#!/usr/bin/env python3
"""a306 VBIF XIN halt probe via /dev/mem (root). GPU must be runtime-active (clocks on).

  vbif.py dump                        read 0x3080..0x3083
  vbif.py halt <ctrl0> <ctrl1> <mask> write mask to ctrl0, poll ctrl1 (100 ms), release (ctrl0 = 0)
Register args are dword offsets (hex), as in a3xx.xml / kgsl a3xx_reg.h.
"""
import mmap, os, struct, sys, time

BASE, SIZE = 0x01C00000, 0x20000
STATUS = "/sys/devices/platform/soc@0/1c00000.gpu/power/runtime_status"
st = open(STATUS).read().strip()
if st != "active":
    sys.exit("GPU runtime_status=%s: registers not clocked, refusing" % st)
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)
rd = lambda r: struct.unpack_from("<I", m, r * 4)[0]
def wr(r, v): struct.pack_into("<I", m, r * 4, v)

if sys.argv[1] == "dump":
    for r in range(0x3080, 0x3084):
        print("0x%04x = 0x%08x" % (r, rd(r)))
elif sys.argv[1] == "probe":
    # write <val> to <reg>, snapshot 0x3080..0x3083 immediately and after 1 ms, then write 0 back
    reg, val = (int(a, 16) for a in sys.argv[2:4])
    snap = lambda: " ".join("%08x" % rd(r) for r in range(0x3080, 0x3084))
    b = snap(); wr(reg, val); a0 = snap(); time.sleep(0.001); a1 = snap(); wr(reg, 0); a2 = snap()
    print("w 0x%04x=0x%x | before %s | +0 %s | +1ms %s | released %s" % (reg, val, b, a0, a1, a2))
elif sys.argv[1] == "halt":
    c0, c1, mask = (int(a, 16) for a in sys.argv[2:5])
    before = rd(c1)
    wr(c0, mask)
    t0 = time.monotonic(); ack = rd(c1)
    while (ack & mask) != mask and time.monotonic() - t0 < 0.1:
        ack = rd(c1)
    dt = (time.monotonic() - t0) * 1e6
    wr(c0, 0)
    after = rd(c1)
    print("ctrl0=0x%04x ctrl1=0x%04x mask=0x%x: ctrl1 before=0x%x ack=0x%x after-release=0x%x %s in %.0f us"
          % (c0, c1, mask, before, ack, after, "ACKED" if (ack & mask) == mask else "NO ACK", dt))
