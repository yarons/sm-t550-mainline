#!/bin/sh
# Screenshot Snapshot's viewfinder (current default camera) after it settles.
#   camshot.sh <out.png> [snapshot env VAR=val...]
out=$1; shift
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
envs="-E WAYLAND_DISPLAY=wayland-0 -E APERTURE_OPTIMAL_RATIO=4:3 -E GSK_RENDERER=gl -E IR3_SHADER_DEBUG=nouboopt"
for kv in "$@"; do envs="$envs -E $kv"; done
pkill -x snapshot; sleep 2; U
# shellcheck disable=SC2086
systemd-run --user --unit=camshot --collect $envs snapshot >/dev/null 2>&1
sleep 15; U; sleep 2
echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
	-vf hwdownload,format=bgr0 -frames:v 1 "$out"
systemctl --user stop camshot; pkill -x snapshot
