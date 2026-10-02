#!/bin/sh
# Rates with Snapshot open (whatever launched it): sensor irq/s, GPU jobs/s per process (phoc jobs ≈ shown fps
# once the camera is offloaded to a subsurface), and CPU of snapshot/softisp.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
i1=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
S sh -c 'T=/sys/kernel/tracing; echo > $T/trace; echo 1 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable;
	echo 1 > $T/tracing_on; sleep 5; echo 0 > $T/tracing_on;
	echo 0 > $T/events/drm_msm_gpu/msm_gpu_submit_retired/enable; cat $T/trace' > "$HOME/disprate.trace"
i2=$(awk '/ispif/{print $2+$3+$4+$5}' /proc/interrupts)
jobs=$(awk '/msm_gpu_submit_retired/ { match($0, /pid=[0-9]+/); n[substr($0, RSTART + 4, RLENGTH - 4)]++ }
	END { for (p in n) { c = "cat /proc/" p "/comm 2>/dev/null"; name = ""; c | getline name; close(c)
		printf " %s %.1f/s", name, n[p] / 5 } }' "$HOME/disprate.trace")
echo "sensor=$(( (i2 - i1) / 5 ))/s gpu-jobs:$jobs"
