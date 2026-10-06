#!/bin/sh
# snapstill.sh <tag> — take one photo with GNOME Snapshot (rear camera) by tapping its shutter through a uinput
# touchscreen (video/uitap.py; positions as in video/snaprec.sh) and report the photo's size and the time from the
# tap to the file, plus the viewfinder size PipeWire negotiated. Snapshot runs via systemd-run with the camera env
# from gt510-camera.conf (a running session only picks environment.d changes up after a re-login).
# GSTDBG=<GST_DEBUG spec> logs GStreamer to /tmp/snapstill-<tag>.gst; SNAPBIN=<path> runs another snapshot binary
# (e.g. one extracted from a test APK, not installed); WAIT=<s> before the tap (default 10). Run as the session user (sudo password <password> for uitap.py).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
T=$1; D=$HOME/Pictures/Camera
mode0=$(gsettings get org.gnome.Snapshot capture-mode)
gsettings set org.gnome.Snapshot capture-mode picture
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
systemd-run --user --unit=snapstill --collect env $(grep -v "^#" /etc/environment.d/60-gt510-camera.conf | tr "\n" " ") \
	GSK_RENDERER=gl ${GSTDBG:+GST_DEBUG=$GSTDBG GST_DEBUG_FILE=/tmp/snapstill-$T.gst GST_DEBUG_NO_COLOR=1} ${SNAPBIN:-snapshot} >/dev/null 2>&1
sleep ${WAIT:-10}
N=libcamera_input._base_soc_0_cci_1b0c000_i2c-bus_0_camera_28
vf=$(pw-dump 2>/dev/null | python3 -c '
import json, sys
for o in json.load(sys.stdin):
    p = o.get("info", {}).get("props", {})
    if p.get("node.name") == sys.argv[1]:
        for f in o["info"].get("params", {}).get("Format", []):
            s = f.get("size", {}); print("%sx%s" % (s.get("width"), s.get("height")))' $N)
XFORM=$(WAYLAND_DISPLAY=wayland-0 wlr-randr 2>/dev/null | awk '/Transform:/ {print $2; exit}')
case "$XFORM" in 90) TAP0="390 40";; 270) TAP0="380 980";; normal) TAP0="379 965";; *) TAP0="";; esac
mkdir -p "$D"; before=$(ls -t "$D" 2>/dev/null | head -1)
t0=$(date +%s.%N)
echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 $HOME/vtest/uitap.py ${TAP:-$TAP0} >/dev/null
f=""; for i in $(seq 1 60); do sleep 0.25; n=$(ls -t "$D" 2>/dev/null | head -1)
	[ -n "$n" ] && [ "$n" != "$before" ] && ffprobe -v quiet "$D/$n" 2>/dev/null && { f=$n; break; }; done
t1=$(date +%s.%N)
gdbus call --session --dest org.gnome.Snapshot --object-path /org/gnome/Snapshot \
	--method org.gtk.Actions.Activate quit "[]" "{}" >/dev/null 2>&1
sleep 2; pkill -x snapshot 2>/dev/null; [ -n "$SNAPBIN" ] && pkill -x "$(basename "$SNAPBIN")" 2>/dev/null
gsettings set org.gnome.Snapshot capture-mode "$mode0"
[ -n "$f" ] || { echo "$T: no new photo (viewfinder ${vf:-?}, transform $XFORM)"; exit 1; }
sz=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$D/$f")
echo "$T: photo $f ${sz} $(stat -c %s "$D/$f") bytes, tap→file $(echo "$t1 $t0" | awk '{printf "%.1f", $1-$2}') s, viewfinder ${vf:-?}"
