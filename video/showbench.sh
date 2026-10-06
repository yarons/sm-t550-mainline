#!/bin/sh
# showbench.sh <clip> <tag> [ENV=val …] — play a clip in GNOME Showtime and measure: MPRIS PlaybackStatus (Play is
# sent if needed), Venus decoder open, Showtime CPU % of one core, frames shown per DRM plane (planefps.py), and a
# downscaled kmsgrab screenshot /tmp/showbench-<tag>.png. Run as the session user (sudo password <password> for debugfs).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name)")")  # node numbers move between boots
C=$1; T=$2; shift 2
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
systemd-run --user --unit=showtime-$T --collect env "$@" showtime "$C" >/dev/null 2>&1
sleep 5
M=$(busctl --user list 2>/dev/null | awk '/org.mpris.MediaPlayer2/ && /howtime/ {print $1; exit}')
st() { gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 --method org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | tr -d "()<>',"; }
s0=$(st)
case "$s0" in *Playing*) ;; *) gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 --method org.mpris.MediaPlayer2.Player.Play >/dev/null 2>&1; sleep 2;; esac
P=$(pgrep -x showtime | head -1)
venus=$(ls -l /proc/$P/fd 2>/dev/null | grep -c "$VDEC")
u0=$(awk '{print $14+$15}' /proc/$P/stat)
PF=$(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 ~/vtest/planefps.py 6 | grep -v "(off)" | tr "\n" ";")
u1=$(awk '{print $14+$15}' /proc/$P/stat)
echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
	-vf hwdownload,format=bgr0,scale=384:-1 -frames:v 1 /tmp/showbench-$T.png
echo "${SUDO_PW:-147147}" | sudo -S -p "" chmod 644 /tmp/showbench-$T.png
echo "$T: mpris=${M:-none} status ${s0:-?} -> $(st)  venus fds=$venus  showtime CPU $(( (u1 - u0) / 6 ))%  planes: $PF"
systemctl --user stop showtime-$T 2>/dev/null; pkill -x showtime; sleep 2
