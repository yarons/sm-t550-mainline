#!/bin/sh
# kptiab.sh <tag> — boot-parameter A/B (kpti, serial console): syscall/IPC microbenchmarks with the performance
# governor (restored after), then whole-system CPU busy % while the rear camera streams in Snapshot (schedutil, as in
# normal use). Results in /home/user/kptiab-<tag>.out. Run as root:
#   systemd-run --unit=kptiab --collect /home/user/kptiab.sh A
T=${1:?tag}; O=/home/user/kptiab-$T.out; : > $O
log() { echo "$*" >> $O; }
busy() { awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat; }
log "== $T: $(cat /proc/cmdline | sed 's/pmos_boot_uuid.*//')"
log "kpti: $(dmesg | grep -oE 'page table isolation[^.]*' | head -1 || true); console: $(cat /proc/consoles | awk '{print $1}' | tr '\n' ' ')"
for c in /sys/devices/system/cpu/cpu[0-3]/cpufreq/scaling_governor; do echo performance > $c; done
sleep 5
for r in 1 2 3; do
	log "syscall basic #$r: $(perf bench syscall basic -l 2000000 2>&1 | grep -E 'usecs/op' | tr -s ' ')"
	log "sched pipe #$r: $(perf bench sched pipe -l 200000 2>&1 | grep -E 'usecs/op' | tr -s ' ')"
	log "sched messaging #$r: $(perf bench sched messaging -g 5 -l 200 2>&1 | grep -E 'Total time' | tr -s ' ')"
done
for c in /sys/devices/system/cpu/cpu[0-3]/cpufreq/scaling_governor; do echo schedutil > $c; done
# Rear camera streaming: Snapshot via the user's fronttest.sh, then whole-system CPU busy over 20 s.
su user -c "XDG_RUNTIME_DIR=/run/user/$(id -u user) /home/user/fronttest.sh Back 40 > /home/user/kptiab-cam-$T.txt 2>&1" &
sleep 18
set -- $(busy); b0=$1; t0=$2; sleep 20; set -- $(busy); b1=$1; t1=$2
log "camera streaming: system CPU busy $(( (b1 - b0) * 1000 / (t1 - t0) ))/1000 over 20 s"
wait
log "$(head -1 /home/user/kptiab-cam-$T.txt)"
pkill -x snapshot
log done
