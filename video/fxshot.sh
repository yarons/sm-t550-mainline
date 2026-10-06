#!/bin/sh
# fxshot.sh <url> <tag> <hw 1|0> [shots] — Firefox (persistent bench profile) plays <url> with hardware decoding
# forced (1) or disabled (0); after 15 s, grabs <shots> screenshots back to back (kmsgrab, 256 px wide) into
# /tmp/fxshot-<tag>-strip.png to look for corruption. EXTRA='user_pref(...);' adds one more pref; FFLIB=<dir> runs Firefox with LD_LIBRARY_PATH=<dir> (test libavcodec builds). Venus open + Firefox CPU are printed.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
U=$1; T=$2; HW=$3; N=${4:-8}
P=/home/user/.cache/fxbench-prof
pgrep -f firefox-esr >/dev/null && { echo "Firefox is already running — close it first"; exit 1; }
if [ "$HW" = 1 ]; then v=true; else v=false; fi
printf 'user_pref("media.hardware-video-decoding.force-enabled", %s);\nuser_pref("media.hardware-video-decoding.enabled", %s);\n' $v $v > $P/user.js
[ -n "$EXTRA" ] && echo "$EXTRA" >> $P/user.js
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null 2>&1
if [ -n "$FFLIB" ]; then
	# Firefox restarts itself once with a changed library path; under systemd-run that first exit stops the unit.
	WAYLAND_DISPLAY=wayland-0 LD_LIBRARY_PATH=$FFLIB setsid nohup firefox-esr --no-remote --profile $P "$U" >/dev/null 2>&1 &
else
	systemd-run --user --unit=fxshot-$T --collect firefox-esr --no-remote --profile $P "$U" >/dev/null 2>&1
fi
sleep 15
venus=0; for p in $(pgrep -f firefox-esr); do venus=$((venus + $(ls -l /proc/$p/fd 2>/dev/null | grep -c /dev/video5))); done
echo "${SUDO_PW:-147147}" | sudo -S -p "" rm -f /tmp/fxshot-$T-*.png
i=1; while [ $i -le $N ]; do
	echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
		-vf hwdownload,format=bgr0,scale=256:-1 -frames:v 1 /tmp/fxshot-$T-$i.png
	i=$((i + 1))
done
echo "${SUDO_PW:-147147}" | sudo -S -p "" sh -c "chmod 644 /tmp/fxshot-$T-*.png"
in=""; i=1; while [ $i -le $N ]; do in="$in -i /tmp/fxshot-$T-$i.png"; i=$((i + 1)); done
ffmpeg -hide_banner -loglevel error -y $in -filter_complex hstack=inputs=$N /tmp/fxshot-$T-strip.png
lavc=$(for p in $(pgrep -f firefox-esr); do grep -ho "/[^ ]*libavcodec\.so[.0-9]*" /proc/$p/maps 2>/dev/null; done | sort -u | tr "\n" " ")
echo "$T: hw=$HW venus fds=$venus lavc=[$lavc]"
systemctl --user stop fxshot-$T 2>/dev/null
for p in $(pgrep -f "profile $P"); do kill $p 2>/dev/null; done; sleep 2; rm -f $P/user.js
