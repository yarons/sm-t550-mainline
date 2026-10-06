#!/bin/sh
# picktest.sh [runs] — ISSUES 33: launch GNOME Snapshot N times the normal way (gapplication launch = D-Bus
# activation) and report which camera each launch opened (libcamera "configuring streams" in the camera service:
# 640x480/1600x1200 NV21 = front SR200PC20, XRGB = rear SR544) plus aperture's own view of the device list
# ("Camera found" = listed at provider start, "Camera added" = arrived later on the bus). Snapshot's debug log is
# switched on for this test only (G_MESSAGES_DEBUG=snapshot in the activation environment) and removed at the end;
# last-camera-id is restored if a run changed it. Session user; refuses if Snapshot or cam is already running.
N=${1:-8}
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
pgrep -x snapshot >/dev/null && { echo "Snapshot already running"; exit 3; }
pgrep -x cam >/dev/null && { echo "cam running"; exit 3; }
id0=$(gsettings get org.gnome.Snapshot last-camera-id)
cleanup() {
	gdbus call --session --dest org.gnome.Snapshot --object-path /org/gnome/Snapshot \
		--method org.gtk.Actions.Activate quit "[]" "{}" >/dev/null 2>&1; sleep 1; pkill -x snapshot 2>/dev/null
	# dbus-broker forwards activation-env updates to systemd: blank it for D-Bus first, then drop it from systemd
	dbus-update-activation-environment G_MESSAGES_DEBUG= >/dev/null 2>&1
	systemctl --user unset-environment G_MESSAGES_DEBUG
	[ "$(gsettings get org.gnome.Snapshot last-camera-id)" = "$id0" ] || gsettings set org.gnome.Snapshot last-camera-id "$id0"
}
trap cleanup EXIT INT TERM
dbus-update-activation-environment --systemd G_MESSAGES_DEBUG=snapshot >/dev/null 2>&1
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
echo "last-camera-id $id0"
front=0; rear=0
for i in $(seq 1 "$N"); do
	t=$(date "+%Y-%m-%d %H:%M:%S"); sleep 1
	gapplication launch org.gnome.Snapshot >/dev/null 2>&1
	sleep 7
	cfg=$(journalctl --user -u wireplumber@video-capture --since "$t" --no-pager -o cat 2>/dev/null |
		grep -o "configuring streams: (0) [^ ]*" | sed 's/configuring streams: (0) //' | tr '\n' ' ')
	ap=$(journalctl --user --since "$t" --no-pager -o cat 2>/dev/null | grep -o -E "Camera (found|added): Built-in [A-Za-z]+" |
		sed -E 's/Camera (found|added): Built-in /\1:/' | tr '\n' ' ')
	case "$cfg" in *NV21*) front=$((front + 1)); who=FRONT ;; *XRGB*|*ABGR*) rear=$((rear + 1)); who=rear ;; *) who=none ;; esac
	echo "run $i $(date +%T): $who [$cfg] aperture: ${ap:-no debug lines}"
	gdbus call --session --dest org.gnome.Snapshot --object-path /org/gnome/Snapshot \
		--method org.gtk.Actions.Activate quit "[]" "{}" >/dev/null 2>&1
	sleep 2; pkill -x snapshot 2>/dev/null; sleep 1
done
echo "summary: rear $rear, front $front of $N; last-camera-id now $(gsettings get org.gnome.Snapshot last-camera-id)"
