#!/bin/sh
# powertest.sh — battery current per configuration, on battery, screen off. Run as root:
#   systemd-run --unit=powertest /home/user/powertest.sh
# Waits until the battery discharges (USB unplugged), then: baseline, Wi-Fi radio off, modem DSP stopped,
# baseline again, screen on. 60 s settle + 360 s (screen on: 180 s) of 2 s current_now samples per phase.
# Results: /home/user/powertest.out (summary), /home/user/powertest.csv (samples). Restores Wi-Fi, the modem
# DSP and rmtfs; reboots only if the sound card did not come back.
B=/sys/class/power_supply/max170xx_battery
O=/home/user/powertest.out; C=/home/user/powertest.csv
BUS=unix:path=/run/user/$(id -u user)/bus
psm() { su user -c "DBUS_SESSION_BUS_ADDRESS=$BUS gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 $1>'" >/dev/null 2>&1; }
log() { echo "$(date +%T) $*" >> $O; }
: > $O; echo "t,phase,uA,uV,cap" > $C; chown user:user $O $C
log "waiting for discharge (unplug USB)"
while [ "$(cat $B/status)" != Discharging ]; do sleep 5; done
log "discharging, cap $(cat $B/capacity)%"
measure() { # $1 phase, $2 seconds, $3 screen mode (3 off / 0 on)
	psm "$3"; sleep 60; n=0; sum=0; end=$(( $(date +%s) + $2 ))
	while [ "$(date +%s)" -lt "$end" ]; do
		i=$(cat $B/current_now); echo "$(date +%s),$1,$i,$(cat $B/voltage_now),$(cat $B/capacity)" >> $C
		n=$((n + 1)); sum=$((sum + i)); sleep 2
	done
	log "$1: mean $(( sum / n / 1000 )) mA ($n samples), V $(( $(cat $B/voltage_now) / 1000 )) mV, cap $(cat $B/capacity)%, bmps_errors $(dmesg | grep -c 'Can not enter BMPS'), wifi $(nmcli -t -f WIFI g)"
}
measure baseline 360 3
nmcli radio wifi off; measure wifi-off 360 3; nmcli radio wifi on
echo stop > /sys/class/remoteproc/remoteproc0/state 2>> $O
log "modem state: $(cat /sys/class/remoteproc/remoteproc0/state) ($(cat /sys/class/remoteproc/remoteproc0/name))"
measure modem-stopped 360 3
echo start > /sys/class/remoteproc/remoteproc0/state 2>> $O; sleep 10; systemctl restart rmtfs; sleep 20
measure baseline2 360 3
measure screen-on 180 0
psm 3
cards=$(aplay -l 2>/dev/null | grep -c samsunggt510)
log "restored: wifi $(nmcli -t -f WIFI g), modem $(cat /sys/class/remoteproc/remoteproc0/state), sound cards $cards"
log done
[ "$cards" -gt 0 ] || { log "no sound card: rebooting"; systemctl reboot; }
