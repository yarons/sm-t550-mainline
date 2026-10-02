#!/bin/sh
# faulttrace.sh <tag> <cmd...> — run <cmd> with GPU iommu faults counted exactly (ftrace iommu:io_page_fault,
# plus iommu:unmap and drm_msm_gpu submit/retire for timing). Prints one line; trace kept in ~/ft-<tag>.txt
TAG=$1; shift; T=/sys/kernel/tracing
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
S sh -c "echo 0 > $T/tracing_on; echo > $T/trace; echo 16384 > $T/buffer_size_kb
  for e in iommu/io_page_fault iommu/unmap drm_msm_gpu/msm_gpu_submit drm_msm_gpu/msm_gpu_submit_retired drm_msm_gpu/msm_gem_shrink drm_msm_gpu/msm_gem_purge_vmaps; do echo 1 > $T/events/\$e/enable; done
  echo 1 > $T/tracing_on"
# screen must be on (a blanked output = unmapped windows = no frames); hold the session idle inhibitor meanwhile
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
gnome-session-inhibit --inhibit idle --inhibit-only >/dev/null 2>&1 & INH=$!
sleep 1
"$@"
kill $INH 2>/dev/null
S sh -c "echo 0 > $T/tracing_on"
S cat $T/trace > "$HOME/ft-$TAG.txt"
S sh -c "for e in iommu/io_page_fault iommu/unmap drm_msm_gpu/msm_gpu_submit drm_msm_gpu/msm_gpu_submit_retired drm_msm_gpu/msm_gem_shrink drm_msm_gpu/msm_gem_purge_vmaps; do echo 0 > $T/events/\$e/enable; done; echo > $T/trace; echo 1 > $T/tracing_on"
n=$(grep -c "io_page_fault:" "$HOME/ft-$TAG.txt")
echo "$TAG: gpu-iommu faults=$n first=$(grep -m1 'io_page_fault:' "$HOME/ft-$TAG.txt" | grep -o 'iova=0x[0-9a-f]*')"
