#!/bin/sh
# Snapshot streaming for each (PipeWire default camera, Snapshot last-camera-id) combination.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
prev_cam=$(gsettings get org.gnome.Snapshot last-camera-id)  # restored on exit: never leave the user on a test camera
id() { wpctl status | sed -n '/^Video/,/^Settings/p' | grep "$1 Camera" | grep -oE '[0-9]+\.' | tr -d .; }
for def in Front Back; do for last in Front Back; do
	pkill -x snapshot; sleep 2
	wpctl set-default "$(id $def)"; gsettings set org.gnome.Snapshot last-camera-id "Built-in $last Camera"
	gapplication launch org.gnome.Snapshot; sleep 12
	i1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts); sleep 4; i2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
	echo "default=$def last=$last: sensor $(( (i2 - i1) / 4 ))/s"
done; done
pkill -x snapshot
wpctl set-default "$(id Front)"; gsettings set org.gnome.Snapshot last-camera-id "$prev_cam"
