#!/bin/sh
# fxrepro.sh <tag> [seconds] [url] — (session user) ISSUES 23 YouTube stall/triangle repro in Yaron's OWN Firefox (default
# profile, nothing changed in it; env only): starts Firefox with decoder logs (MOZ_LOG → /tmp/fxlog-<tag>*), a Venus trace
# for <seconds> (vtrace.sh → /tmp/vt-<tag>.txt) and a once-a-second watch of the RDD process's /dev/video fds with the
# uptime (= dmesg time) → /tmp/fdwatch-<tag>.txt. FXENV='VAR=value …' adds environment (e.g. the test Mesa).
T=$1; D=${2:-300}; U=$3
systemd-run --user --unit=fxyaron-$T --collect -p KillMode=process env $FXENV \
	MOZ_LOG="timestamp,PlatformDecoderModule:5,FFmpegVideo:5,MediaFormatReader:5" MOZ_LOG_FILE=/tmp/fxlog-$T firefox-esr $U >/dev/null 2>&1
# services, not background jobs: an ssh session closing kills its background jobs
echo "${SUDO_PW:-147147}" | sudo -S -p "" systemd-run --unit=vtrace-$T --collect sh /home/user/vtest/vtrace.sh /tmp/vt-$T.txt sleep "$D" >/dev/null 2>&1
systemd-run --user --unit=fdwatch-$T --collect sh -c 'end=$(( $(date +%s) + '"$D"' ))
while [ "$(date +%s)" -lt "$end" ]; do
	R=$(pgrep -f "contentproc.*rdd" | head -1)
	n=0; [ -n "$R" ] && n=$(ls -l /proc/$R/fd 2>/dev/null | grep -c /dev/video)
	echo "$(cut -d" " -f1 /proc/uptime) rdd=$R videofds=$n"
	sleep 1
done > /tmp/fdwatch-'"$T"'.txt' >/dev/null 2>&1
