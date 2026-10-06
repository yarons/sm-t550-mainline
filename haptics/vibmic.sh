#!/bin/sh
# vibmic.sh — does the motor move? 80-400 Hz mic band RMS (in RAM) quiet vs. each drive mode; GPIO 76/50 pad states.
export XDG_RUNTIME_DIR=/run/user/$(id -u); S=alsa_input.platform-7702000.sound.HiFi__Mic1__source
lf() { timeout 3 parec -d $S --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 192000 | ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 1 -i - -af "aresample=8000:filter_size=256:cutoff=0.9,highpass=f=80,lowpass=f=400,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep "RMS level" | sed "s/.*dB: //"; }
P() { echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 ~/$@; }
echo "quiet:                 80-400 Hz $(lf) dB"
python3 ~/ffrumble.py /dev/input/event5 3500 65535 >/dev/null & sleep 0.2; P gp2set.py 3 140 137 >/dev/null; echo "25.7 kHz 98%:          80-400 Hz $(lf) dB  | $(P tlmm.py 76)"; wait
python3 ~/ffrumble.py /dev/input/event5 3500 65535 >/dev/null & sleep 0.2; P gp2set.py 3 140 3 >/dev/null; echo "25.7 kHz 2%:           80-400 Hz $(lf) dB"; wait
set -- $(P tlmm.py 50 | sed -E "s/.*cfg=(0x[0-9a-f]+).*io=(0x[0-9a-f]+).*/\1 \2/")
python3 ~/ffrumble.py /dev/input/event5 3500 65535 >/dev/null & sleep 0.2; P tlmm.py 50 static-high >/dev/null; echo "gpio50 static high:    80-400 Hz $(lf) dB  | $(P tlmm.py 50) | $(P tlmm.py 76)"; wait
P tlmm.py 50 restore $1 $2 | sed "s/^/restored: /"; P gp2set.py 1 120 90 | sed "s/^/GP2 back to mainline: /"
echo "quiet again:           80-400 Hz $(lf) dB"
