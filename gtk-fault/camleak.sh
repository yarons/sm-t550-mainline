#!/bin/sh
# camleak.sh <n> — camera-service GPU memory per Snapshot session: restart wireplumber@video-capture (Snapshot
# closed), then n launch/close cycles; prints the service's drm-total/resident memory after each. -> ~/camleak.out
N=${1:-4}; O=$HOME/camleak.out
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
mem() { p=$(systemctl --user show -p MainPID --value wireplumber@video-capture)
  for f in /proc/$p/fdinfo/*; do grep -q drm-driver "$f" 2>/dev/null && { grep -E "drm-total-memory|drm-resident-memory" "$f" | awk '{printf "%s %s%s ", $1, $2, $3}'; break; }; done
  echo "rss=$(awk '/VmRSS/{print $2$3}' /proc/$p/status)"; }
gnome-session-inhibit --inhibit idle --inhibit-only >/dev/null 2>&1 & INH=$!
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
pkill -x snapshot; sleep 2
echo "before restart: $(mem)" > "$O"
systemctl --user restart wireplumber@video-capture; sleep 8
echo "after restart:  $(mem)" >> "$O"
i=0; while [ $i -lt "$N" ]; do i=$((i+1)); gapplication launch org.gnome.Snapshot >/dev/null 2>&1 & sleep 12; pkill -x snapshot; sleep 4
  echo "after session $i: $(mem)" >> "$O"; done
kill $INH; echo done >> "$O"
