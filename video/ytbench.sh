#!/bin/sh
# ytbench.sh <url> <tag> [secs] [ENV=val …] — play a URL (YouTube via clapper-enhancers' yt-dlp) in Clapper, which uses
# libclapper-gtk like Pipeline, and measure a <secs> window (default 40) after playback starts: frames shown per second
# (planefps.py, 6 s), Clapper CPU % of one core, total CPU % of 400, memory pressure (PSI "some" share of the window),
# MemAvailable, swap used, Venus decoder fds and which video sink ran (libgstgtk4.so mapped = gtk4paintablesink,
# libgstclapper.so = clappersink via glsinkbin). Clapper runs with GDK_DEBUG=offload; log ~/vtest/logs/ytbench-<tag>.log.
# ISSUES 21 (i). Run as the session user (sudo password <password> for planefps).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name)")")
U=$1; T=$2; D=${3:-40}; shift 2; [ $# -gt 0 ] && shift
L=$HOME/vtest/logs/ytbench-$T.log; mkdir -p "$HOME/vtest/logs"
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
pkill -x clapper; sleep 1
systemd-run --user --unit=ytb-$T --collect -p StandardOutput=file:$L -p StandardError=file:$L \
	env GDK_DEBUG=offload "$@" clapper "$U" >/dev/null 2>&1
t0=$(date +%s); P=; n=0
while [ $(( $(date +%s) - t0 )) -lt 90 ]; do  # yt-dlp extraction + buffering
	P=$(pgrep -x clapper | head -1)
	[ -n "$P" ] && n=$(ls -l /proc/$P/fd 2>/dev/null | grep -c "$VDEC")
	[ "${n:-0}" -gt 0 ] && break
	sleep 1
done
start=$(( $(date +%s) - t0 ))
[ "${n:-0}" -gt 0 ] || { echo "$T: no Venus decoder after 90 s (log $L)"; systemctl --user stop ytb-$T; exit 1; }
sleep 8
cpu() { awk '/^cpu / {print $2+$3+$4+$7+$8+$9, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat; }
psi() { awk '/^some/ {sub("total=", "", $5); print $5}' /proc/pressure/memory; }
set -- $(cpu); b0=$1; c0=$2; p0=$(awk '{print $14+$15}' /proc/$P/stat); m0=$(psi); s0=$(date +%s)
fps=$(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 $HOME/vtest/planefps.py 6 | awk '/plane-0/ {print $2}')
while [ $(( $(date +%s) - s0 )) -lt "$D" ]; do sleep 1; done
set -- $(cpu); el=$(( $(date +%s) - s0 )); p1=$(awk '{print $14+$15}' /proc/$P/stat 2>/dev/null || echo $p0); m1=$(psi)
sink=other; grep -q libgstgtk4 /proc/$P/maps 2>/dev/null && sink=gtk4paintablesink
grep -q libgstclapper.so /proc/$P/maps 2>/dev/null && sink="clappersink${sink#other}"
ma=$(awk '/MemAvailable/ {print int($2 / 1024)}' /proc/meminfo)
sw=$(awk '/SwapTotal/ {t = $2} /SwapFree/ {f = $2} END {print int((t - f) / 1024)}' /proc/meminfo)
ref=$(grep -ciE "offload.*(fail|refus|not)|Only textures" "$L")
awk -v tag=$T -v b=$(( $1 - b0 )) -v t=$(( $2 - c0 )) -v p=$((p1 - p0)) -v el=$el -v fps=${fps:-?} -v m=$(( m1 - m0 )) \
	-v ma=$ma -v sw=$sw -v start=$start -v sink="$sink" -v ref=$ref 'BEGIN {
	printf "%s: decoder after %d s; shown %s fps; clapper %.0f %% of a core; CPU %.0f %% of 400; memory PSI some %.1f %%; MemAvailable %d MB; swap used %d MB; sink %s; offload refusal lines %d\n",
		tag, start, fps, 100 * p / 100 / el, 400 * b / t, 100 * m / (el * 1e6), ma, sw, sink, ref }'
systemctl --user stop ytb-$T 2>/dev/null; pkill -x clapper
