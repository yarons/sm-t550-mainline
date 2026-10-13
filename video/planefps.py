#!/usr/bin/env python3
# planefps.py <seconds> — sample /sys/kernel/debug/dri/0/state ~50x/s (root) and count framebuffer changes per plane
# (= frames shown on that plane), with the last pixel format and size seen on each plane, and the frame pacing:
# the longest gap between two changes and how many gaps exceeded 70 ms (= at least one frame skipped at 30 fps).
import re
import sys
import time

S = "/sys/kernel/debug/dri/0/state"
dur = float(sys.argv[1])
last, flips, info, tl = {}, {}, {}, {}
t0 = time.time()
while time.time() - t0 < dur:
    st = open(S).read()
    for m in re.finditer(r"plane\[\d+\]: (\S+)\n(.*?)(?=\nplane\[|\ncrtc\[|\Z)", st, re.S):
        name, body = m.group(1), m.group(2)
        fb = re.search(r"fb=(\d+)", body)
        fb = fb.group(1) if fb else "0"
        fmt = re.search(r"format=(\S+)", body)
        sz = re.search(r"size=(\S+)", body)
        if fb != "0":
            info[name] = "%s %s" % (fmt.group(1) if fmt else "?", sz.group(1) if sz else "?")
        if name in last and last[name] != fb:
            flips[name] = flips.get(name, 0) + 1
            tl.setdefault(name, []).append(time.time())
        last[name] = fb
    time.sleep(0.02)
for n in sorted(last):
    g = [b - a for a, b in zip(tl.get(n, []), tl.get(n, [])[1:])]
    pace = "  max gap %.0f ms, %d gaps > 70 ms" % (max(g) * 1000, sum(x > 0.07 for x in g)) if g else ""
    print("%s: %.1f fb changes/s  %s%s" % (n, flips.get(n, 0) / dur, info.get(n, "(off)"), pace))
