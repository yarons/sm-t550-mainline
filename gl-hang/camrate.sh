#!/bin/sh
# Launch Snapshot (D-Bus, like the app grid) and report per-second pipeline rates.
#   camrate.sh <tag>
tag=$1
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
cpu() { awk '{print $14+$15}' "/proc/$1/stat"; }

pkill -x snapshot; sleep 2; U
if [ -n "$EXTRA" ]; then systemd-run --user --unit="cr-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 -E APERTURE_OPTIMAL_RATIO=4:3 -E GSK_RENDERER=gl -E IR3_SHADER_DEBUG=nouboopt -E FD_MESA_DEBUG=inorder $EXTRA snapshot >/dev/null 2>&1; else gapplication launch org.gnome.Snapshot; fi
sleep 14; U; sleep 2
p=$(pgrep -x snapshot | head -1)
w=$(pgrep -f "wireplumber -p video-capture" | head -1)
PW=$(ls /usr/lib/libpipewire-0.3.so.0* | head -1)
G=/usr/lib/libgtk-4.so.1.2400.0
S perf probe -q -d 'probe_*:*' 2>/dev/null
S perf probe -q -x "$PW" pw_stream_queue_buffer
S perf probe -q -x "$G" gsk_renderer_render
w1=$(cpu "$w"); s1=$(cpu "$p")
isp1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
S perf stat -x, -e probe_libpipewire:pw_stream_queue_buffer -e probe_libgtk:gsk_renderer_render \
	-p "$p" -o "$HOME/camrate.perf" -- sleep 10
isp2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
w2=$(cpu "$w"); s2=$(cpu "$p")
S perf probe -q -d 'probe_*:*'
deliv=$(grep pw_stream_queue_buffer "$HOME/camrate.perf" | cut -d, -f1)
rend=$(grep gsk_renderer_render "$HOME/camrate.perf" | cut -d, -f1)
echo "$tag: sensor=$(( (isp2 - isp1) / 10 ))/s delivered=$(( deliv / 10 ))/s rendered=$(( rend / 10 ))/s" \
	"snapshot_cpu=$(( (s2 - s1) / 10 ))% softisp_cpu=$(( (w2 - w1) / 10 ))%"
