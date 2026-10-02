#!/bin/sh
# Run a gst-launch pipeline (args) with GTK GL, measure black frames of the app area.
#   gp.sh <tag> <gst-launch pipeline...>
tag=$1; shift
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
pkill -x snapshot; pkill -x gst-launch-1.0; sleep 2; U
systemd-run --user --unit="gp-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 -E GSK_RENDERER=gl \
	-E IR3_SHADER_DEBUG=nouboopt "$@" >/dev/null 2>&1
sleep 10; U; sleep 2
S ffmpeg -loglevel error -nostats -y -device /dev/dri/card0 -f kmsgrab -framerate 60 -i - -t 3 \
	-vf "hwdownload,format=bgr0,crop=768:900:0:40,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
	-f null - 2>/dev/null | grep -oE "YAVG=[0-9.]+" | cut -d= -f2 > "$HOME/yavg-gp-$tag.txt"
n=$(wc -l < "$HOME/yavg-gp-$tag.txt"); b=$(awk '$1 < 20' "$HOME/yavg-gp-$tag.txt" | wc -l)
st=$(systemctl --user is-active "gp-$tag")
systemctl --user stop "gp-$tag" 2>/dev/null
echo "$tag: black=$b/$n state=$st hangs=$(S dmesg | grep -c hangcheck)"
