#!/usr/bin/env python3
"""uyvy2png.py RAW W H FRAME OUT.png [ORDER] - raw 4:2:2 frame to PNG, stdlib only.
ORDER is the byte order of one 2-pixel group, default UYVY (also YUYV, VYUY, YVYU)."""
import struct, sys, zlib
raw, w, h, n, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
order = sys.argv[6] if len(sys.argv) > 6 else "UYVY"
fs = w * h * 2
d = open(raw, "rb").read()[n * fs:(n + 1) * fs]
iy0, iy1, iu, iv = order.index("Y"), order.rindex("Y"), order.index("U"), order.index("V")
clip = lambda x: 0 if x < 0 else 255 if x > 255 else int(x)
rows = bytearray()
for y in range(h):
    rows.append(0)
    for x in range(0, w, 2):
        g = d[(y * w + x) * 2:(y * w + x) * 2 + 4]
        u, v = g[iu] - 128, g[iv] - 128
        for yy in (g[iy0], g[iy1]):
            c = 1.164 * (yy - 16)
            rows += bytes((clip(c + 1.596 * v), clip(c - 0.392 * u - 0.813 * v), clip(c + 2.017 * u)))
chunk = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))
open(out, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                      + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))
