#!/usr/bin/env python3
# Mean of the high 8 bits of packed RAW10 (skips every 5th byte), last frame, sampled.
import sys
d = open(sys.argv[1], 'rb').read(); fs = int(sys.argv[2])
f = d[-fs:]
s = n = 0
for i in range(0, len(f) - 5, 5 * 97):
    s += f[i] + f[i + 1] + f[i + 2] + f[i + 3]; n += 4
print(f"{sys.argv[3]}: mean10 {4 * s / n:.1f}")
