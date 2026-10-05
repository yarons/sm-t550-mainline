#!/bin/sh
# tonemeas.sh <tag> — 2 s from the Mic1 source in RAM: 14-18 kHz band RMS, rest-of-band RMS (8 kHz resample), peak freq.
export XDG_RUNTIME_DIR=/run/user/$(id -u); S=alsa_input.platform-7702000.sound.HiFi__Mic1__source
timeout 4 parec -d $S --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 192000 > /dev/shm/g.raw
printf "%s: " "$1"; ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 1 -i /dev/shm/g.raw -af "asplit[a][b];[a]bandpass=f=16000:width_type=h:w=4000,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;[b]aresample=8000:filter_size=256:cutoff=0.9,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep "RMS level" | sed "s/.*dB: //" | tr "\n" " "; echo "(below8k, tone band) ADC1=$(amixer -c 0 cget name="ADC1 Volume" | grep -o "values=[0-9]*")"
rm -f /dev/shm/g.raw
