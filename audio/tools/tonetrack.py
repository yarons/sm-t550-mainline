#!/usr/bin/env python3
# tonetrack.py <fs> <win_s> <f_lo> <f_hi> <step> — s16le mono stdin; per window: strongest frequency + dBFS.
import sys, math, struct
fs, win, lo, hi, step = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
raw = sys.stdin.buffer.read(); x = struct.unpack("<%dh" % (len(raw) // 2), raw[: len(raw) // 2 * 2])
W = int(fs * win); bins = []
f = lo
while f <= hi: bins.append(f); f += step
coef = [2 * math.cos(2 * math.pi * f / fs) for f in bins]
for k in range(0, len(x) - W + 1, W):
    seg = x[k:k + W]; best = (0, 0)
    for f, c in zip(bins, coef):
        s1 = s2 = 0.0
        for v in seg:
            s0 = v + c * s1 - s2; s2 = s1; s1 = s0
        p = s1 * s1 + s2 * s2 - c * s1 * s2
        if p > best[1]: best = (f, p)
    print("t=%.2fs peak %.0f Hz %.1f dBFS" % (k / fs, best[0], 20 * math.log10(2 * math.sqrt(best[1]) / W / 32768 + 1e-12)))
