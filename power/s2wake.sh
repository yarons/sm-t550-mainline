#!/bin/sh
# s2wake.sh <blank|lit> <secs> — one s2idle cycle with an RTC wake after <secs>, the panel blanked or lit at entry.
# Logs before/after to /home/user/s2wake.out; a missing "after" line + a new boot = the cycle reset the tablet. Root:
#   systemd-run --unit=s2wake --collect /home/user/s2wake.sh blank 10
MODE=${1:-blank}; S=${2:-10}; O=/home/user/s2wake.out; R=/sys/class/rtc/rtc0
BUS=unix:path=/run/user/$(id -u user)/bus
log() { echo "$(date +%T) $*" >> $O; sync; }
psm() { su user -c "DBUS_SESSION_BUS_ADDRESS=$BUS gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 $1>'" >/dev/null 2>&1; }
if [ "$MODE" = lit ]; then psm 0; else psm 3; fi
sleep 5
log "before $MODE ${S}s: boot $(cat /proc/sys/kernel/random/boot_id | cut -c1-8) up $(cut -d. -f1 /proc/uptime)s success=$(cat /sys/power/suspend_stats/success) charger=$(cat /sys/class/power_supply/max77693-charger/online)"
echo 0 > $R/wakealarm; echo +"$S" > $R/wakealarm; t=$(date +%s)
echo freeze > /sys/power/state; rc=$?
log "after: rc=$rc slept $(( $(date +%s) - t ))s wake_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null) success=$(cat /sys/power/suspend_stats/success) fail=$(cat /sys/power/suspend_stats/fail)"
sleep 3; psm 0
