#!/usr/bin/env python3
# h264frames.py <file.h264> [fps] [window] — split an Annex-B H.264 stream into access units (one per slice with
# first_mb_in_slice == 0) and print bytes/frame averages per window, plus I-frame sizes, to see how rate control
# behaves over time.
import sys

d = open(sys.argv[1], "rb").read()
fps = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
win = int(sys.argv[3]) if len(sys.argv) > 3 else 30
starts, i = [], 0
while True:
    j = d.find(b"\x00\x00\x01", i)
    if j < 0:
        break
    starts.append(j)
    i = j + 3
starts.append(len(d))
frames, cur, idr = [], 0, []
for k in range(len(starts) - 1):
    a, b = starts[k], starts[k + 1]
    t = d[a + 3] & 0x1f
    if t in (1, 5):
        first_mb_zero = d[a + 4] & 0x80  # ue(v) first_mb_in_slice == 0 -> leading bit 1
        if first_mb_zero and cur:
            frames.append(cur)
            cur = 0
        if t == 5 and first_mb_zero:
            idr.append(len(frames))
    cur += b - a
frames.append(cur)
print("frames %d, IDR at %s" % (len(frames), idr[:8]))
for w in range(0, len(frames), win):
    seg = frames[w:w + win]
    print("  frames %4d-%4d: %7.1f kbit/frame = %6.2f Mbit/s @%gfps (max %.0f kbit)" %
          (w, w + len(seg) - 1, sum(seg) * 8 / len(seg) / 1000, sum(seg) * 8 / len(seg) * fps / 1e6, fps,
           max(seg) * 8 / 1000))
