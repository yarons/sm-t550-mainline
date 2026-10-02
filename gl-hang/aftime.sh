#!/bin/sh
# Autofocus timing: Snapshot start (stream configure → AF scan) until the IPA logs "Focused at".
#   aftime.sh [runs]
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
D=$XDG_RUNTIME_DIR/systemd/user/wireplumber@video-capture.service.d
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
prev_cam=$(gsettings get org.gnome.Snapshot last-camera-id)  # restored on exit: never leave the user on a test camera
trap 'pkill -x snapshot; gsettings set org.gnome.Snapshot last-camera-id "$prev_cam"; rm -f $D/aflog.conf; systemctl --user daemon-reload; systemctl --user restart wireplumber@video-capture' EXIT
mkdir -p $D; printf '[Service]\nEnvironment=LIBCAMERA_LOG_LEVELS=*:WARN,IPASoftAf:DEBUG,Camera:INFO\n' > $D/aflog.conf
systemctl --user daemon-reload; pkill -x snapshot; systemctl --user restart wireplumber@video-capture; sleep 6
gsettings set org.gnome.Snapshot last-camera-id "Built-in Back Camera"
for i in $(seq 1 "${1:-3}"); do
	pkill -x snapshot; sleep 2; U
	t0=$(date '+%Y-%m-%d %H:%M:%S')
	gapplication launch org.gnome.Snapshot; sleep 10
	journalctl --user -u wireplumber@video-capture --since "$t0" --no-pager -o cat |
		grep -E "configuring streams|Focused at|refocusing" | sed -E 's/^\[([0-9:.]+)\].*(configuring streams|Focused at.*|refocusing.*)/\1 \2/'
	echo ---
done
