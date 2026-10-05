#!/usr/bin/env python3
# goertzel.py <fs> <f_lo> <f_hi> <step> — read s16le mono from stdin, print the strongest frequency in [f_lo, f_hi]
# and its level relative to full scale (Goertzel per bin; nothing stored beyond the samples in memory).
import sys, math, struct
fs, lo, hi, step = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
raw = sys.stdin.buffer.read()
x = struct.unpack("<%dh" % (len(raw) // 2), raw[: len(raw) // 2 * 2])
n = len(x); best = (0, 0)
f = lo
while f <= hi:
    w = 2 * math.pi * f / fs; c = 2 * math.cos(w); s1 = s2 = 0.0
    for v in x:
        s0 = v + c * s1 - s2; s2 = s1; s1 = s0
    p = s1 * s1 + s2 * s2 - c * s1 * s2
    if p > best[1]: best = (f, p)
    f += step
amp = 2 * math.sqrt(best[1]) / n / 32768
print("peak %.2f Hz, %.1f dBFS, %d samples" % (best[0], 20 * math.log10(amp + 1e-12), n))
