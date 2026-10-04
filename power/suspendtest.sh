#!/bin/sh
# suspendtest.sh <idle|suspend> <secs> — average battery current over <secs> from the gauge's coulomb counter, either
# awake with the screen off (idle) or in s2idle with an RTC wake alarm (suspend). Run as root:
#   systemd-run --unit=suspendtest /home/user/suspendtest.sh suspend 900
# Results appended to /home/user/suspendtest.out (+ kernel messages around the suspend).
MODE=${1:-suspend}; S=${2:-600}; B=/sys/class/power_supply/max170xx_battery; O=/home/user/suspendtest.out
R=/sys/class/rtc/rtc0
BUS=unix:path=/run/user/$(id -u user)/bus
log() { echo "$(date +%T) $*" >> $O; }
psm() { su user -c "DBUS_SESSION_BUS_ADDRESS=$BUS gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 $1>'" >/dev/null 2>&1; }
log "== $MODE $S s: status $(cat $B/status), cap $(cat $B/capacity)%, states [$(cat /sys/power/state)] mem_sleep [$(cat /sys/power/mem_sleep 2>/dev/null)]"
psm 3; sleep 20
c0=$(cat $B/charge_counter); q0=$(cat $B/charge_now); t0=$(date +%s)
if [ "$MODE" = suspend ]; then
	# Re-suspend until $S seconds have passed; log each wake with the wakeup sources whose event count moved.
	W=/sys/kernel/debug/wakeup_sources; m0=$(dmesg | wc -l); n=0
	while [ $(( $(date +%s) - t0 )) -lt "$S" ]; do
		left=$(( S - ($(date +%s) - t0) ))
		awk 'NR>1{print $1, $3}' $W > /tmp/ws0
		echo 0 > $R/wakealarm; echo +$left > $R/wakealarm
		ts=$(date +%s); sync; echo freeze > /sys/power/state; rc=$?
		n=$((n + 1)); awk 'NR>1{print $1, $3}' $W > /tmp/ws1
		moved=$(awk 'NR==FNR{a[$1]=$2; next} ($1 in a) && $2 != a[$1] {printf "%s+%d ", $1, $2 - a[$1]}' /tmp/ws0 /tmp/ws1)
		log "cycle $n: rc=$rc slept $(( $(date +%s) - ts ))s, wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null) moved: $moved"
		sleep 3
	done
else
	sleep "$S"
fi
t1=$(date +%s); c1=$(cat $B/charge_counter); q1=$(cat $B/charge_now); dt=$((t1 - t0))
log "$MODE: ${dt}s, coulomb counter -$(( (c0 - c1) / 1000 )) mAh -> avg $(( (c0 - c1) * 36 / dt / 10 )) mA (charge_now: avg $(( (q0 - q1) * 36 / dt / 10 )) mA), cap $(cat $B/capacity)%"
[ "$MODE" = suspend ] && dmesg | tail -n +"$m0" | grep -v -E "^$" | tail -40 >> $O
log "done"
