#!/bin/sh
# stalepipe.sh [cycles] — kernel 0125 check: suspend (s2idle, RTC wake after 10 s) with the panel LIT, then blank and
# unblank via PowerSaveMode. Stock mdp5 after such a resume: WARN in mdp5_pipe_release + phoc "Failed to commit power
# mode change" and the CRTC stays active while blanked. Run as root:
#   systemd-run --unit=stalepipe --collect /home/user/stalepipe.sh 3
# Results appended to /home/user/stalepipe.out. Leaves the screen on.
N=${1:-3}; O=/home/user/stalepipe.out; R=/sys/class/rtc/rtc0; S=/sys/kernel/debug/dri/0/state
BUS=unix:path=/run/user/$(id -u user)/bus
log() { echo "$(date +%T) $*" >> $O; }
psm() { su user -c "DBUS_SESSION_BUS_ADDRESS=$BUS gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 $1>'" >/dev/null 2>&1; }
warns() { dmesg | grep -c 'mdp5_pipe.c:138'; }
crtc() { awk '/^crtc\[/{c=1} c && /active=/{print $1; exit}' $S; }
pipes() { awk '/^plane\[/{p=$2} /hwpipe=/{printf "%s:%s ", p, substr($1, 8)}' $S; }
log "== $(uname -r) $(cat /proc/sys/kernel/tainted 2>/dev/null | sed 's/^/tainted=/') warns=$(warns)"
i=0
while [ $i -lt "$N" ]; do
	i=$((i + 1))
	psm 0; sleep 3
	log "cycle $i lit: $(crtc) $(pipes)"
	echo 0 > $R/wakealarm; echo +10 > $R/wakealarm; sync; echo freeze > /sys/power/state
	sleep 5
	log "cycle $i resumed: $(crtc) $(pipes) warns=$(warns)"
	psm 3; sleep 3
	log "cycle $i blanked: $(crtc) $(pipes) warns=$(warns) bl=$(cat /sys/class/backlight/*/actual_brightness)"
done
psm 0; sleep 2
log "end: $(crtc) $(pipes) warns=$(warns); phoc failures this run: $(journalctl -b --no-pager --since "-$((N * 30 + 10))s" | grep -c 'Failed to commit power mode change')"
