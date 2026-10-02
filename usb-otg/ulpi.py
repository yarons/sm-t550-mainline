#!/usr/bin/env python3
"""Poke the msm8916 chipidea controller (usb@78d9000) and its ULPI PHY via /dev/mem.

  ulpi.py dump                 PORTSC/OTGSC/USBMODE + key ULPI registers
  ulpi.py r <reg>              read ULPI register (hex)
  ulpi.py w <reg> <val>        write ULPI register (hex); use the SET (+1) / CLR (+2) aliases for bit ops

Debug aid only (races the kernel's own viewport use; fine for one-off pokes). Needs root.
"""
import mmap, os, struct, sys, time

BASE = 0x78D9000
VIEWPORT, PORTSC, OTGSC, USBMODE = 0x170, 0x184, 0x1A4, 0x1A8
RUN, WRITE, WAKEUP = 1 << 30, 1 << 29, 1 << 31

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=BASE)


def rd(off):
    return struct.unpack_from("<I", m, off)[0]


def wr(off, val):
    struct.pack_into("<I", m, off, val)


def vp_wait(bit=RUN):
    for _ in range(10000):
        v = rd(VIEWPORT)
        if not v & bit:
            return v
        time.sleep(0.0001)
    raise TimeoutError("ULPI viewport stuck (PHY suspended? PORTSC PHCD=%d)" % ((rd(PORTSC) >> 23) & 1))


def vp_wake():
    # same as drivers/usb/chipidea/ulpi.c: wake the PHY before each access
    wr(VIEWPORT, WRITE | WAKEUP)
    vp_wait(WAKEUP)


def ulpi_read(reg):
    vp_wake()
    wr(VIEWPORT, RUN | (reg << 16))
    return (vp_wait() >> 8) & 0xFF


def ulpi_write(reg, val):
    vp_wake()
    wr(VIEWPORT, RUN | WRITE | (reg << 16) | val)
    vp_wait()


def dump():
    p = rd(PORTSC)
    print("PORTSC 0x%08x CCS=%d PE=%d LS=%d%d PP=%d PHCD=%d PSPD=%d" % (
        p, p & 1, (p >> 2) & 1, (p >> 11) & 1, (p >> 10) & 1, (p >> 12) & 1, (p >> 23) & 1, (p >> 26) & 3))
    o = rd(OTGSC)
    print("OTGSC  0x%08x ID=%d AVV=%d ASV=%d BSV=%d" % (o, (o >> 8) & 1, (o >> 9) & 1, (o >> 10) & 1, (o >> 11) & 1))
    print("USBMODE 0x%08x (CM=%d: 2 device, 3 host)" % (rd(USBMODE), rd(USBMODE) & 3))
    for name, reg in (("FUNC_CTRL", 0x04), ("IFC_CTRL", 0x07), ("OTG_CTRL", 0x0A), ("INT_STS", 0x13),
                      ("DEBUG(linestate)", 0x15), ("MISC_A", 0x96)):
        v = ulpi_read(reg)
        extra = ""
        if reg == 0x0A:
            extra = " IdPullup=%d DpPd=%d DmPd=%d DrvVbus=%d DrvVbusExt=%d" % (
                v & 1, (v >> 1) & 1, (v >> 2) & 1, (v >> 5) & 1, (v >> 6) & 1)
        elif reg == 0x04:
            extra = " XcvrSel=%d TermSel=%d OpMode=%d SuspendM=%d" % (v & 3, (v >> 2) & 1, (v >> 3) & 3, (v >> 6) & 1)
        elif reg == 0x13:
            extra = " VbusValid=%d SessValid=%d SessEnd=%d IdGnd=%d" % ((v >> 1) & 1, (v >> 2) & 1, (v >> 3) & 1, (v >> 4) & 1)
        print("ULPI %-17s[0x%02x] = 0x%02x%s" % (name, reg, v, extra))


cmd = sys.argv[1] if len(sys.argv) > 1 else "dump"
if cmd == "dump":
    dump()
elif cmd == "r":
    print("0x%02x" % ulpi_read(int(sys.argv[2], 16)))
elif cmd == "w":
    ulpi_write(int(sys.argv[2], 16), int(sys.argv[3], 16))
else:
    sys.exit(__doc__)
