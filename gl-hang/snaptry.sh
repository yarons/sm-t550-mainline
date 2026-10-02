#!/bin/sh
# Launch Snapshot like the app grid does, on the given default camera, and report whether it streams.
#   snaptry.sh Front|Back
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
pkill -x snapshot; sleep 2
wpctl set-default "$(wpctl status | sed -n '/^Video/,/^Settings/p' | grep "$1 Camera" | grep -oE '[0-9]+\.' | tr -d .)"
since=$(date +%s)
gapplication launch org.gnome.Snapshot
sleep 14
i1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts); sleep 5; i2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
echo "$1: sensor $(( (i2 - i1) / 5 ))/s"
journalctl --user -b -o cat --no-pager --since "@$since" | grep -oE "Orientation: libcamera rotation [^,]*|no more input formats|not-negotiated|Could not start camerabin" | sort | uniq -c
pkill -x snapshot
