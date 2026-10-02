#!/bin/sh
# Launch Snapshot with an FD_MESA_DEBUG variant, trace GPU job retirements for 3 s and report
# the average GPU time per job for Snapshot and phoc (a3xx has no per-job timestamps, but the GPU is
# saturated, so the gap before each retirement is that job's GPU time).
#   gputime.sh <tag> <FD_MESA_DEBUG value>
tag=$1 fd=$2
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
pkill -x snapshot; sleep 2; U
systemd-run --user --unit="gt-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 -E APERTURE_OPTIMAL_RATIO=4:3 \
	-E GSK_RENDERER=gl -E IR3_SHADER_DEBUG=nouboopt -E FD_MESA_DEBUG="$fd" snapshot >/dev/null 2>&1
sleep 14; U; sleep 2
sp=$(pgrep -x snapshot | head -1); pp=$(pgrep -x phoc)
S sh -c 'T=/sys/kernel/tracing; echo > $T/trace; echo 1 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable;
	echo 1 > $T/tracing_on; sleep 3; echo 0 > $T/tracing_on;
	echo 0 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable; cat $T/trace' > "$HOME/gt-$tag.txt"
awk -v sp="$sp" -v pp="$pp" -v tag="$tag" '
/msm_gpu_submit_retired/ { t = $4 + 0; match($0, /pid=[0-9]+/); p = substr($0, RSTART + 4, RLENGTH - 4)
	if (lt) { d = (t - lt) * 1000; if (p == sp) { s += d; ns++ } else if (p == pp) { c += d; nc++ } else { o += d; no++ } }
	lt = t }
END { printf "%s: snapshot %d jobs avg %.1f ms | phoc %d jobs avg %.1f ms | other %d jobs %.0f ms total -> %.1f fps shown\n",
	tag, ns, ns ? s / ns : 0, nc, nc ? c / nc : 0, no, o, nc / 3 }' "$HOME/gt-$tag.txt"
systemctl --user stop "gt-$tag" 2>/dev/null; pkill -x snapshot
