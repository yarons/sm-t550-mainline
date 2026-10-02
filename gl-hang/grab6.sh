#!/bin/sh
# Open Snapshot (app-grid launch) and grab 6 screen frames at 10 fps into a 3x2 contact sheet.
#   grab6.sh <out.png>
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
pkill -x snapshot; sleep 1
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
gapplication launch org.gnome.Snapshot; sleep 12
echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -loglevel error -y -device /dev/dri/card0 -f kmsgrab -framerate 10 -i - \
	-vf "hwdownload,format=bgr0,scale=384:512,tile=3x2" -frames:v 1 "$1"
pkill -x snapshot
