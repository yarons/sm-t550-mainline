#!/bin/sh
# Snapshot black-frame count per FD_MESA_DEBUG value (app-grid style D-Bus launch).
# Edits Snapshot's D-Bus service Exec for each run and restores the packaged file at the end.
#   fdvar.sh "<value>" ["<value>"...]      ("" = no FD_MESA_DEBUG at all)
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
F=/usr/share/dbus-1/services/org.gnome.Snapshot.service
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
S cp "$F" /root/snapshot.service.orig
for v in "$@"; do
	if [ -n "$v" ]; then e="env GSK_RENDERER=gl IR3_SHADER_DEBUG=nouboopt FD_MESA_DEBUG=$v"
	else e="env -u FD_MESA_DEBUG GSK_RENDERER=gl IR3_SHADER_DEBUG=nouboopt"; fi
	S sed -i "s|^Exec=.*|Exec=$e /usr/bin/snapshot --gapplication-service|" "$F"
	pkill -x snapshot; sleep 2; U
	f0=$(S dmesg | grep -cE "hangcheck|\*\*\* fault")
	gapplication launch org.gnome.Snapshot; sleep 12; U; sleep 1
	p=$(pgrep -x snapshot); got=$(tr '\0' '\n' < /proc/$p/environ | grep '^FD_MESA_DEBUG=' | cut -d= -f2)
	# centre of the framebuffer = viewfinder in both orientations; limited range: black < 20
	S ffmpeg -loglevel error -nostats -y -device /dev/dri/card0 -f kmsgrab -framerate 30 -i - -t 2 \
		-vf "hwdownload,format=bgr0,crop=384:512:192:256,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
		-f null - 2>/dev/null | grep -oE "YAVG=[0-9.]+" | cut -d= -f2 > "$HOME/yavg.txt"
	n=$(wc -l < "$HOME/yavg.txt"); black=$(awk '$1 < 20' "$HOME/yavg.txt" | wc -l)
	c1=$(awk '{print $14+$15}' /proc/$p/stat); sleep 3; c2=$(awk '{print $14+$15}' /proc/$p/stat)
	f1=$(S dmesg | grep -cE "hangcheck|\*\*\* fault")
	printf 'FD_MESA_DEBUG=%-12s black %2d/%-2d  snapshot cpu %3d%%  new gpu faults %s\n' "[$got]" "$black" "$n" $(( (c2 - c1) / 3 )) $((f1 - f0))
done
pkill -x snapshot
S cp /root/snapshot.service.orig "$F"; S rm /root/snapshot.service.orig
grep ^Exec "$F"
