#!/bin/sh
# relaunch.sh <n> <secs> <app...> — start/stop an app n times (systemd-run, GSK gl), sleep 1 between.
N=$1; SECS=$2; shift 2; i=0
while [ $i -lt "$N" ]; do
  i=$((i + 1))
  systemd-run --user --collect -q --unit=relaunch-$$-$i -E GSK_RENDERER=gl -E WAYLAND_DISPLAY=wayland-0 "$@" >/dev/null 2>&1
  sleep "$SECS"; systemctl --user stop relaunch-$$-$i 2>/dev/null; sleep 1
done
