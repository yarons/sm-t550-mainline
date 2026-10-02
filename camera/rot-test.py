#!/usr/bin/env python3
# Offscreen check of GTK's cairo renderer on a 90/270-degree rotated, scaled texture:
# a quadrant pattern must land where plain affine math says, and we time it.
import time, gi
gi.require_version('Gsk', '4.0'); gi.require_version('Gdk', '4.0'); gi.require_version('Graphene', '1.0')
from gi.repository import Gsk, Gdk, Graphene, GLib

W, H = 800, 600
px = bytearray(W * H * 4)
for y in range(H):
    for x in range(W):
        q = (x >= W // 2) + 2 * (y >= H // 2)          # 0 TL red, 1 TR green, 2 BL blue, 3 BR white
        c = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)][q]
        i = (y * W + x) * 4
        px[i:i + 4] = bytes((c[2], c[1], c[0], 255))   # B8G8R8A8 premultiplied
tex = Gdk.MemoryTexture.new(W, H, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, GLib.Bytes.new(bytes(px)), W * 4)

r = Gsk.CairoRenderer.new(); r.realize(None)
OW, OH = 732, 976                                        # portrait preview box
for angle, mirror in ((90, 1), (89.99, 1), (90, -1), (89.99, -1), (270, -1), (269.99, -1)):
    node = Gsk.TextureNode.new(tex, Graphene.Rect().init(0, 0, OH, OW))   # texture laid out landscape
    t = Gsk.Transform.new().translate(Graphene.Point().init(OW / 2, OH / 2)).rotate(angle) \
        .scale(mirror, 1).translate(Graphene.Point().init(-OH / 2, -OW / 2))
    tnode = Gsk.TransformNode.new(node, t)
    vp = Graphene.Rect().init(0, 0, OW, OH)
    out = r.render_texture(tnode, vp)
    t0 = time.monotonic()
    for _ in range(10):
        out = r.render_texture(tnode, vp)
    ms = (time.monotonic() - t0) * 100
    d = Gdk.TextureDownloader.new(out); d.set_format(Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED)
    b, stride = d.download_bytes(); b = b.get_data()
    def at(x, y):
        i = y * stride + x * 4; return (b[i + 2], b[i + 1], b[i])
    corners = [at(40, 40), at(OW - 40, 40), at(40, OH - 40), at(OW - 40, OH - 40)]
    print(f"rot{angle:g} mirror={mirror}: {ms:.1f} ms/frame corners TL,TR,BL,BR = {corners}")
r.unrealize()
