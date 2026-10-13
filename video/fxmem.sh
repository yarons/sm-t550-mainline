#!/bin/sh
# fxmem.sh <tag> <seconds> [user_pref lines…] — Firefox memory A/B (ISSUES 23): play URL= (default Yaron's test clip)
# in a COPY of the warmed bench profile (~/.cache/fxbench-prof → ~/.cache/fxmem-<tag>, removed afterwards; the
# user's own profile is never touched) with the extra prefs, HW decode forced, autoplay allowed. Every 10 s: Firefox
# process count and total RSS+swap, MemAvailable, swap used, memory PSI some avg10, Venus fds; every 60 s a 10 s
# frame-pacing sample (planefps.py). Per-sample log /tmp/fxmem-<tag>.txt, summary line at the end.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus WAYLAND_DISPLAY=wayland-0
T=$1; D=$2; shift 2; U=${URL:-https://youtu.be/pVaeEK1WC2M}
B=/home/user/.cache/fxbench-prof; P=/home/user/.cache/fxmem-$T; L=/tmp/fxmem-$T.txt
pgrep -x firefox-esr >/dev/null && { echo "Firefox is already running — close it first"; exit 1; }
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name | head -1)")")
rm -rf "$P"; cp -a "$B" "$P"
rm -rf $P/.startup-incomplete $P/.parentlock $P/lock $P/sessionstore* $P/sessionstore-backups
{ printf 'user_pref("media.hardware-video-decoding.force-enabled", true);\nuser_pref("media.autoplay.default", 0);\nuser_pref("media.autoplay.blocking_policy", 0);\n'
  printf 'user_pref("browser.sessionstore.resume_from_crash", false);\nuser_pref("browser.startup.page", 1);\nuser_pref("browser.startup.homepage", "%s");\n' "$U"
  for p in "$@"; do echo "$p"; done; } > $P/user.js
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null 2>&1
systemd-run --user --unit=fxmem-$T --collect -p KillMode=process firefox-esr --no-remote --profile $P >/dev/null 2>&1
s=0; : > $L
while [ $s -lt "$D" ]; do
	n=0; tot=0; venus=0
	for p in $(pgrep -f "firefox-esr"); do
		v=$(awk '/^VmRSS/ {r=$2} /^VmSwap/ {w=$2} END {print int((r + w) / 1024)}' /proc/$p/status 2>/dev/null)
		[ -n "$v" ] && { n=$((n + 1)); tot=$((tot + v)); }
		venus=$((venus + $(ls -l /proc/$p/fd 2>/dev/null | grep -c $VDEC)))
	done
	m=$(awk '/MemAvailable/ {a=$2} /SwapTotal/ {st=$2} /SwapFree/ {sf=$2} END {printf "avail=%d swap=%d", a / 1024, (st - sf) / 1024}' /proc/meminfo)
	echo "t=$s procs=$n ffmb=$tot $m psi=$(awk '/some/ {sub("avg10=", "", $2); print $2}' /proc/pressure/memory) venus=$venus" >> $L
	if [ $((s % 60)) -eq 30 ]; then
		echo "  pace t=$s $(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 /home/user/vtest/planefps.py 10 | grep plane-0)" >> $L; s=$((s + 10))
	else sleep 10; s=$((s + 10)); fi
done
for p in $(pgrep -x firefox-esr); do kill $p 2>/dev/null; done; sleep 3; rm -rf "$P"
awk -v T=$T '/^t=/ {for (i = 1; i <= NF; i++) {split($i, a, "="); v[a[1]] = a[2]} if (v["t"] >= 60) {k++; if (v["ffmb"] > mf) mf = v["ffmb"]; sf += v["ffmb"]; if (ma == "" || v["avail"] < ma) ma = v["avail"]; sa += v["avail"]; if (v["swap"] > ms) ms = v["swap"]; if (v["psi"] > mp) mp = v["psi"]; sp += v["psi"]; if (v["procs"] > mx) mx = v["procs"]; if (v["venus"] > 0) vs++}}
	/pace/ {match($0, /[0-9.]+ fb changes/); fps = fps " " substr($0, RSTART, RLENGTH - 11); match($0, /[0-9]+ gaps > 70/); gaps = gaps " " substr($0, RSTART, RLENGTH - 8)}
	END {printf "%s (t>=60 s, %d samples): firefox RSS+swap avg %d max %d MB, procs max %d; MemAvailable avg %d min %d MB; swap max %d MB; PSI some avg %.1f max %.1f; venus active %d/%d; fps%s; gaps>70ms%s\n", T, k, sf / k, mf, mx, sa / k, ma, ms, sp / k, mp, vs, k, fps, gaps}' $L
