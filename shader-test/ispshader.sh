#!/bin/sh
# ISP GPU time per debayer shader variant (Mesa shader replacement in wireplumber@video-capture).
#   ispshader.sh <variant>...   (variant dirs ~/shvar/<v>/FS_<hash>.glsl; "orig" = no replacement)
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
D=$XDG_RUNTIME_DIR/systemd/user/wireplumber@video-capture.service.d
trap 'rm -f $D/shvar.conf; systemctl --user daemon-reload; systemctl --user restart wireplumber@video-capture' EXIT
for v in "$@"; do
	mkdir -p $D
	printf '[Service]\nEnvironment=MESA_SHADER_READ_PATH=%s/shvar/%s MESA_SHADER_CACHE_DISABLE=true\n' "$HOME" "$v" > $D/shvar.conf
	systemctl --user daemon-reload; pkill -x snapshot; systemctl --user restart wireplumber@video-capture; sleep 8
	printf '%-8s ' "$v"; ~/fdperf.sh "IR3_SHADER_DEBUG= FD_GT510=272" 2>&1 | tail -1
done
