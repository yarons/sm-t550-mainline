#!/bin/sh
# AVRCP button test (ISSUES 25): play /tmp/arp.wav in Decibels, then for $1 s log (a) AVCTP/AV-C frames from btmon,
# (b) key events on the headset's AVRCP uinput device, (c) Decibels MPRIS PlaybackStatus changes. Run as user.
T=${1:-40}
EV=$(awk '/^N: Name=".*\(AVRCP\)"/{f=1} f && /^H: /{for(i=1;i<=NF;i++) if($i ~ /^event/) print $i; exit}' /proc/bus/input/devices)
MP=org.mpris.MediaPlayer2.org.gnome.Decibels
busctl --user list 2>/dev/null | grep -q "$MP" || { systemd-run --user --collect gapplication launch org.gnome.Decibels /tmp/arp.wav >/dev/null; sleep 4; }
busctl --user call $MP /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player OpenUri s file:///tmp/arp.wav 2>/dev/null
busctl --user call $MP /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Play 2>/dev/null
echo "uinput=$EV start $(date +%T)"
echo "${SUDO_PW:-147147}" | sudo -S -p "" timeout $T btmon -T 2>/dev/null | grep -E "AVCTP|AV/C|Opcode|Operation|Passthrough|PLAY|PAUSE|STOP|FORWARD|BACKWARD|Volume" &
echo "${SUDO_PW:-147147}" | sudo -S -p "" timeout $T python3 -c "
import struct, time
f = open('/dev/input/$EV', 'rb', buffering=0)
while True:
    s, us, t, c, v = struct.unpack('qqHHi', f.read(24))
    if t == 1: print(time.strftime('%T'), 'uinput key', c, ('up', 'down', 'repeat')[v], flush=True)
" &
last=; end=$(( $(date +%s) + T ))
while [ $(date +%s) -lt $end ]; do
  s=$(busctl --user get-property $MP /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | cut -d'"' -f2)
  [ "$s" != "$last" ] && { echo "$(date +%T) mpris $s"; last=$s; }
  sleep 0.3
done
wait
busctl --user call $MP /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Stop 2>/dev/null
echo "end $(date +%T)"
