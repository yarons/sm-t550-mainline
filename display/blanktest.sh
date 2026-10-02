#!/bin/sh
# blanktest.sh <cycles> [on_secs] [off_secs] — PowerSaveMode on/off cycles; logs MDP iommu faults,
# vblank timeouts, DSI write errors per unblank. Output: ~/blanktest.out. Leaves the screen in its start state.
N=${1:-5}; ON=${2:-3}; OFF=${3:-3}
OUT=$HOME/blanktest.out
psm() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 $1>" >/dev/null; }
get() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Get org.gnome.Mutter.DisplayConfig PowerSaveMode | tr -dc 0-9; }
cnt() { echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep -c -E "$1"; }
START=$(get)
: > "$OUT"
echo "start PowerSaveMode=$START" >> "$OUT"
i=1
while [ $i -le $N ]; do
  f0=$(cnt 'context fault'); v0=$(cnt 'vblank time out'); d0=$(cnt 'sending dcs data .* failed')
  psm 0; sleep "$ON"
  f1=$(cnt 'context fault'); v1=$(cnt 'vblank time out'); d1=$(cnt 'sending dcs data .* failed')
  psm 3; sleep "$OFF"
  f2=$(cnt 'context fault'); v2=$(cnt 'vblank time out'); d2=$(cnt 'sending dcs data .* failed')
  echo "cycle $i on: faults+$((f1-f0)) vblank+$((v1-v0)) dcs+$((d1-d0)) | off: faults+$((f2-f1)) vblank+$((v2-v1)) dcs+$((d2-d1)) bl=$(cat /sys/class/backlight/*/brightness)" >> "$OUT"
  i=$((i+1))
done
psm "$START"
echo done >> "$OUT"
