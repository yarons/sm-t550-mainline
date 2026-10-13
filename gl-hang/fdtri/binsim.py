# Port of Mesa 26.2.4 freedreno_gmem.c calc_nbins/layout_gmem/pipe setup for FD307 (a306): GMEM 128 KiB,
# tile_align 32x32, tile_max_w 992, tile_max_h max_bitfield_val(9,5,5)=(2^5-1)<<5=992, 8 VSC pipes, page align 4 KiB.
import math, sys
GMEM = 128 * 1024; TAW = TAH = 32; TMW = 992; TMH = 31 << 5; NP = 8; PAGE = 1 * 0x1000
def div_align(n, d, al): return -(-(-(-n // d)) // al) * al
def layout(w, h, cpps, nx, ny):
    bw, bh = div_align(w, nx, TAW), div_align(h, ny, TAH)
    if bw > TMW or bh > TMH: return None
    total = 0
    for c in cpps:
        base = -(-total // PAGE) * PAGE; total = base + c * bw * bh
    return (bw, bh, -(-w // bw), -(-h // bh)) if total <= GMEM else None
def calc(w, h, cpps):
    nx = ny = 1
    while div_align(w, nx, TAW) > TMW: nx += 1
    while div_align(h, ny, TAH) > TMH: ny += 1
    while not layout(w, h, cpps, nx, ny):
        if ny > nx: nx += 1
        else: ny += 1
    if (nx - 1) * (ny + 1) < nx * ny and layout(w, h, cpps, nx - 1, ny + 1): nx, ny = nx - 1, ny + 1
    elif (nx + 1) * (ny - 1) < nx * ny and layout(w, h, cpps, nx + 1, ny - 1): nx, ny = nx + 1, ny - 1
    bw, bh, nbx, nby = layout(w, h, cpps, nx, ny)
    tx = ty = 1
    while -(-nby // ty) > NP: ty += 2
    while -(-nby // ty) * -(-nbx // tx) > NP: tx += 1
    hw = (tx * ty <= 32) and tx <= 15 and ty <= 15 and nbx * nby > 2
    return bw, bh, nbx, nby, tx, ty, hw
for (w, h, cpps, what) in [(1024, 512, [4, 4], "tile RT RGBA8 + Z24S8"), (1024, 512, [4], "tile RT RGBA8 only"),
                           (1024, 768, [4], "window RGBA8"), (1024, 768, [4, 4], "window RGBA8 + depth")] + \
                          [(int(a), int(b), [4, 4], "custom") for a, b in [x.split("x") for x in sys.argv[1:]]]:
    bw, bh, nbx, nby, tx, ty, hw = calc(w, h, cpps)
    print(f"{w}x{h} {what}: bins {nbx}x{nby} of {bw}x{bh}, pipes of {tx}x{ty} bins ({tx*bw}x{ty*bh} px), hw binning {hw}")
    print("   bin x edges:", [i * bw for i in range(nbx + 1)], " pipe x edges:", [i * tx * bw for i in range(-(-nbx // tx) + 1)])
