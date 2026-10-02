#!/bin/sh
# Rotate the output under a running Snapshot and check the camera keeps streaming.
#   rottest.sh <Front|Back> <transform>...    e.g. rottest.sh Back normal 270
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus WAYLAND_DISPLAY=wayland-0
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
rate() { i1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts); sleep 3; i2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts); echo $(( (i2 - i1) / 3 )); }
cam=$1; shift
pkill -x snapshot; sleep 2; U
# restore the user's camera choice afterwards (this script used to leave it on the tested camera)
prev_cam=$(gsettings get org.gnome.Snapshot last-camera-id)
trap 'gsettings set org.gnome.Snapshot last-camera-id "$prev_cam"' EXIT
gsettings set org.gnome.Snapshot last-camera-id "Built-in $cam Camera"
t0=$(date '+%Y-%m-%d %H:%M:%S')
gapplication launch org.gnome.Snapshot; sleep 12
echo "start ($(wlr-randr | awk '/Transform/{print $2}')): sensor $(rate)/s"
for t in "$@"; do
	wlr-randr --output DSI-1 --transform "$t"; U; sleep 6
	echo "after $t: sensor $(rate)/s"
	echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - -vf hwdownload,format=bgr0,scale=256:-1 -frames:v 1 "$HOME/rot-$t.png"
done
journalctl --user --since "$t0" --no-pager -o cat | grep -E "aperture|phoc|pipewire" | grep -vE "zbus" | cut -c1-200 | tail -12
