#!/bin/sh
# A2DP stability run (hardware review #5): 60 s arpeggio per codec to the BT sink; logs CPU of pulseaudio +
# bluetoothd and any PA/BlueZ journal lines. Usage: a2dprun.sh <card-mac-underscored> [codec ...]
M=$1; shift
CARD=bluez_card.$M SINK=bluez_sink.$M.a2dp_sink
[ -f /tmp/arp.wav ] || python3 - <<'PY'
import math, struct, wave
r = 44100; notes = [261.63, 329.63, 392.0, 523.25]
w = wave.open("/tmp/arp.wav", "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(r)
n = r // 4; buf = bytearray()
for k in range(240):
    f = notes[k % 4]
    for i in range(n):
        s = int(0.25 * 32767 * math.sin(2 * math.pi * f * i / r) * min(1, i / 300, (n - i) / 300))
        buf += struct.pack("<hh", s, s)
w.writeframes(bytes(buf)); w.close()
PY
ticks() { awk '{print $14+$15}' /proc/$1/stat; }
PA=$(pgrep -x pulseaudio) BZ=$(pgrep -x bluetoothd)
for c in "${@:-sbc}"; do
  pactl send-message /card/$CARD/bluez switch-codec "\"$c\"" >/dev/null 2>&1; sleep 3
  echo "== $c (active: $(pactl send-message /card/$CARD/bluez get-codec 2>&1)) $(date +%T)"
  a=$(ticks $PA) b=$(ticks $BZ) t0=$(date +%s)
  paplay -d $SINK /tmp/arp.wav; echo "paplay rc=$?"
  t=$(( $(date +%s) - t0 ))
  echo "pulseaudio CPU $(( ($(ticks $PA) - a) * 100 / (t * 100) ))%  bluetoothd CPU $(( ($(ticks $BZ) - b) * 100 / (t * 100) ))%  wall ${t}s"
done
