#!/bin/sh
# gpustress.sh [on|auto] [tag] — GPU runtime suspend/resume stress (default auto; needs the a306 VBIF mask fix).
# Phases: blank/unblank, 4 GTK apps x2 (gltest.sh hang watchdog), Snapshot x3, glmark2 scenes, idle gaps between.
# Counts GPU runtime-PM transitions (ftrace rpm_status) and msm hang/fault lines per phase. -> ~/gpustress.out
MODE=${1:-auto}; O=$HOME/gpustress${2:+-$2}.out; G=/sys/devices/platform/soc@0/1c00000.gpu/power; T=/sys/kernel/tracing
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
: > "$O"
S sh -c "echo $MODE > $G/control; echo 0 > $T/tracing_on; echo > $T/trace; echo 'name == \"1c00000.gpu\"' > $T/events/rpm/rpm_status/filter; echo 1 > $T/events/rpm/rpm_status/enable; echo 8192 > $T/buffer_size_kb; echo 1 > $T/tracing_on"
bad() { S dmesg | grep -c -E 'hangcheck|msm_gpu_fault|\*\*\* fault|gpu lockup|recover'; }
trans() { S cat $T/trace | grep -c 'status=RPM_ACTIVE'; }
phase() { echo "[$1] resumes so far=$(trans) bad-lines(since last dmesg -c)=$(bad) status=$(cat $G/runtime_status)" >> "$O"; }
S dmesg -c >/dev/null
~/blanktest.sh 5 3 3; phase blank
for r in 1 2; do
  for a in gnome-calculator gnome-text-editor kgx gnome-clocks; do
    ~/gltest.sh 8 "pm-$a-$r" "$a" >> "$O" 2>&1; sleep 2
  done
done
phase gtk
for r in 1 2 3; do gapplication launch org.gnome.Snapshot >/dev/null 2>&1 & sleep 15; pkill -x snapshot; sleep 3; done
phase snapshot
systemd-run --user --unit=pm-glmark --collect -E WAYLAND_DISPLAY=wayland-0 glmark2-es2-wayland -s 768x1024 \
  -b build:duration=3 -b texture:duration=3 -b shading:duration=3 -b refract:duration=3 -b terrain:duration=3 >/dev/null 2>&1
for i in $(seq 1 40); do systemctl --user is-active -q pm-glmark || break; sleep 1; done
systemctl --user stop pm-glmark 2>/dev/null
journalctl --user -u pm-glmark --no-pager -o cat | grep -E "glmark2 Score|FPS:" | tail -6 >> "$O"
phase glmark
sleep 10; phase idle10s
S sh -c "echo 0 > $T/events/rpm/rpm_status/enable; echo > $T/events/rpm/rpm_status/filter"
echo "MODE=$MODE TOTAL resumes=$(trans) suspended_ms=$(cat $G/runtime_suspended_time) active_ms=$(cat $G/runtime_active_time)" >> "$O"
echo done >> "$O"
