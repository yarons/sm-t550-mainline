#!/bin/sh
# A/B the soft ISP debayer: grab soft-ISP output frames (tag-free, sensor orientation) with GPU then CPU debayer.
#   ispab.sh   -> ~/isp-gpu.png ~/isp-cpu.png
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
D=$XDG_RUNTIME_DIR/systemd/user/wireplumber@video-capture.service.d
N=libcamera_input._base_soc_0_cci_1b0c000_i2c-bus_0_camera_28
grab() {
	sleep 15
	timeout 40 gst-launch-1.0 -q pipewiresrc target-object=$N num-buffers=30 ! video/x-raw,width=1152,height=864 ! \
		videoconvert ! pngenc ! multifilesink location=/tmp/ispab%02d.png >/dev/null 2>&1
	ls /tmp/ispab*.png | wc -l; cp "$(ls /tmp/ispab*.png | tail -1)" "$1"; rm -f /tmp/ispab*.png
}
pkill -x snapshot
trap 'rm -rf "$D"; systemctl --user daemon-reload; systemctl --user restart wireplumber@video-capture' EXIT
grab "$HOME/isp-gpu.png"
mkdir -p "$D"; printf '[Service]\nEnvironment=LIBCAMERA_SOFTISP_MODE=cpu\n' > "$D/cpu.conf"
systemctl --user daemon-reload; systemctl --user restart wireplumber@video-capture
grab "$HOME/isp-cpu.png"
ls -la "$HOME"/isp-*.png
