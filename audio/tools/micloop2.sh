#!/bin/sh
# micloop2.sh — mic loopback through PulseAudio: 1 kHz sine to the speaker sink while recording the Mic1 source;
# analyzed in memory (tone at 16 kHz removed by resampling to 8 kHz), nothing written. Run as the session user.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
SRC=alsa_input.platform-7702000.sound.HiFi__Mic1__source; SINK=alsa_output.platform-7702000.sound.HiFi__Speaker__sink
an() { ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 1 -i - -af "aresample=8000:filter_size=256:cutoff=0.9,asplit[a][b];[a]astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;[b]bandpass=f=1000:width_type=h:w=200,bandpass=f=1000:width_type=h:w=200,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep -E "RMS level" | sed "s/.*\] //" | tr -s " " | tr "\n" " "; echo; }
echo "sink volume: $(pactl get-sink-volume $SINK | head -1 | grep -oE "[0-9]+%" | head -1), mute $(pactl get-sink-mute $SINK)"
printf "quiet: "; timeout 4 parec -d $SRC --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 288000 | an
ffmpeg -hide_banner -nostats -loglevel error -f lavfi -i "sine=f=1000:d=4" -af volume=0.5 -ar 48000 -ac 2 -f s16le - | pacat -d $SINK --format=s16le --rate=48000 --channels=2 &
sleep 0.7
printf "beep:  "; timeout 4 parec -d $SRC --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 288000 | an
wait
