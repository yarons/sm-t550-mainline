#!/bin/sh
# faultcatch2.sh <max-launches> — like gpu-pm/faultcatch.sh but detects faults exactly via the iommu:io_page_fault
# tracepoint and also traces iommu:unmap + msm shrinker/purge, so the faulting buffer's unmap can be found.
# Output ~/faultcatch2/{summary,trace,dmesg,gem}.txt
MAX=${1:-90}; D=$HOME/faultcatch2; T=/sys/kernel/tracing
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
EV="iommu/io_page_fault iommu/unmap drm_msm_gpu/msm_gpu_submit drm_msm_gpu/msm_gpu_submit_retired drm_msm_gpu/msm_gem_shrink drm_msm_gpu/msm_gem_purge_vmaps drm_msm_gpu/msm_gpu_resume drm_msm_gpu/msm_gpu_suspend"
rm -rf "$D"; mkdir -p "$D"
S sh -c "echo 0 > $T/tracing_on; echo > $T/trace; echo 16384 > $T/buffer_size_kb; for e in $EV; do echo 1 > $T/events/\$e/enable; done; echo 1 > $T/tracing_on"
gnome-session-inhibit --inhibit idle --inhibit-only >/dev/null 2>&1 & INH=$!
nf() { S grep -c 'io_page_fault:' $T/trace; }
apps="kgx org.gnome.Snapshot gnome-text-editor org.gnome.Calculator gnome-clocks org.gnome.Nautilus"
i=0; hit=
while [ $i -lt "$MAX" ] && [ -z "$hit" ]; do
  for a in $apps; do
    i=$((i + 1)); t0=$(cut -d' ' -f1 /proc/uptime)
    gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
      --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
    case $a in org.*) gapplication launch $a >/dev/null 2>&1 & ;; *) systemd-run --user --collect -q $a >/dev/null 2>&1 ;; esac
    sleep 9
    pkill -x snapshot; pkill -x kgx; pkill -f gnome-text-editor; pkill -f gnome-calculator; pkill -f gnome-clocks; pkill -x nautilus
    sleep 2
    n=$(nf); echo "launch $i $a at ${t0}s: faults so far $n" >> "$D/summary.txt"
    if [ "$n" -gt 0 ]; then hit=$a; break; fi
  done
done
kill $INH
S sh -c "echo 0 > $T/tracing_on"
S cat $T/trace > "$D/trace.txt"; S dmesg > "$D/dmesg.txt"; S cat /sys/kernel/debug/dri/0/gem > "$D/gem.txt"
S sh -c "for e in $EV; do echo 0 > $T/events/\$e/enable; done; echo > $T/trace; echo 1 > $T/tracing_on"
echo "RESULT: ${hit:-no fault} after $i launches" >> "$D/summary.txt"; echo done >> "$D/summary.txt"
