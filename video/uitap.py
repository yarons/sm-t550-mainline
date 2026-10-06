#!/usr/bin/env python3
# uitap.py <x> <y> [taps] [gap_s] — (root) tap the screen through a temporary uinput touchscreen that copies the real
# maXTouch axis ranges; <x> <y> are panel-native pixels of the raw 768x1024 scanout (a kmsgrab screenshot), so the
# compositor rotates them exactly like a finger. Used to press Snapshot's shutter (it has no D-Bus or key binding).
import fcntl
import os
import struct
import sys
import time

REAL = "/dev/input/event4"
W, H = 768, 1024
x, y = float(sys.argv[1]), float(sys.argv[2])
taps = int(sys.argv[3]) if len(sys.argv) > 3 else 1
gap = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, ABS_X, ABS_Y = 0x14A, 0, 1
ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_ID = 0x2F, 0x35, 0x36, 0x39


def absinfo(fd, code):  # EVIOCGABS: value, min, max, fuzz, flat, resolution
    return struct.unpack("6i", fcntl.ioctl(fd, 0x80184540 + code, b"\0" * 24))


rfd = os.open(REAL, os.O_RDONLY)
rx, ry = absinfo(rfd, ABS_MT_X), absinfo(rfd, ABS_MT_Y)
os.close(rfd)
fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, 0x40045564, EV_KEY)  # UI_SET_EVBIT
fcntl.ioctl(fd, 0x40045564, EV_ABS)
fcntl.ioctl(fd, 0x40045564, EV_SYN)
fcntl.ioctl(fd, 0x40045565, BTN_TOUCH)  # UI_SET_KEYBIT
for c in (ABS_X, ABS_Y, ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_ID):
    fcntl.ioctl(fd, 0x40045567, c)  # UI_SET_ABSBIT
fcntl.ioctl(fd, 0x4004556E, 1)  # UI_SET_PROPBIT INPUT_PROP_DIRECT
amax, amin = [0] * 64, [0] * 64
for c, r in ((ABS_X, rx), (ABS_Y, ry), (ABS_MT_X, rx), (ABS_MT_Y, ry)):
    amin[c], amax[c] = r[1], r[2]
amax[ABS_MT_SLOT], amax[ABS_MT_ID] = 0, 65535
dev = struct.pack("80sHHHHi64i64i64i64i", b"gt510 test touch", 0x18, 0x1234, 0x5678, 1, 0,
                  *amax, *amin, *([0] * 64), *([0] * 64))
os.write(fd, dev)
fcntl.ioctl(fd, 0x5501)  # UI_DEV_CREATE
time.sleep(1.5)  # let udev and the compositor pick the device up
px = int(rx[1] + x / (W - 1) * (rx[2] - rx[1]))
py = int(ry[1] + y / (H - 1) * (ry[2] - ry[1]))


def ev(t, c, v):
    os.write(fd, struct.pack("qqHHi", 0, 0, t, c, v))


for i in range(taps):
    ev(EV_ABS, ABS_MT_SLOT, 0); ev(EV_ABS, ABS_MT_ID, 100 + i)
    ev(EV_ABS, ABS_MT_X, px); ev(EV_ABS, ABS_MT_Y, py); ev(EV_ABS, ABS_X, px); ev(EV_ABS, ABS_Y, py)
    ev(EV_KEY, BTN_TOUCH, 1); ev(EV_SYN, 0, 0)
    time.sleep(0.08)
    ev(EV_ABS, ABS_MT_ID, -1); ev(EV_KEY, BTN_TOUCH, 0); ev(EV_SYN, 0, 0)
    print("tap %d at (%d,%d) -> device (%d,%d)" % (i + 1, x, y, px, py), flush=True)
    if i + 1 < taps:
        time.sleep(gap)
time.sleep(0.5)
fcntl.ioctl(fd, 0x5502)  # UI_DEV_DESTROY
os.close(fd)
