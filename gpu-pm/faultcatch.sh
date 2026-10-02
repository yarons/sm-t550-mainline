#!/bin/sh
# faultcatch.sh <max-launches> — launch GTK4 apps in a loop under ftrace (msm submit events) until the first GPU
# iommu fault burst ("*** fault"), then freeze the trace and save it with dmesg + GEM list for attribution.
# Output: ~/faultcatch/{summary,trace,dmesg,gem}.txt
MAX=${1:-60}; D=$HOME/faultcatch; T=/sys/kernel/tracing
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
rm -rf "$D"; mkdir -p "$D"
S sh -c "echo 0 > $T/tracing_on; echo > $T/trace; echo 32768 > $T/buffer_size_kb
  for e in msm_gpu_submit msm_gpu_submit_flush msm_gpu_submit_retired msm_gpu_resume msm_gpu_suspend; do echo 1 > $T/events/drm_msm_gpu/\$e/enable; done
  echo 1 > $T/tracing_on"
cnt() { S dmesg | grep -c '\*\*\* fault\|msm_gpu_fault_handler'; }
apps="kgx org.gnome.Snapshot gnome-text-editor org.gnome.Calculator gnome-clocks org.gnome.Nautilus"
base=$(cnt); i=0; hit=
while [ $i -lt "$MAX" ] && [ -z "$hit" ]; do
  for a in $apps; do
    i=$((i + 1)); t0=$(cut -d' ' -f1 /proc/uptime)
    case $a in org.*) gapplication launch $a >/dev/null 2>&1 & ;; *) systemd-run --user --collect -q $a >/dev/null 2>&1 ;; esac
    sleep 9
    pkill -x snapshot; pkill -x kgx; pkill -f gnome-text-editor; pkill -f gnome-calculator; pkill -f gnome-clocks; pkill -x nautilus
    sleep 2
    n=$(cnt)
    echo "launch $i $a at ${t0}s: fault lines $((n - base))" >> "$D/summary.txt"
    if [ "$n" -gt "$base" ]; then hit=$a; break; fi
  done
done
S sh -c "echo 0 > $T/tracing_on"
S cat $T/trace > "$D/trace.txt"
S dmesg > "$D/dmesg.txt"
S cat /sys/kernel/debug/dri/0/gem > "$D/gem.txt"
S sh -c "for e in msm_gpu_submit msm_gpu_submit_flush msm_gpu_submit_retired msm_gpu_resume msm_gpu_suspend; do echo 0 > $T/events/drm_msm_gpu/\$e/enable; done; echo > $T/trace; echo 1 > $T/tracing_on"
echo "RESULT: ${hit:-no fault} after $i launches" >> "$D/summary.txt"
echo done >> "$D/summary.txt"
