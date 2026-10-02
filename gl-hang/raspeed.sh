#!/bin/sh
# RetroArch emulation speed: time 900 frames (--max-frames) per variant and display orientation.
#   raspeed.sh <rom> <core.so> <transforms, e.g. "3 0">
rom=$1; core=$2; transforms=$3
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
DC="gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig"
U() { $DC --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
rot() { s=$($DC --method org.gnome.Mutter.DisplayConfig.GetCurrentState | sed -n 's/^(uint32 \([0-9]*\),.*/\1/p')
	$DC --method org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig "$s" 1 \
		"[(0, 0, 1.0, $1, true, [(\"DSI-1\", \"768x1024@60\", @a{sv} {})])]" "@a{sv} {}" >/dev/null; }
cur() { $DC --method org.gnome.Mutter.DisplayConfig.GetCurrentState | grep -oE "\(0, 0, 1\.0, uint32 [0-9]" | tail -c 2; }
d=$HOME/ratest; mkdir -p "$d"; cp "$rom" "$d/test.${rom##*.}"
cp "$HOME/.config/retroarch/retroarch.cfg" "$d/base.cfg"
printf 'savefile_directory = "%s"\nsavestate_directory = "%s"\nconfig_save_on_exit = "false"\n' "$d" "$d" > "$d/common.cfg"
lock0=$(gsettings get org.gnome.settings-daemon.peripherals.touchscreen orientation-lock)
gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock true
NOWA="env -u FD_MESA_DEBUG -u IR3_SHADER_DEBUG -u GSK_RENDERER"
run() { tag=$1; envp=$2; printf '%b' "$3" > "$d/$tag.cfg"; n=${4:-900}; U
	t0=$(cut -d' ' -f1 /proc/uptime)
	systemd-run --user --wait --quiet --unit="ra-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 \
		$envp retroarch --max-frames=$n --config "$d/base.cfg" --appendconfig "$d/common.cfg|$d/$tag.cfg" \
		-L "$core" "$d/test.${rom##*.}" >/dev/null 2>&1
	t1=$(cut -d' ' -f1 /proc/uptime)
	echo "$t0 $t1" | awk -v tag="$tag" -v n="$n" -v tr="$(cur)" '{ printf "rot %s %-10s %5.1f s for %d frames\n", tr, tag, $2 - $1, n }'
	sleep 1; }
VARIANTS=${VARIANTS:-std}
for t in $transforms; do [ "$t" = cur ] || { rot "$t"; sleep 2; }
	if [ "$VARIANTS" = std ]; then
	run A_now "" ""
	run B_nowa "$NOWA" ""
	run C_thread "$NOWA" 'video_threaded = "true"\n'
	run D_full "$NOWA" 'video_fullscreen = "true"\n'
	else
	run O_startup "$NOWA" 'video_fullscreen = "true"\n' 1
	run D_full "$NOWA" 'video_fullscreen = "true"\n'
	run E_fullthr "$NOWA" 'video_fullscreen = "true"\nvideo_threaded = "true"\n'
	run F_full_wa "" 'video_fullscreen = "true"\n'
	fi
done
gsettings set org.gnome.settings-daemon.peripherals.touchscreen orientation-lock "$lock0"
