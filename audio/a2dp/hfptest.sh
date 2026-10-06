#!/bin/sh
# HFP mic/earpiece test (ISSUES 25): switch the headset to handsfree_head_unit, record $2 s from its mic while
# btmon counts SCO packets (SCO over HCI vs. a PCM side path that Linux never sees), report codec + level, play
# the recording back over HFP, then return to A2DP. Usage: hfptest.sh <mac_underscored> [seconds]
M=$1 T=${2:-6} CARD=bluez_card.$1
pactl set-card-profile $CARD handsfree_head_unit || exit 1
sleep 2
SRC=$(pactl list short sources | awk '/bluez_source/ {print $2; exit}')
SINK=$(pactl list short sinks | awk '/bluez_sink/ {print $2; exit}')
echo "profile=$(pactl list cards | sed -n "/$CARD/,/Active Profile/p" | awk -F': ' '/Active Profile/ {print $2}') src=$SRC sink=$SINK codec=$(pactl list cards | sed -n "/$CARD/,/^Card/p" | awk -F'"' '/bluetooth.codec/ {print $2}')"
echo "${SUDO_PW:-147147}" | sudo -S -p "" timeout $((T + 4)) btmon > /tmp/hfp-btmon.txt 2>&1 &
sleep 1
echo "REC start $(date +%T)"
timeout $T parecord -d "$SRC" --file-format=wav /tmp/hfp-rec.wav
echo "REC end $(date +%T)"
wait
echo "SCO frames in btmon: $(grep -c 'SCO Data' /tmp/hfp-btmon.txt)  eSCO setup: $(grep -c -i -E 'Synchronous Connection Complete' /tmp/hfp-btmon.txt) air_mode: $(grep -i -m1 'Air mode' /tmp/hfp-btmon.txt | sed 's/^ *//')"
python3 - <<'PY'
import wave, struct, math
w = wave.open('/tmp/hfp-rec.wav'); n = w.getnframes(); ch = w.getnchannels(); r = w.getframerate()
d = struct.unpack('<%dh' % (n * ch), w.readframes(n))
rms = math.sqrt(sum(x * x for x in d) / max(1, len(d))); pk = max((abs(x) for x in d), default=0)
print(f"rec rate={r} ch={ch} dur={n / r:.1f}s rms={20 * math.log10(max(rms, 1) / 32768):.1f} dBFS peak={20 * math.log10(max(pk, 1) / 32768):.1f} dBFS")
PY
echo "PLAYBACK over HFP $(date +%T)"
paplay -d "$SINK" /tmp/hfp-rec.wav
pactl set-card-profile $CARD a2dp_sink
echo "back to $(pactl list cards | sed -n "/$CARD/,/Active Profile/p" | awk -F': ' '/Active Profile/ {print $2}')"
