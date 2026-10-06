#!/bin/sh
# fxseek.sh — Firefox (persistent bench profile, HW decode forced) plays the 100 s H.264 clip, then seeks with
# the keyboard (wtype: Right = +5 s in Firefox's video document, ×4) and checks that playback continues on Venus:
# last decoded pts before/after, flushes, frames shown, Venus session errors.
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
P=/home/user/.cache/fxbench-prof; L=/tmp/fxseek.log
pgrep -f firefox-esr >/dev/null && { echo "Firefox is already running — close it first"; exit 1; }
echo 'user_pref("media.hardware-video-decoding.force-enabled", true);' > $P/user.js
rm -f $L*; T0=$(date "+%Y-%m-%d %H:%M:%S")
systemd-run --user --unit=fxseek --collect env MOZ_LOG=FFmpegVideo:4 MOZ_LOG_FILE=$L \
	firefox-esr --no-remote --profile $P file:///home/user/vtest/yt/yt-h264-100s.mp4 >/dev/null 2>&1
sleep 30
pts() { grep -h -o "V4L2 Got one frame output with pts=[0-9]*" $L* 2>/dev/null | tail -1 | grep -o "[0-9]*$"; }
p0=$(pts); f0=$(grep -h -c ProcessFlush $L* 2>/dev/null | awk '{s+=$1} END {print s+0}')
for i in 1 2 3 4; do wtype -k Right; sleep 0.3; done
sleep 8
p1=$(pts); f1=$(grep -h -c ProcessFlush $L* 2>/dev/null | awk '{s+=$1} END {print s+0}')
PF=$(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 ~/vtest/planefps.py 5 | grep -v "(off)" | tr "\n" ";")
p2=$(pts)
echo "pts before seek ${p0:-?} us, 8 s after seek ${p1:-?} us, +5 s later ${p2:-?} us; flushes $f0 -> $f1; $PF"
echo "venus errors: $(journalctl -k --no-pager --since "$T0" | grep -c -E 'session error|Err_Fatal')"
systemctl --user stop fxseek 2>/dev/null; sleep 2; rm -f $P/user.js
