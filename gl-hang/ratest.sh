#!/bin/sh
# RetroArch frame-rate probe: run a ROM copy under several settings, count GPU jobs per process
# for 3 s (msm_gpu_submit_retired) = frames/s for retroarch and phoc.
#   ratest.sh <rom> <core.so>
rom=$1; core=$2
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
d=$HOME/ratest; rm -rf "$d"; mkdir -p "$d"
cp "$rom" "$d/test.${rom##*.}"
cp "$HOME/.config/retroarch/retroarch.cfg" "$d/base.cfg"
printf 'savefile_directory = "%s"\nsavestate_directory = "%s"\nconfig_save_on_exit = "false"\n' "$d" "$d" > "$d/common.cfg"
run() { # tag, env prefix, extra cfg lines
	tag=$1; envp=$2; printf '%b' "$3" > "$d/$tag.cfg"
	U
	systemd-run --user --unit="ra-$tag" --collect -E WAYLAND_DISPLAY=wayland-0 \
		$envp retroarch --config "$d/base.cfg" --appendconfig "$d/common.cfg|$d/$tag.cfg" \
		-L "$core" "$d/test.${rom##*.}" >/dev/null 2>&1
	sleep 12; U
	S sh -c 'T=/sys/kernel/tracing; echo > $T/trace; echo 1 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable;
		echo 1 > $T/tracing_on; sleep 3; echo 0 > $T/tracing_on;
		echo 0 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable; cat $T/trace' > "$d/$tag.trace"
	P=$(systemctl --user show -p MainPID --value "ra-$tag")
	cpu0=$(awk '{print $14+$15}' /proc/$P/stat 2>/dev/null); sleep 2; cpu1=$(awk '{print $14+$15}' /proc/$P/stat 2>/dev/null)
	systemctl --user stop "ra-$tag"; sleep 2
	awk -v tag="$tag" -v cpu=$(( (cpu1 - cpu0) / 2 )) '
	/msm_gpu_submit_retired/ { t = $4 + 0; match($0, /pid=[0-9]+/); p = substr($0, RSTART + 4, RLENGTH - 4)
		if (lt) { sum[p] += (t - lt) * 1000 } n[p]++; lt = t; first = first ? first : t; last = t }
	END { printf "%-10s", tag
		for (p in n) { c = "cat /proc/" p "/comm 2>/dev/null"; name = "gone"; c | getline name; close(c)
			printf "  %s %.1f fps (gpu %.1f ms)", name, n[p] / (last - first), sum[p] / n[p] }
		printf "  cpu %d%%\n", cpu }' "$d/$tag.trace"
}
run A_now "" ""
run B_nowa "env -u FD_MESA_DEBUG -u IR3_SHADER_DEBUG -u GSK_RENDERER" ""
run C_thread "env -u FD_MESA_DEBUG -u IR3_SHADER_DEBUG -u GSK_RENDERER" 'video_threaded = "true"\n'
run D_full "env -u FD_MESA_DEBUG -u IR3_SHADER_DEBUG -u GSK_RENDERER" 'video_fullscreen = "true"\n'
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null | grep -oE "\(0, 0, 1\.0, uint32 [0-9]" | head -1
