#!/bin/sh
# kprobe-leak.sh <n> — kprobe msm GEM lifetime (new/import/open/close/export/dmabuf release/vma get/put/free)
# around n Snapshot launch/close cycles; trace -> ~/kleak.txt
N=${1:-2}; T=/sys/kernel/tracing
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
S sh -c "echo 0 > $T/tracing_on; echo > $T/trace; echo > $T/kprobe_events; echo 16384 > $T/buffer_size_kb
cat >> $T/kprobe_events <<K
r:gk/gnew msm_gem_new ret=\\\$retval size=+0(\\\$retval):u64
r:gk/gimport msm_gem_import ret=\\\$retval
p:gk/gopen msm_gem_open obj=%x0 file=%x1
p:gk/gclose msm_gem_close obj=%x0 file=%x1
p:gk/vget msm_gem_vma_get obj=%x0
p:gk/vput msm_gem_vma_put obj=%x0
p:gk/pexport msm_gem_prime_export obj=%x0
r:gk/pimport msm_gem_prime_import ret=\\\$retval
p:gk/dbrel msm_gem_dmabuf_release dmabuf=%x0
p:gk/putiova put_iova_spaces obj=%x0 vm=%x1 close=%x2
p:gk/gfree msm_gem_free_object obj=%x0
K
echo 1 > $T/events/gk/enable; echo 1 > $T/tracing_on" || { echo "kprobe setup failed"; S cat $T/error_log | tail -5; exit 1; }
gnome-session-inhibit --inhibit idle --inhibit-only >/dev/null 2>&1 & INH=$!
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 0>" >/dev/null
sleep 3; i=0
while [ $i -lt "$N" ]; do i=$((i+1)); gapplication launch org.gnome.Snapshot >/dev/null 2>&1 & sleep 12; pkill -x snapshot; sleep 5; done
sleep 5; kill $INH
S sh -c "echo 0 > $T/tracing_on; cat $T/trace > /home/user/kleak.txt; echo 0 > $T/events/gk/enable; echo > $T/kprobe_events; echo > $T/trace; echo 1 > $T/tracing_on"
echo "done $(grep -c ': ' /home/user/kleak.txt) lines"
