#!/bin/sh
# Rear camera focus sweep: lens position -> centre sharpness (raw 1296x972).
MD=/dev/media0
LENS=$(media-ctl -d $MD -e "$(media-ctl -d $MD -p | sed -n 's/.*entity [0-9]*: \(dw9807 [^ ]*\).*/\1/p' | head -1)")
[ -n "$LENS" ] || { echo "no lens"; exit 1; }
sleep 600 < "$LENS" &          # keep the VCM powered (runtime PM) during the sweep
HOLD=$!
for pos in ${POSITIONS:-0 100 200 300 400 500 600 700 800 900 1023}; do
	v4l2-ctl -d "$LENS" -c focus_absolute=$pos
	sleep 0.2
	sh /home/user/cam/reartest.sh 1296 972 ${EXP:-1900} ${GAIN:-64} 3 48 >/dev/null 2>&1
	python3 - "$pos" <<'PY'
import sys
d = open('/tmp/rear.raw', 'rb').read(); stride, h = 1624, 972
f = d[-stride * h:]
s = n = 0
for y in range(h // 2 - 200, h // 2 + 200, 2):
    row = f[y * stride:(y + 1) * stride]
    # high bytes only (skip every 5th packed byte); compare same-colour pixels two apart
    px = [row[i] for i in range(0, 1620) if i % 5 != 4]
    c = len(px) // 2
    seg = px[c - 200:c + 200]
    for a, b in zip(seg, seg[2:]):
        s += abs(a - b); n += 1
print(f"pos {int(sys.argv[1]):5d}: sharpness {s / n:.3f}")
PY
done
kill $HOLD
