#!/bin/sh
# Launch Snapshot with extra env, grab 30 screen frames, count frames whose app area is black.
#   flicker.sh <tag> [VAR=value ...]
set -u
tag=$1; shift
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
envs="-E WAYLAND_DISPLAY=wayland-0 -E APERTURE_OPTIMAL_RATIO=4:3 -E GSK_RENDERER=gl -E IR3_SHADER_DEBUG=nouboopt"
for kv in "$@"; do envs="$envs -E $kv"; done
pkill -x snapshot; systemctl --user stop "flk-$tag" 2>/dev/null; sleep 2
U
# shellcheck disable=SC2086
systemd-run --user --unit="flk-$tag" --collect $envs snapshot >/dev/null 2>&1
sleep 12; U; sleep 3
# app area = below the phosh top bar; per-frame mean luma (limited range: black = 16)
S ffmpeg -loglevel error -nostats -y -device /dev/dri/card0 -f kmsgrab -framerate 60 -i - -t 3 \
	-vf "hwdownload,format=bgr0,crop=768:900:0:40,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
	-f null - 2>/dev/null | grep -oE "YAVG=[0-9.]+" | cut -d= -f2 > "$HOME/yavg-$tag.txt"
n=$(wc -l < "$HOME/yavg-$tag.txt"); black=$(awk '$1 < 20' "$HOME/yavg-$tag.txt" | wc -l)
p=$(pgrep -x snapshot | head -1)
renders=$(S sh -c "perf probe -q -x /usr/lib/libgtk-4.so.1.2400.0 gsk_renderer_render; perf stat -x, -e probe_libgtk:gsk_renderer_render -p $p -- sleep 5 2>&1 | cut -d, -f1; perf probe -q -d 'probe_libgtk:*'" | tail -1)
c1=$(awk '{print $14+$15}' /proc/$p/stat); sleep 5; c2=$(awk '{print $14+$15}' /proc/$p/stat)
hang=$(S dmesg | grep -c hangcheck)
systemctl --user stop "flk-$tag"; pkill -x snapshot
echo "$tag: black=$black/$n fps=$((renders / 5)) cpu=$(( (c2 - c1) / 5 ))% hangs=$hang env=[$*]"
