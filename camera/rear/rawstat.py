#!/usr/bin/env python3
# Mean/stddev of full 10-bit samples of packed RAW10 (last frame, sampled groups).
import sys, math
d = open(sys.argv[1], 'rb').read(); fs = int(sys.argv[2]); f = d[-fs:]
v = []
for i in range(0, len(f) - 5, 5 * 53):
    lo = f[i + 4]
    v += [(f[i] << 2) | (lo & 3), (f[i + 1] << 2) | ((lo >> 2) & 3),
          (f[i + 2] << 2) | ((lo >> 4) & 3), (f[i + 3] << 2) | (lo >> 6)]
m = sum(v) / len(v); sd = math.sqrt(sum((x - m) ** 2 for x in v) / len(v))
print(f"{sys.argv[3]}: mean {m:.2f} sd {sd:.2f} max {max(v)}")
