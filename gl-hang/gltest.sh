#!/bin/sh
# Run a GTK4 app with GSK_RENDERER=gl under a GPU-hang watchdog (a306 / freedreno).
#   gltest.sh <seconds> <tag> <app> [VAR=value ...]
# Kills the app at the first msm hangcheck, saves the devcoredump to /tmp/gpucrash-<tag>.bin
# and prints one verdict line. Run as the session user; uses sudo (password $SUDO_PW, default 147147) for dmesg.
set -u
secs=$1 tag=$2 app=$3
shift 3
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }

envs="-E WAYLAND_DISPLAY=wayland-0 -E GSK_RENDERER=gl -E APERTURE_OPTIMAL_RATIO=4:3"
for kv in "$@"; do envs="$envs -E $kv"; done

unit=gltest-$tag
systemctl --user stop "$unit" 2>/dev/null
# drop dumps left by earlier runs (a late devcoredump from the previous hang otherwise lands here)
for d in /sys/class/devcoredump/devcd*; do [ -e "$d/data" ] && echo 1 | S tee "$d/data" >/dev/null; done
rm -f "/tmp/gpucrash-$tag.bin"
S dmesg -c >/dev/null
# shellcheck disable=SC2086
systemd-run --user --unit="$unit" --collect $envs "$app" >/dev/null 2>&1

verdict=OK
i=0
while [ $i -lt "$secs" ]; do
	sleep 1
	i=$((i + 1))
	if S dmesg | grep -q "hangcheck detected gpu lockup"; then
		verdict="HANG@${i}s"
		break
	fi
	systemctl --user is-active -q "$unit" || { verdict="EXITED@${i}s"; break; }
done
systemctl --user stop "$unit" 2>/dev/null
sleep 2
faults=$(S dmesg | grep -c "fault")
for d in /sys/class/devcoredump/devcd*; do
	[ -e "$d/data" ] || continue
	S cat "$d/data" > "/tmp/gpucrash-$tag.bin"
	echo 1 | S tee "$d/data" >/dev/null	# free it
done
echo "$tag: $verdict faults=$faults env=[$*] dump=$(ls /tmp/gpucrash-$tag.bin 2>/dev/null || echo none)"
