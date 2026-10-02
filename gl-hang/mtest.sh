#!/bin/sh
# Run <app> with the TEST Mesa (~/mesatest) + env under a GPU-hang watchdog; kill it at the first hang.
#   mtest.sh <secs> <app> "<env assignments>"
set -u
secs=$1 app=$2 extra=$3
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
T=$HOME/mesatest/root/usr/lib
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
envs="-E WAYLAND_DISPLAY=wayland-0 -E GSK_RENDERER=gl -E LD_LIBRARY_PATH=$T -E LIBGL_DRIVERS_PATH=$T/dri -E GBM_BACKENDS_PATH=$T/gbm"
for kv in $extra; do envs="$envs -E $kv"; done
S dmesg -c >/dev/null
# shellcheck disable=SC2086
systemd-run --user --unit=mtest --collect $envs -p UnsetEnvironment="FD_MESA_DEBUG IR3_SHADER_DEBUG" "$app" >/dev/null 2>&1
verdict=OK i=0
while [ $i -lt "$secs" ]; do
	sleep 1; i=$((i + 1))
	if S dmesg | grep -qE "hangcheck|gpu lockup|recover"; then verdict="HANG@${i}s"; break; fi
	systemctl --user is-active -q mtest || { verdict="EXITED@${i}s"; break; }
done
p=$(systemctl --user show -p MainPID --value mtest)
lib=$(grep -c "$T/libgallium" /proc/$p/maps 2>/dev/null)
envp=$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | grep -E "^(FD_|IR3_)" | tr '\n' ' ')
systemctl --user stop mtest 2>/dev/null; sleep 1
echo "$app [$extra]: $verdict testlib=$lib env=[$envp] faults=$(S dmesg | grep -cE 'context fault|\*\*\* fault|msm_gpu_fault')"
S dmesg | grep -E "hangcheck|lockup|fault|recover" | head -5
