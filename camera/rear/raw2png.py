#!/usr/bin/env python3
"""raw2png.py RAW W H STRIDE OUT.png [ORDER] [--frame N] [--no-wb]

CSI-2 packed RAW10 Bayer (4 pixels in 5 bytes) -> half-resolution RGB PNG, stdlib only.
Each 2x2 Bayer quad becomes one pixel; gray-world white balance and sRGB gamma are applied.
Prints the mean level and the clipped fraction so exposure/gain can be tuned from it.
"""
import struct, sys, zlib

args = [a for a in sys.argv[1:] if not a.startswith('--')]
raw, w, h, stride, out = args[0], int(args[1]), int(args[2]), int(args[3]), args[4]
order = args[5] if len(args) > 5 else 'RGGB'
frame = int(sys.argv[sys.argv.index('--frame') + 1]) if '--frame' in sys.argv else 0
wb = '--no-wb' not in sys.argv
ccm = [float(v) for v in sys.argv[sys.argv.index('--ccm') + 1].split(',')] if '--ccm' in sys.argv else None
fixed = [float(v) for v in sys.argv[sys.argv.index('--wb') + 1].split(',')] if '--wb' in sys.argv else None

data = open(raw, 'rb').read()
fsize = stride * h
data = data[frame * fsize:(frame + 1) * fsize]


def row(y):
    """10-bit samples of one line (high 8 bits + packed low bits)."""
    line = data[y * stride:y * stride + w * 5 // 4]
    out = []
    for i in range(0, len(line) - 4, 5):
        lo = line[i + 4]
        out += [(line[i] << 2) | (lo & 3), (line[i + 1] << 2) | ((lo >> 2) & 3),
                (line[i + 2] << 2) | ((lo >> 4) & 3), (line[i + 3] << 2) | (lo >> 6)]
    return out


pos = {c: [] for c in 'RGB'}
for i, c in enumerate(order):          # position of each colour in the 2x2 quad
    pos[c].append((i // 2, i % 2))

hw, hh = w // 2, h // 2
planes = {'R': [], 'G': [], 'B': []}
for qy in range(hh):
    rows = (row(2 * qy), row(2 * qy + 1))
    for c in 'RGB':
        vals = []
        for qx in range(hw):
            s = 0
            for dy, dx in pos[c]:
                s += rows[dy][2 * qx + dx]
            vals.append(s / len(pos[c]))
        planes[c].append(vals)

black = 64                              # typical 10-bit pedestal
mean = {c: sum(map(sum, planes[c])) / (hw * hh) - black for c in 'RGB'}
clip = sum(1 for r in planes['G'] for v in r if v >= 1000) / (hw * hh)
print(f"mean R/G/B (minus black {black}): {mean['R']:.1f} {mean['G']:.1f} {mean['B']:.1f} "
      f"of 959, G clipped {clip * 100:.2f}%")
gain = {c: (mean['G'] / mean[c] if wb and mean[c] > 1 else 1.0) for c in 'RGB'}
if fixed:
    gain = {'R': fixed[0], 'G': 1.0, 'B': fixed[1]}
# normalise so the brightest 1% maps near white (simple auto-level for viewing)
gs = sorted(v for r in planes['G'][::4] for v in r[::4])
top = max(gs[int(len(gs) * 0.99)] - black, 1)


def enc(v):
    v = max(0.0, min(1.0, v))
    v = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return int(v * 255 + 0.5)


rows_out = bytearray()
for y in range(hh):
    rows_out.append(0)
    for x in range(hw):
        v = [(planes[c][y][x] - black) * gain[c] / top for c in 'RGB']
        if ccm:
            v = [ccm[3 * i] * v[0] + ccm[3 * i + 1] * v[1] + ccm[3 * i + 2] * v[2] for i in range(3)]
        for c in v:
            rows_out.append(enc(c))
chunk = lambda t, b: struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b))
open(out, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', hw, hh, 8, 2, 0, 0, 0))
                      + chunk(b'IDAT', zlib.compress(bytes(rows_out))) + chunk(b'IEND', b''))
print('wb gains R/B:', round(gain['R'], 2), round(gain['B'], 2))
