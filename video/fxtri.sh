#!/bin/sh
# fxtri.sh <tag> <page> ['VAR=value …'] — run fstri.sh (PAGE=<page>, bench profile, DOM fullscreen) and measure the
# ISSUES 23 black triangle in each full-resolution scanout shot: dark pixels (luma < 12) in the raw region x 200-264,
# y 760-1024 where Yaron's triangle sits (raw 768x1024, display transform 270; 90 is handled too, CROP= overrides). testsrc2 has no dark pixels there,
# so a count well above 0 means the triangle (or another black hole) is back.
T=$1; PAGE=$2; ENVS=$3
# landscape (768,512)-(1024,552) in raw scanout coordinates: transform 270 → x 200-264, y 760-1024; transform 90 → x 504-568, y 0-264
TR=$(XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 wlr-randr 2>/dev/null | awk '/Transform/ {print $2}')
case $TR in 90) CROP=${CROP:-64:264:504:0} ;; *) CROP=${CROP:-64:264:200:760} ;; esac
PAGE=$PAGE WAIT=${WAIT:-30} sh /home/user/vtest/fstri.sh "$T" "$ENVS" | tail -1
for f in /tmp/fxshot-$T-[0-9].png; do
	n=$(ffmpeg -hide_banner -loglevel error -i "$f" -vf crop=$CROP,format=gray -f rawvideo - | od -An -v -tu1 | tr -s ' ' '\n' | awk '$1 != "" && $1 < 12 {c++} END {print c+0}')
	echo "  $(basename "$f") (transform $TR, crop $CROP): dark pixels in the triangle region: $n / 16896"
done
