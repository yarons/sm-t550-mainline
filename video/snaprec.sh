#!/bin/sh
# snaprec.sh <secs> <tag> — record a <secs> video with GNOME Snapshot (rear camera, its own settings) and report the
# file: codec, size, duration, bitrate, frame rate. Switches Snapshot to video mode, presses its shutter through the
# shutter (uinput tap, see act()) twice, closes Snapshot and restores capture-mode.
# Run as the session user (sudo password <password> for the optional SHOT=<png> kmsgrab screenshot).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S=$1; T=$2; L=$HOME/vtest/logs; mkdir -p $L
mode0=$(gsettings get org.gnome.Snapshot capture-mode)
gsettings set org.gnome.Snapshot capture-mode video
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
gapplication launch org.gnome.Snapshot >/dev/null 2>&1
sleep 8
W=$(gdbus introspect --session --dest org.gnome.Snapshot --object-path /org/gnome/Snapshot/window 2>/dev/null |
	awk '/node [0-9]+/ {print $2; exit}')
# win.take-picture is a widget action (not on D-Bus) and has no key binding: tap the shutter through a uinput
# touchscreen (uitap.py; TAP="x y" in raw 768x1024 scanout pixels; default = Snapshot's record button for the
# current landscape transform, 90 or 270, read with wlr-randr).
XFORM=$(WAYLAND_DISPLAY=wayland-0 wlr-randr 2>/dev/null | awk '/Transform:/ {print $2; exit}')
case "$XFORM" in 90) TAP0="390 40";; 270) TAP0="380 980";; *) TAP0="";; esac
[ -n "${TAP:-$TAP0}" ] || { echo "$T: output transform $XFORM: shutter position unknown, set TAP"; exit 1; }
act() { echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 $HOME/vtest/uitap.py ${TAP:-$TAP0} >/dev/null; }
D=$HOME/Videos/Camera; before=$(ls -t "$D" 2>/dev/null | head -1)
act
if [ -n "$SHOT" ]; then  # SHOT=<png>: screenshot of the screen (preview) 3 s into the recording
	sleep 3; echo "${SUDO_PW:-147147}" | sudo -S -p "" ffmpeg -hide_banner -loglevel error -y -device /dev/dri/card0 -f kmsgrab -i - \
		-vf hwdownload,format=bgr0 -frames:v 1 "$SHOT" && echo "${SUDO_PW:-147147}" | sudo -S -p "" chmod 644 "$SHOT"
	sleep $((S - 3))
else
	sleep "$S"
fi
act; sleep 10  # mp4 finalisation (moov) takes a few seconds
gdbus call --session --dest org.gnome.Snapshot --object-path /org/gnome/Snapshot \
	--method org.gtk.Actions.Activate quit "[]" "{}" >/dev/null 2>&1
sleep 2; pkill -x snapshot 2>/dev/null
gsettings set org.gnome.Snapshot capture-mode "$mode0"
F=$(ls -t "$D" 2>/dev/null | head -1)
[ -n "$F" ] && [ "$F" != "$before" ] || { echo "$T: no new recording (window ${W:-?})"; exit 1; }
V=$D/$F
echo "$T: $F $(stat -c %s "$V") B"
ffprobe -v error -show_entries format=duration,bit_rate:stream=codec_type,codec_name,profile,level,width,height,avg_frame_rate,bit_rate,nb_frames \
	-of compact "$V"
