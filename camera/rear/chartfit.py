#!/usr/bin/env python3
"""chartfit.py RAW FRAME - measure the test-chart patches in a 2592x1944 BGGR RAW10 capture
(half-res quad coordinates, black level 64) and fit white balance + a 3x3 colour matrix
from camera RGB to linear sRGB, the way libcamera's simple IPA applies them (WB gains
first, then the CCM on white-balanced linear RGB)."""
import sys

W, H, STRIDE, BLACK = 2592, 1944, 3240, 64
data = open(sys.argv[1], 'rb').read()
frame = int(sys.argv[2]) if len(sys.argv) > 2 else 0
data = data[frame * STRIDE * H:(frame + 1) * STRIDE * H]


def sample(x, y):
    lo = data[y * STRIDE + (x // 4) * 5 + 4]
    b = data[y * STRIDE + (x // 4) * 5 + (x % 4)]
    return (b << 2) | ((lo >> (2 * (x % 4))) & 3)


def quad(qx, qy):
    """BGGR quad at half-res (qx, qy) -> linear (R, G, B) minus black."""
    x, y = 2 * qx, 2 * qy
    b = sample(x, y)
    g = (sample(x + 1, y) + sample(x, y + 1)) / 2
    r = sample(x + 1, y + 1)
    return r - BLACK, g - BLACK, b - BLACK


def box(cx, cy, r=14):
    acc = [0.0, 0.0, 0.0]; n = 0
    for qy in range(cy - r, cy + r, 2):
        for qx in range(cx - r, cx + r, 2):
            p = quad(qx, qy)
            for i in range(3):
                acc[i] += p[i]
            n += 1
    return [a / n for a in acc]


def lin(v):  # sRGB 8-bit -> linear 0..1
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


# (name, target sRGB, half-res centre) read off the rotated chart image
patches = [
    ('grey255', (255, 255, 255), (295, 45)), ('grey230', (230, 230, 230), (295, 125)),
    ('grey204', (204, 204, 204), (295, 210)), ('grey179', (179, 179, 179), (295, 300)),
    ('grey153', (153, 153, 153), (295, 405)), ('grey128', (128, 128, 128), (295, 510)),
    ('grey102', (102, 102, 102), (295, 625)), ('grey77', (77, 77, 77), (295, 745)),
    ('yellow', (255, 255, 0), (460, 90)), ('magenta', (255, 0, 255), (460, 255)),
    ('cyan', (0, 255, 255), (460, 440)), ('blue', (0, 0, 255), (460, 635)),
    ('green', (0, 255, 0), (460, 830)),
    ('lime', (157, 188, 64), (680, 125)), ('purple', (94, 60, 108), (680, 290)),
    ('orange', (214, 126, 44), (680, 455)), ('foliage', (87, 108, 67), (690, 625)),
    ('sky', (98, 122, 157), (700, 795)),
    ('white', (255, 255, 255), (830, 650)), ('black', (0, 0, 0), (845, 880)),
]

meas = {}
for name, tgt, (cx, cy) in patches:
    meas[name] = box(cx, cy)
    r, g, b = meas[name]
    print(f'{name:9s} cam R {r:7.1f} G {g:7.1f} B {b:7.1f}   target {tgt}')

# White balance from the neutral patches (exclude near-clipped and near-black ones)
neutral = [n for n in meas if n.startswith('grey') or n == 'white']
sr = sum(meas[n][0] for n in neutral); sg = sum(meas[n][1] for n in neutral); sb = sum(meas[n][2] for n in neutral)
gr, gb = sg / sr, sg / sb
print(f'\nWB gains (G=1): R {gr:.3f} B {gb:.3f}')

# Exposure normalisation: map the white patch's green to 1.0 linear
scale = 1.0 / meas['white'][1]
colour = [n for n, _, _ in patches if n not in ('black',)]
X = []; Y = []
for name, tgt, _ in patches:
    if name not in colour:
        continue
    r, g, b = meas[name]
    X.append((r * gr * scale, g * scale, b * gb * scale))
    Y.append(tuple(lin(t) for t in tgt))

# Least squares CCM: Y = M X, solved per output channel via 3x3 normal equations
def solve3(A, y):
    import copy
    m = [row[:] + [y[i]] for i, row in enumerate(A)]
    for c in range(3):
        p = max(range(c, 3), key=lambda k: abs(m[k][c])); m[c], m[p] = m[p], m[c]
        for k in range(3):
            if k != c:
                f = m[k][c] / m[c][c]
                m[k] = [a - f * b for a, b in zip(m[k], m[c])]
    return [m[i][3] / m[i][i] for i in range(3)]

XtX = [[sum(x[i] * x[j] for x in X) for j in range(3)] for i in range(3)]
M = []
for ch in range(3):
    Xty = [sum(x[i] * y[ch] for x, y in zip(X, Y)) for i in range(3)]
    M.append(solve3(XtX, Xty))
# keep neutrals neutral: rows sum to 1
M = [[v / sum(row) for v in row] for row in M]
print('\nCCM (rows sum to 1):')
for row in M:
    print('  ', ', '.join(f'{v:6.3f}' for v in row))

err = 0
for x, y in zip(X, Y):
    p = [sum(M[c][i] * x[i] for i in range(3)) for c in range(3)]
    err += sum((a - b) ** 2 for a, b in zip(p, y))
print(f'RMS error (linear): {(err / (3 * len(X))) ** 0.5:.3f}')

# --- Chromaticity-only refit: vignetting and screen viewing angle make patch
# intensities unreliable, so give every patch its own scale and alternate
# between fitting the CCM and the per-patch scales.
names = [n for n, _, _ in patches if n not in ('black',) and not n.startswith('grey')] + ['grey153', 'grey128']
Xc = []; Yc = []
for name, tgt, _ in patches:
    if name in names:
        r, g, b = meas[name]
        Xc.append([r * gr, g, b * gb])
        Yc.append([lin(t) for t in tgt])
s = [1.0 / max(1e-6, sum(x) / 3) * (sum(y) / 3) for x, y in zip(Xc, Yc)]
for it in range(60):
    Xs = [[v * si for v in x] for x, si in zip(Xc, s)]
    XtX = [[sum(x[i] * x[j] for x in Xs) for j in range(3)] for i in range(3)]
    M2 = []
    for ch in range(3):
        Xty = [sum(x[i] * y[ch] for x, y in zip(Xs, Yc)) for i in range(3)]
        M2.append(solve3(XtX, Xty))
    M2 = [[v / sum(row) for v in row] for row in M2]
    # best scale per patch for this matrix
    for k, (x, y) in enumerate(zip(Xc, Yc)):
        p = [sum(M2[c][i] * x[i] for i in range(3)) for c in range(3)]
        pp = sum(a * a for a in p)
        s[k] = sum(a * b for a, b in zip(p, y)) / pp if pp > 0 else s[k]
err = 0
for x, y, si in zip(Xc, Yc, s):
    p = [si * sum(M2[c][i] * x[i] for i in range(3)) for c in range(3)]
    err += sum((a - b) ** 2 for a, b in zip(p, y))
print('\nCCM, chromaticity fit (rows sum to 1):')
for row in M2:
    print('  ', ', '.join(f'{v:6.3f}' for v in row))
print(f'RMS error (linear, per-patch scaled): {(err / (3 * len(Xc))) ** 0.5:.3f}')
