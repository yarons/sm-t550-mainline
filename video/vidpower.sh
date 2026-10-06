#!/bin/sh
# vidpower.sh <clip> [secs] — battery current and CPU while GNOME Showtime plays <clip>, per playback path:
#   idle (screen on, nothing playing) · venus (hardware decode, GTK offload) · venus-nooffload (GDK_DISABLE=offload:
#   GTK draws the frames itself) · sw (avdec_h264, offload) · idle again.
# Each phase: <secs> (default 40) with the first 8 s discarded; reports battery current (mA, from the gauge's
# current_now, discharge positive), total CPU % (of 400), Showtime CPU % (of one core), frames shown per second
# (planefps.py, 6 s) and backlight level. Needs the tablet UNPLUGGED (refuses while charging); auto-brightness is
# switched off for the run and restored. Showtime runs from the patched copy (PYTHONPATH=~/vtest/st).
# Run as a user unit: systemd-run --user --unit=vidpower --collect ~/vtest/vidpower.sh <clip>; log ~/vtest/logs/vidpower.txt
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
C=$1; D=${2:-40}; L=$HOME/vtest/logs; O=$L/vidpower.txt; mkdir -p $L; : > $O
B=/sys/class/power_supply/max170xx_battery; BL=$(ls -d /sys/class/backlight/* | head -1)
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
log() { echo "$*" | tee -a $O; }
[ "$(cat $B/status)" = Charging ] && { log "refusing: battery is charging, unplug the tablet"; exit 1; }
amb0=$(gsettings get org.gnome.settings-daemon.plugins.power ambient-enabled 2>/dev/null)
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false 2>/dev/null
trap 'gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled ${amb0:-true}; pkill -x showtime' EXIT
unblank() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
cpu() { awk '/^cpu / {print $2+$3+$4+$7+$8+$9, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat; }  # busy, total (idle+iowait not busy)
phase() {  # phase <tag> [ENV=val …] — "-" as the first env = no Showtime (idle)
	tag=$1; shift; unblank
	if [ "$1" != - ]; then
		systemd-run --user --unit=vp-$tag --collect env PYTHONPATH=$HOME/vtest/st "$@" showtime "$C" >/dev/null 2>&1
		M=; i=0
		while [ -z "$M" ] && [ $i -lt 20 ]; do sleep 1; i=$((i + 1))
			M=$(busctl --user list 2>/dev/null | awk '/org.mpris.MediaPlayer2/ && /howtime/ {print $1; exit}'); done
		st=$(gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 --method org.freedesktop.DBus.Properties.Get \
			org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | tr -d "()<>',")
		case "$st" in *Playing*) ;; *) gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 \
			--method org.mpris.MediaPlayer2.Player.Play >/dev/null 2>&1;; esac
	fi
	sleep 8
	P=$(pgrep -x showtime | head -1); venus=0; [ -n "$P" ] && venus=$(ls -l /proc/$P/fd 2>/dev/null | grep -c /dev/video5)
	set -- $(cpu); b0=$1; t0=$2; p0=0; [ -n "$P" ] && p0=$(awk '{print $14+$15}' /proc/$P/stat)
	sum=0; n=0; s0=$(date +%s)
	fps=$(S python3 $HOME/vtest/planefps.py 6 | awk '/plane-0/ {print $2}')
	while [ $(( $(date +%s) - s0 )) -lt $((D - 8)) ]; do
		sum=$((sum + $(cat $B/current_now))); n=$((n + 1)); sleep 1
	done
	set -- $(cpu); el=$(( $(date +%s) - s0 )); p1=0; [ -n "$P" ] && p1=$(awk '{print $14+$15}' /proc/$P/stat)
	awk -v tag=$tag -v sum=$sum -v n=$n -v b=$(( $1 - b0 )) -v t=$(( $2 - t0 )) -v p=$((p1 - p0)) -v el=$el -v fps=${fps:-?} \
		-v v=$venus -v bl=$(cat $BL/brightness) -v cap=$(cat $B/capacity) 'BEGIN {
		printf "%-16s %6.0f mA  CPU %5.1f %% of 400  showtime %5.1f %%  shown %s fps  venus fds %d  backlight %d  battery %d %%\n",
			tag, -sum / n / 1000, 400 * b / t, 100 * p / 100 / el, fps, v, bl, cap }' | tee -a $O
	[ -n "$P" ] && { systemctl --user stop vp-$tag 2>/dev/null; pkill -x showtime; sleep 3; }
}
log "== vidpower $(date +%T) clip $C, $D s per phase, $(uname -v | cut -c1-40)"
phase idle -
phase venus GST_DEBUG=0
phase venus-nooffload GDK_DISABLE=offload
phase sw GST_PLUGIN_FEATURE_RANK=v4l2h264dec:NONE
phase idle2 -
log "DONE"
