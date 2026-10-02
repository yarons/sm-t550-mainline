#!/bin/sh
# Run Snapshot (D-Bus launch) with extra env for <secs>, save its journal to ~/snapenv.log, restore the service.
#   snapenv.sh <secs> "<env assignments>"
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
F=/usr/share/dbus-1/services/org.gnome.Snapshot.service
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
U() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null; }
S cp "$F" /root/snapshot.service.orig
trap 'S cp /root/snapshot.service.orig "$F"; S rm -f /root/snapshot.service.orig; pkill -x snapshot' EXIT
S sed -i "s|^Exec=.*|Exec=env GSK_RENDERER=gl IR3_SHADER_DEBUG=nouboopt FD_MESA_DEBUG=inorder $2 /usr/bin/snapshot --gapplication-service|" "$F"
grep ^Exec "$F"
pkill -x snapshot; sleep 2; U
t0=$(date '+%Y-%m-%d %H:%M:%S')
gapplication launch org.gnome.Snapshot; sleep "$1"
journalctl --user --since "$t0" --no-pager -o cat > "$HOME/snapenv.log"
wc -l "$HOME/snapenv.log"
