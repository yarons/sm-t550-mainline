#!/usr/bin/env python3
"""Mean R G B of rectangles of the tablet's screen (raw screencap over adb) or of a BMP file.

    patch-means.py <serial|file.bmp> name:x,y,w,h [name:x,y,w,h ...]

For a JPEG photo: sips -s format bmp photo.jpg --out photo.bmp first. Pure Python.
"""
import struct
import subprocess
import sys


def load(source):
    if source.lower().endswith('.bmp'):
        d = open(source, 'rb').read()
        off, = struct.unpack_from('<I', d, 10)
        w, h = struct.unpack_from('<ii', d, 18)
        bpp, = struct.unpack_from('<H', d, 28)
        n = bpp // 8
        stride = (w * n + 3) & ~3
        flip = h > 0
        h = abs(h)

        def px(x, y):
            yy = h - 1 - y if flip else y
            o = off + yy * stride + x * n
            return d[o + 2], d[o + 1], d[o]
        return w, h, px
    raw = subprocess.run(['adb', '-s', source, 'exec-out', 'screencap'], capture_output=True, timeout=60).stdout
    w, h, _ = struct.unpack_from('<3I', raw, 0)
    off = len(raw) - w * h * 4

    def px(x, y):
        o = off + (y * w + x) * 4
        return raw[o], raw[o + 1], raw[o + 2]
    return w, h, px


w, h, px = load(sys.argv[1])
print(f'image {w}x{h}')
for spec in sys.argv[2:]:
    name, rect = spec.split(':')
    x0, y0, rw, rh = (int(v) for v in rect.split(','))
    r = g = b = n = 0
    for y in range(y0, min(h, y0 + rh), 2):
        for x in range(x0, min(w, x0 + rw), 2):
            pr, pg, pb = px(x, y)
            r += pr
            g += pg
            b += pb
            n += 1
    print(f'{name:10s} R {r / n:5.1f}  G {g / n:5.1f}  B {b / n:5.1f}')
