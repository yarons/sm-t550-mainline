#!/bin/sh
# Run a client (args) for a while, trace GPU job retirements for 3 s, report average GPU time per
# job for each process (valid while the GPU is saturated; otherwise gaps include idle time).
#   gpujobs.sh <tag> <command...>
tag=$1; shift
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
U
if [ "$1" != "none" ]; then
	systemd-run --user --unit="gj-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 "$@" >/dev/null 2>&1
	sleep 8
fi
U; sleep 2
S sh -c 'T=/sys/kernel/tracing; echo > $T/trace; echo 1 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable;
	echo 1 > $T/tracing_on; sleep 3; echo 0 > $T/tracing_on;
	echo 0 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable; cat $T/trace' > "$HOME/gj-$tag.txt"
awk -v tag="$tag" '
/msm_gpu_submit_retired/ { t = $4 + 0; match($0, /pid=[0-9]+/); p = substr($0, RSTART + 4, RLENGTH - 4)
	if (lt) { sum[p] += (t - lt) * 1000; n[p]++ } lt = t; first = first ? first : t; last = t }
END { printf "%s (%.1f s traced):", tag, last - first
	for (p in n) { c = "cat /proc/" p "/comm 2>/dev/null"; name = ""; c | getline name; close(c)
		printf "  %s[%s] %d jobs avg %.1f ms", name, p, n[p], sum[p] / n[p] }
	print "" }' "$HOME/gj-$tag.txt"
[ "$1" != "none" ] && systemctl --user stop "gj-$tag" 2>/dev/null
exit 0
