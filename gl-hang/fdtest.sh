#!/bin/sh
# Snapshot with the test Mesa in ~/mesatest (Snapshot only), black frames + GPU fault lines per env variant.
#   fdtest.sh "<env assignments>" ...     e.g. "" "FD_GT510=1" "FD_MESA_DEBUG=inorder"
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
F=/usr/share/dbus-1/services/org.gnome.Snapshot.service
T=$HOME/mesatest/root/usr/lib
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
cnt() { S dmesg | grep -cE "msm_gpu_fault_handler|\*\*\* fault"; }
S cp "$F" /root/snapshot.service.orig
trap 'S cp /root/snapshot.service.orig "$F"' EXIT
for v in "$@"; do
	e="env -u FD_MESA_DEBUG LD_LIBRARY_PATH=$T LIBGL_DRIVERS_PATH=$T/dri GBM_BACKENDS_PATH=$T/gbm GSK_RENDERER=gl IR3_SHADER_DEBUG=nouboopt $v"
	S sed -i "s|^Exec=.*|Exec=$e /usr/bin/snapshot --gapplication-service|" "$F"
	pkill -x snapshot; sleep 2; U; f0=$(cnt)
	gapplication launch org.gnome.Snapshot; sleep 12; U; sleep 1
	p=$(pgrep -x snapshot)
	if [ -z "$p" ]; then printf '%-28s DID NOT START\n' "[$v]"; continue; fi
	lib=$(grep -c "$T/libgallium" /proc/$p/maps)
	S ffmpeg -loglevel error -nostats -y -device /dev/dri/card0 -f kmsgrab -framerate 30 -i - -t 2 \
		-vf "hwdownload,format=bgr0,crop=384:512:192:256,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-" \
		-f null - 2>/dev/null | grep -oE "YAVG=[0-9.]+" | cut -d= -f2 > "$HOME/yavg.txt"
	n=$(wc -l < "$HOME/yavg.txt"); black=$(awk '$1 < 20' "$HOME/yavg.txt" | wc -l)
	c1=$(awk '{print $14+$15}' /proc/$p/stat); sleep 3; c2=$(awk '{print $14+$15}' /proc/$p/stat)
	f1=$(cnt)
	printf '%-28s testlib=%s black %2d/%-2d cpu %3d%% new-fault-lines %s\n' "[$v]" "$lib" "$black" "$n" $(( (c2 - c1) / 3 )) $((f1 - f0))
done
pkill -x snapshot
S cp /root/snapshot.service.orig "$F"; S rm /root/snapshot.service.orig
grep ^Exec "$F"
