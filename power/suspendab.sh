#!/bin/sh
# suspendab.sh [secs] — suspend vs idle A/B on battery: waits until the charger is unplugged (the battery reports
# "Full", not "Discharging", at 100 %), then suspendtest.sh suspend <secs> and idle <secs>. logind sleep + lid handling
# is blocked for the whole run (GNOME suspends after 15 min idle on battery; the hall sensor's lid switch suspends too);
# suspendtest.sh writes /sys/power/state itself, which inhibitors don't affect. Run as root:
#   systemd-run --unit=suspendab --collect /home/user/suspendab.sh 900
S=${1:-900}; C=/sys/class/power_supply/max77693-charger; O=/home/user/suspendtest.out
echo "$(date +%T) waiting for unplug (charger online=$(cat $C/online))" >> $O
while [ "$(cat $C/online)" != 0 ]; do sleep 5; done
echo "$(date +%T) unplugged" >> $O; sleep 30
exec systemd-inhibit --what=sleep:idle:handle-lid-switch --who=suspendab --why="suspend/idle power A/B" \
	sh -c "/home/user/suspendtest.sh suspend $S; /home/user/suspendtest.sh idle $S"
