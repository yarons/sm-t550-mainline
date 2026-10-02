#!/bin/sh
# Launch apps one at a time (like the app grid) and count new GPU iommu fault storms per app.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
cnt() { S dmesg | grep -cE "msm_gpu_fault_handler|\*\*\* fault"; }
try() { name=$1; shift; U; a=$(cnt); t0=$(cut -d' ' -f1 /proc/uptime)
	"$@" >/dev/null 2>&1 & sleep 15; b=$(cnt)
	echo "$name: new fault lines $((b - a)) (launched at ${t0}s)"; }
gs() { gsettings set org.gnome.Snapshot last-camera-id "$1"; }
prev_cam=$(gsettings get org.gnome.Snapshot last-camera-id)  # restored on exit: never leave the user on a test camera
trap 'gsettings set org.gnome.Snapshot last-camera-id "$prev_cam"' EXIT
try "Files" gapplication launch org.gnome.Nautilus; pkill -x nautilus; sleep 2
try "Calculator" gapplication launch org.gnome.Calculator; pkill -f gnome-calculator; sleep 2
gs "Built-in Front Camera"; try "Snapshot front" gapplication launch org.gnome.Snapshot; pkill -x snapshot; sleep 2
gs "Built-in Back Camera"; try "Snapshot rear" gapplication launch org.gnome.Snapshot; pkill -x snapshot; sleep 2
try "cam rear (no GTK)" cam -c /base/soc@0/cci@1b0c000/i2c-bus@0/camera@28 --capture=60; sleep 2
try "cam front (no GTK)" cam -c /base/soc@0/cci@1b0c000/i2c-bus@0/camera@20 --capture=60; sleep 2
S dmesg | grep -E "msm_gpu_fault_handler" | tail -4
