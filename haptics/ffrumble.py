#!/usr/bin/env python3
# ffrumble.py <event dev> <ms> [strong 0-65535] — upload an FF_RUMBLE effect and play it once.
import fcntl, os, struct, sys, time
dev, ms = sys.argv[1], int(sys.argv[2]); strong = int(sys.argv[3]) if len(sys.argv) > 3 else 0xC000
EVIOCSFF = 0x40304580  # _IOW(E, 0x80, struct ff_effect), sizeof(struct ff_effect) = 48 on arm64
# type, id, direction, trigger(button, interval), replay(length, delay), then the union at offset 16
eff = bytearray(struct.pack("<HhHHHHH", 0x50, -1, 0, 0, 0, ms, 0)) + bytearray(48 - 14)
struct.pack_into("<HH", eff, 16, strong, strong // 2)
fd = os.open(dev, os.O_RDWR)
fcntl.ioctl(fd, EVIOCSFF, eff, True)
eid = struct.unpack_from("<h", eff, 2)[0]
os.write(fd, struct.pack("<qqHHi", 0, 0, 0x15, eid, 1))  # EV_FF, code = effect id, value 1 = play
time.sleep(ms / 1000 + 0.2)
os.close(fd)
print("played effect", eid, "for", ms, "ms")
