#!/bin/sh
# Rear camera Snapshot with the test Mesa: rendered fps + GPU ms/job per process, per env variant.
#   fdperf.sh "<env assignments>" ...
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
F=/usr/share/dbus-1/services/org.gnome.Snapshot.service
T=$HOME/mesatest/root/usr/lib
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
S cp "$F" /root/snapshot.service.orig
trap 'S cp /root/snapshot.service.orig "$F"; S rm -f /root/snapshot.service.orig; pkill -x snapshot' EXIT
for v in "$@"; do
	e="env -u FD_MESA_DEBUG LD_LIBRARY_PATH=$T LIBGL_DRIVERS_PATH=$T/dri GBM_BACKENDS_PATH=$T/gbm GSK_RENDERER=gl IR3_SHADER_DEBUG=nouboopt $v"
	S sed -i "s|^Exec=.*|Exec=$e /usr/bin/snapshot --gapplication-service|" "$F"
	pkill -x snapshot; sleep 2; U
	gapplication launch org.gnome.Snapshot; sleep 14; U; sleep 1
	p=$(pgrep -x snapshot); [ -z "$p" ] && { echo "[$v] DID NOT START"; continue; }
	S perf probe -q -d 'probe_*:*' 2>/dev/null
	S perf probe -q -x /usr/lib/libgtk-4.so.1.2400.0 gsk_renderer_render
	S perf stat -x, -e probe_libgtk:gsk_renderer_render -p "$p" -o "$HOME/fdperf.perf" -- sleep 6
	S perf probe -q -d 'probe_*:*'
	rend=$(grep gsk_renderer_render "$HOME/fdperf.perf" | cut -d, -f1)
	S sh -c 'T=/sys/kernel/tracing; echo > $T/trace; echo 1 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable;
		echo 1 > $T/tracing_on; sleep 3; echo 0 > $T/tracing_on;
		echo 0 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable; cat $T/trace' > "$HOME/fdperf.trace"
	gpu=$(awk '/msm_gpu_submit_retired/ { t = $4 + 0; match($0, /pid=[0-9]+/); p = substr($0, RSTART + 4, RLENGTH - 4)
		if (lt) { sum[p] += (t - lt) * 1000; n[p]++ } lt = t }
		END { for (p in n) { c = "cat /proc/" p "/comm 2>/dev/null"; name = ""; c | getline name; close(c)
			printf " %s %.1fms", name, sum[p] / n[p] } }' "$HOME/fdperf.trace")
	printf '%-24s rendered %2d fps |%s\n' "[$v]" $((rend / 6)) "$gpu"
done
