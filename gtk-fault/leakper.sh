#!/bin/sh
# leakper.sh <n> — per-app GEM leak: resident objects/bytes before and after n launch/close cycles of each app.
N=${1:-5}; O=$HOME/leakper.out
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
res() { S grep '^Resident:' /sys/kernel/debug/dri/0/gem | awk '{print $2, int($4/1048576)"MB"}'; }
gnome-session-inhibit --inhibit idle --inhibit-only >/dev/null 2>&1 & INH=$!
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
: > "$O"; sleep 3
for a in kgx org.gnome.Snapshot gnome-text-editor org.gnome.Calculator gnome-clocks org.gnome.Nautilus python3; do
  b=$(res); i=0
  while [ $i -lt "$N" ]; do
    i=$((i + 1))
    case $a in org.*) gapplication launch $a >/dev/null 2>&1 & ;;
      python3) systemd-run --user --collect -q -E GSK_RENDERER=gl python3 /home/user/resizetest.py relaunch 6 ;;
      *) systemd-run --user --collect -q $a >/dev/null 2>&1 ;; esac
    sleep 9
    pkill -x snapshot; pkill -x kgx; pkill -f gnome-text-editor; pkill -f gnome-calculator; pkill -f gnome-clocks; pkill -x nautilus; pkill -f resizetest.py
    sleep 3
  done
  echo "$a: before $b -> after $(res)" >> "$O"
done
kill $INH; echo done >> "$O"
