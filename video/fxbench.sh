#!/bin/sh
# fxbench.sh <url> <tag> [user_pref lines …] — play <url> in Firefox ESR with a THROWAWAY profile (/tmp/fxbench-<tag>,
# deleted afterwards; the user's profile and session are never touched), then measure for 10 s: CPU % (one core =
# 100) summed over all Firefox processes, MemAvailable / swap used / memory PSI, Venus fds, frames shown per DRM plane
# (planefps.py), and which decoder Firefox picked (MOZ_LOG PlatformDecoderModule → /tmp/fxbench-<tag>.log).
# Extra args are raw prefs, e.g. 'user_pref("media.hardware-video-decoding.force-enabled", true);'.
# PROF=<dir> = persistent profile instead (kept; warm it once: pmOS policy force-installs uBlock Origin, whose
# first-run list compile costs ~1 core for minutes). WAIT=<s> before measuring (default 12; a fresh profile does first-run work for ~30 s).
# Run as the session user (sudo password <password> for debugfs).
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name | head -1)")")  # node moves between boots
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
U=$1; T=$2; shift 2
P=${PROF:-/tmp/fxbench-$T}; L=/tmp/fxbench-$T.log
pgrep -f firefox-esr >/dev/null && { echo "Firefox is already running — close it first"; exit 1; }
rm -f "$L"*; [ -n "$PROF" ] || rm -rf "$P"; mkdir -p "$P"; rm -f "$P/user.js"
for p in "$@"; do echo "$p" >> "$P/user.js"; done
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null 2>&1
systemd-run --user --unit=fxbench-$T --collect env MOZ_LOG=PlatformDecoderModule:4,FFmpegVideo:4,Dmabuf:4 MOZ_LOG_FILE=$L \
	firefox-esr --no-remote --profile "$P" "$U" >/dev/null 2>&1
sleep ${WAIT:-12}
ticks() { t=0; for p in $(pgrep -f firefox-esr); do v=$(awk '{print $14+$15}' /proc/$p/stat 2>/dev/null); t=$((t + ${v:-0})); done; echo $t; }
mem() { awk '/MemAvailable/{a=$2} /SwapTotal/{st=$2} /SwapFree/{sf=$2} END{printf "avail %d MB, swap used %d MB", a/1024, (st-sf)/1024}' /proc/meminfo; }
venus=0; for p in $(pgrep -f firefox-esr); do venus=$((venus + $(ls -l /proc/$p/fd 2>/dev/null | grep -c $VDEC))); done
lavc=$(for p in $(pgrep -f firefox-esr); do grep -ho "libavcodec\.so\.[0-9]*" /proc/$p/maps 2>/dev/null; done | sort -u | tr "\n" " ")
tticks() { for p in $(pgrep -f firefox-esr); do k=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | awk '{print $NF}'); case $k in rdd|tab|gpu|socket|utility) ;; *) k=main;; esac
	for t in /proc/$p/task/*; do printf "%s %s:%s %s\n" "${t##*/}" "$k" "$(tr ' ' '_' < $t/comm 2>/dev/null)" "$(awk '{print $14+$15}' $t/stat 2>/dev/null)"; done; done; }
m0=$(mem); u0=$(ticks); tticks > /tmp/fxbench-t0
PF=$(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 ~/vtest/planefps.py 10 | grep -v "(off)" | tr "\n" ";")
u1=$(ticks); m1=$(mem); tticks > /tmp/fxbench-t1
psi=$(awk '/full/{print $2}' /proc/pressure/memory)
echo "$T: firefox CPU $(( (u1 - u0) / 10 ))%  venus fds=$venus lavc=[$lavc]  start: $m0  end: $m1  mem PSI full $psi  planes: $PF"
echo "  top threads (% of one core):"; awk 'NR==FNR {a[$1]=$3; next} {d=$3-a[$1]; if (d > 0) s[$2]+=d} END {for (k in s) printf "    %4d%% %s\n", s[k]/10, k}' /tmp/fxbench-t0 /tmp/fxbench-t1 | sort -rn | head -10
grep -h -o -E "(FFmpeg|FFVPX|V4L2|VAAPI|Dmabuf|OpenH264|libavcodec)[^\"]{0,110}" "$L"* 2>/dev/null | sed -E 's/0x[0-9a-f]+/0x…/g' | sort | uniq -c | sort -rn | head -8
systemctl --user stop fxbench-$T 2>/dev/null; sleep 3
for p in $(pgrep -f "firefox-esr --no-remote --profile $P"); do kill $p 2>/dev/null; done; sleep 1
[ -n "$PROF" ] || rm -rf "$P"
