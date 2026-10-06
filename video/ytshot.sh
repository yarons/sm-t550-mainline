#!/bin/sh
# ytshot.sh <youtube url> <tag> <hw 1|0> [shots] — YouTube in the persistent bench profile: start page = the URL
# (Firefox's self-relaunch drops URL arguments), H.264 via the system prefs, HW decode forced (1) or off (0); after
# 35 s (autoplay allowed by pref) press F11 / f (fullscreen) with wtype, wait 12 s, then <shots> scanout screenshots (384 px wide strip
# /tmp/ytshot-<tag>-strip.png) plus full-resolution crops of the region where the black triangle shows
# (raw 768x1024 scanout x 408-768, y 0-260; /tmp/ytshot-<tag>-tri.png). EXTRA='user_pref(...);' adds a pref; REQ=<n> sets GT510_V4L2_REQUEUE_DELAY (ffmpeg r103+).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus WAYLAND_DISPLAY=wayland-0
U=$1; T=$2; HW=$3; N=${4:-6}; P=/home/user/.cache/fxbench-prof
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name | head -1)")")
pgrep -x firefox-esr >/dev/null && { echo "Firefox is already running — close it first"; exit 1; }
if [ "$HW" = 1 ]; then v=true; else v=false; fi
{ printf 'user_pref("media.hardware-video-decoding.force-enabled", %s);\nuser_pref("media.hardware-video-decoding.enabled", %s);\n' $v $v
  printf 'user_pref("browser.sessionstore.resume_from_crash", false);\nuser_pref("media.autoplay.default", 0);\nuser_pref("media.autoplay.blocking_policy", 0);\n'
  printf 'user_pref("toolkit.startup.max_resumed_crashes", -1);\nuser_pref("browser.startup.page", 1);\nuser_pref("browser.startup.homepage", "%s");\n' "$U"
  [ -n "$EXTRA" ] && echo "$EXTRA"; } > $P/user.js
rm -rf $P/.startup-incomplete $P/.parentlock $P/lock $P/sessionstore* $P/sessionstore-backups
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null 2>&1
wtype -k Escape 2>/dev/null; sleep 1
rm -f /tmp/ytshot-$T.moz*
systemd-run --user --unit=ytshot-$T --collect -p KillMode=process env ${REQ:+GT510_V4L2_REQUEUE_DELAY=$REQ} MOZ_LOG=FFmpegVideo:4,PlatformDecoderModule:4 MOZ_LOG_FILE=/tmp/ytshot-$T.moz firefox-esr --no-remote --profile $P >/dev/null 2>&1
sleep 35
wtype -k F11; sleep 3; wtype f; sleep 12
venus=0; for p in $(pgrep -f firefox-esr); do venus=$((venus + $(ls -l /proc/$p/fd 2>/dev/null | grep -c $VDEC))); done
echo "${SUDO_PW:-147147}" | sudo -S -p "" rm -f /tmp/ytshot-$T-*.png
i=1; while [ $i -le $N ]; do
	echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
		-vf hwdownload,format=bgr0 -frames:v 1 /tmp/ytshot-$T-$i.png
	i=$((i + 1))
done
echo "${SUDO_PW:-147147}" | sudo -S -p "" sh -c "chmod 644 /tmp/ytshot-$T-*.png"
in=""; tin=""; i=1; while [ $i -le $N ]; do in="$in -i /tmp/ytshot-$T-$i.png"; i=$((i + 1)); done
ffmpeg -hide_banner -loglevel error -y $in -filter_complex "$(i=0; while [ $i -lt $N ]; do printf '[%d]scale=384:-1[s%d];' $i $i; i=$((i+1)); done; i=0; while [ $i -lt $N ]; do printf '[s%d]' $i; i=$((i+1)); done; printf 'hstack=inputs=%d' $N)" /tmp/ytshot-$T-strip.png
ffmpeg -hide_banner -loglevel error -y $in -filter_complex "$(i=0; while [ $i -lt $N ]; do printf '[%d]crop=360:260:408:0[c%d];' $i $i; i=$((i+1)); done; i=0; while [ $i -lt $N ]; do printf '[c%d]' $i; i=$((i+1)); done; printf 'hstack=inputs=%d' $N)" /tmp/ytshot-$T-tri.png
echo "$T: hw=$HW venus fds=$venus  V4L2 frames $(cat /tmp/ytshot-$T.moz* 2>/dev/null | grep -c "V4L2 Got one frame")  SW frames $(cat /tmp/ytshot-$T.moz* 2>/dev/null | grep -c "Got one frame output with pts" )"
cat /tmp/ytshot-$T.moz* 2>/dev/null | grep -o -E "requested type '[^']+'|Initialising [A-Za-z0-9-]+ FFmpeg decoder|Choosing FFmpeg pixel format[^.]*|codec [a-z0-9_]+ :" | sort | uniq -c | sort -rn | head -6
for p in $(pgrep -x firefox-esr); do kill $p 2>/dev/null; done; sleep 2; rm -f $P/user.js
