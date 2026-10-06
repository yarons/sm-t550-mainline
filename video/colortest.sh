#!/bin/sh
# colortest.sh gen | run <601|709> <tag> — which YCbCr matrix the compositor uses for offloaded video (ISSUES 21 g).
#   gen: writes ~/vtest/ct709.mp4 and ~/vtest/ct601.mp4: 1080p H.264, 6 s, seven 75 % colour bars (red, green, blue,
#        yellow, cyan, magenta, grey) converted from RGB with the BT.709 resp. BT.601 matrix, limited range, and tagged
#        with that colorimetry (libx264, nice 19, a few seconds of CPU).
#   run: plays the clip in Showtime (Venus decode, GTK offload), grabs the composed frame with kmsgrab after 6 s and
#        prints, for each bar, the screen colour next to the two predictions: decoded with the right matrix (= the
#        source RGB) and with the other one. Showtime runs with GDK_DEBUG=offload,misc; its log (offload decisions and
#        "Setting color state ... coefficients") goes to ~/vtest/logs/colortest-<tag>.log. WAIT=<s> (default 8)
#        before the grab. PHOC=<binary> runs Showtime inside a NESTED phoc (wayland backend, a window in the session):
#        the nested phoc converts the video and hands RGB to the session's phoc, so a patched phoc is tested without
#        installing it or restarting the session.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
V=$HOME/vtest; L=$V/logs; mkdir -p $L
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
BARS="191,0,0 0,191,0 0,0,191 191,191,0 0,191,191 191,0,191 128,128,128"

case $1 in
gen)
	python3 - "$BARS" > /tmp/ct.ppm <<'EOF'
import sys
bars = [tuple(int(c) for c in b.split(",")) for b in sys.argv[1].split()]
w, h = 1920, 1080
row = bytearray()
for x in range(w):
    row += bytes(bars[min(x * len(bars) // w, len(bars) - 1)])
sys.stdout.buffer.write(b"P6 %d %d 255\n" % (w, h) + bytes(row) * h)
EOF
	for m in 709 601; do
		if [ $m = 709 ]; then mat=bt709; tag="-colorspace bt709 -color_primaries bt709 -color_trc bt709"
		else mat=bt601; tag="-colorspace smpte170m -color_primaries smpte170m -color_trc smpte170m"; fi
		nice -n 19 ffmpeg -hide_banner -loglevel error -y -loop 1 -framerate 30 -i /tmp/ct.ppm -t 6 \
			-vf "scale=in_range=pc:out_range=tv:out_color_matrix=$mat,format=yuv420p" \
			-c:v libx264 -preset ultrafast -tune stillimage $tag -color_range tv $V/ct$m.mp4 && echo "wrote $V/ct$m.mp4"
	done
	rm -f /tmp/ct.ppm
	;;
run)
	M=$2; T=$3; C=$V/ct$M.mp4; [ -f "$C" ] || { echo "no $C, run gen first"; exit 1; }
	gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
		--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
	pkill -x showtime; sleep 1
	if [ -n "$PHOC" ]; then
		systemd-run --user --unit=colortest --collect -p StandardOutput=file:$L/colortest-$T.log \
			-p StandardError=file:$L/colortest-$T.log env WAYLAND_DISPLAY=wayland-0 WLR_BACKENDS=wayland \
			"$PHOC" -E "env GDK_DEBUG=offload,misc showtime $C" >/dev/null 2>&1
	else
		systemd-run --user --unit=colortest --collect -p StandardOutput=file:$L/colortest-$T.log \
			-p StandardError=file:$L/colortest-$T.log env GDK_DEBUG=offload,misc showtime "$C" >/dev/null 2>&1
	fi
	sleep ${WAIT:-8}
	S ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
		-vf hwdownload,format=bgr0,format=rgb24 -frames:v 1 -f rawvideo /tmp/ct-$T.rgb 2>/dev/null
	S chmod 644 /tmp/ct-$T.rgb
	systemctl --user stop colortest 2>/dev/null; pkill -x showtime
	python3 - "$BARS" "$M" /tmp/ct-$T.rgb <<'EOF'
import sys, collections
bars = [tuple(int(c) for c in b.split(",")) for b in sys.argv[1].split()]
m = sys.argv[2]
data = open(sys.argv[3], "rb").read()
K = {"709": (0.2126, 0.0722), "601": (0.299, 0.114)}
def enc(rgb, k):  # RGB 0-255 full -> limited-range Y'CbCr (8 bit, rounded like the encoder)
    kr, kb = k; kg = 1 - kr - kb
    r, g, b = (c / 255 for c in rgb)
    y = kr * r + kg * g + kb * b
    return (round(16 + 219 * y), round(128 + 224 * (b - y) / (2 * (1 - kb))), round(128 + 224 * (r - y) / (2 * (1 - kr))))
def dec(ycc, k):
    kr, kb = k; kg = 1 - kr - kb
    y = (ycc[0] - 16) / 219; cb = (ycc[1] - 128) / 224; cr = (ycc[2] - 128) / 224
    r = y + 2 * (1 - kr) * cr; b = y + 2 * (1 - kb) * cb; g = (y - kr * r - kb * b) / kg
    return tuple(max(0, min(255, round(255 * c))) for c in (r, g, b))
other = "601" if m == "709" else "709"
# Most common screen colours (every 3rd pixel); the bars dominate.
cnt = collections.Counter(data[i:i + 3] for i in range(0, len(data) - 2, 9))
top = [tuple(c) for c, n in cnt.most_common(40)]
def dist(a, b): return max(abs(x - y) for x, y in zip(a, b))
print(f"clip BT.{m}: screen colour (nearest of the 40 most common) vs decode with BT.{m} / BT.{other}")
ok = bad = 0
for rgb in bars:
    ycc = enc(rgb, K[m]); right = dec(ycc, K[m]); wrong = dec(ycc, K[other])
    near = min(top, key=lambda c: min(dist(c, right), dist(c, wrong)))
    dr, dw = dist(near, right), dist(near, wrong)
    verdict = f"BT.{m}" if dr < dw else (f"BT.{other}" if dw < dr else "?")
    ok += dr < dw; bad += dw < dr
    print(f"  bar {str(rgb):15} screen {str(near):15} BT.{m} {str(right):15} (d {dr:2})  BT.{other} {str(wrong):15} (d {dw:2})  -> {verdict}")
print(f"RESULT: {ok} bars match BT.{m}, {bad} match BT.{other}")
EOF
	grep -cE "offload.*(fail|refus|No )" $L/colortest-$T.log | sed 's/^/offload refusals in log: /'
	grep -m3 -E "Setting color state|coefficients" $L/colortest-$T.log
	;;
*) sed -n 2,9p "$0"; exit 1 ;;
esac
