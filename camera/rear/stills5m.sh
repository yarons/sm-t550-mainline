#!/bin/sh
# stills5m.sh [frames] — rear SR544 through libcamera's soft ISP at full 2592x1944 vs the 1296x972 preview mode:
# delivered fps (cam's per-frame "(xx.xx fps)") and CPU % of one core, with the output cap lifted for THIS process
# only (XDG_CONFIG_HOME → a copy of /etc/libcamera/configuration.yaml without max_output_*). Timing runs write no
# files (a 5 MP XRGB frame is 20 MB; /tmp is RAM); then ONE frame per mode goes to ~/vtest/cam/<tag>.bin (3 frames
# captured, the first two deleted). Run as the session user with the camera idle (no Snapshot).
N=${1:-30}
export XDG_RUNTIME_DIR=/run/user/$(id -u)
C=/tmp/stills5m-conf; mkdir -p $C/libcamera
grep -v -E "max_output_(width|height)" /etc/libcamera/configuration.yaml > $C/libcamera/configuration.yaml
CAM=$(cam -l 2>/dev/null | grep -i -m1 -E "back|sr544" | sed -E 's/^ *([0-9]+):.*/\1/')
echo "rear camera index: ${CAM:-?}"
run() { # W H tag
	s0=$(date +%s.%N); c0=$(awk '{print $16+$17}' /proc/$$/stat)
	XDG_CONFIG_HOME=$C cam -c "$CAM" -s width=$1,height=$2,role=still --capture="$N" > /tmp/stills5m-$3.log 2>&1
	s1=$(date +%s.%N); c1=$(awk '{print $16+$17}' /proc/$$/stat)
	n=$(grep -c "seq:" /tmp/stills5m-$3.log)
	fps=$(grep -o "([0-9.]* fps)" /tmp/stills5m-$3.log | tr -d "(fps)" | tail -n +3 | awk '{s+=$1; c++} END {printf "%.1f", c ? s/c : 0}')
	cfg=$(grep -m1 -E "^Using camera|configuration" /tmp/stills5m-$3.log)
	echo "$3: $n frames, mean $fps fps (frames 3+), wall $(echo "$s1 $s0" | awk '{printf "%.1f", $1-$2}') s, CPU $(( (c1 - c0) * 100 / 100 )) ticks (cam, 100/s); $cfg"
	grep -i -E "error|warn|fail" /tmp/stills5m-$3.log | sort | uniq -c | head -4
	mkdir -p ~/vtest/cam; rm -f ~/vtest/cam/$3-*
	XDG_CONFIG_HOME=$C cam -c "$CAM" -s width=$1,height=$2,role=still --capture=3 --file="$HOME/vtest/cam/$3-#.bin" >/dev/null 2>&1
	f=$(ls ~/vtest/cam/$3-* 2>/dev/null | tail -1); [ -n "$f" ] && { mv "$f" ~/vtest/cam/$3.bin; rm -f ~/vtest/cam/$3-*; }
	ls -la ~/vtest/cam/$3.bin 2>/dev/null | awk '{print "   frame:", $NF, $5, "bytes"}'
}
run 1296 972 m1296
run 2592 1944 m5m
