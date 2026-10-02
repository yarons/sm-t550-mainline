#!/bin/sh
# Launch Snapshot with last-camera-id=<Front|Back>, report sensor irq rate + Snapshot journal lines.
#   fronttest.sh <Front|Back> [wait]
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
pkill -x snapshot; sleep 2
prev_cam=$(gsettings get org.gnome.Snapshot last-camera-id)  # restored on exit: never leave the user on a test camera
trap 'gsettings set org.gnome.Snapshot last-camera-id "$prev_cam"' EXIT
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
gsettings set org.gnome.Snapshot last-camera-id "Built-in $1 Camera"
t0=$(date '+%Y-%m-%d %H:%M:%S')
gapplication launch org.gnome.Snapshot; sleep ${2:-12}
i1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts); sleep 4; i2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
echo "last=$1: sensor $(( (i2 - i1) / 4 ))/s"
journalctl --user --since "$t0" --no-pager -o cat | grep -viE "sr200pc20'|sensor properties" | grep -iE "snapshot|aperture|error|warn|negotiat|format" | tail -20
