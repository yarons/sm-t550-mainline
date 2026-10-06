#!/bin/sh
# spkchan.sh — does the speaker play BOTH stereo channels? 1 kHz tone to the Speaker sink on LEFT only, RIGHT only,
# and both, recorded with Mic1; prints the 1 kHz band level per phase (analysis in memory, nothing written).
# The MAX98357A is a mono amp: SD_MODE picks left, right or (L+R)/2. If one phase is at the quiet level, that
# channel never reaches the speaker. Run as the session user; refuses if another stream is playing or recording.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
SRC=alsa_input.platform-7702000.sound.HiFi__Mic1__source; SINK=alsa_output.platform-7702000.sound.HiFi__Speaker__sink
busy=$(pactl list short sink-inputs | wc -l)$(pactl list short source-outputs | wc -l)
[ "$busy" = 00 ] || { echo "BUSY: other audio streams present (sink-inputs/source-outputs $busy)"; pactl list short sink-inputs; pactl list short source-outputs; exit 2; }
an() { ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 1 -i - -af "aresample=8000:filter_size=256:cutoff=0.9,bandpass=f=1000:width_type=h:w=200,bandpass=f=1000:width_type=h:w=200,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep -E "RMS level" | sed "s/.*\] //" | tr -s " " | tr "\n" " "; echo; }
phase() { # $1 label, $2 aevalsrc expression (L|R)
	ffmpeg -hide_banner -nostats -loglevel error -f lavfi -i "aevalsrc=$2:s=48000:d=3" -f s16le - | pacat -d $SINK --format=s16le --rate=48000 --channels=2 &
	sleep 0.7
	printf "%-6s " "$1"; timeout 2 parec -d $SRC --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 144000 | an
	wait
	sleep 0.5
}
echo "sink volume: $(pactl get-sink-volume $SINK | head -1 | grep -oE "[0-9]+%" | head -1), mute $(pactl get-sink-mute $SINK)"
printf "%-6s " quiet; timeout 2 parec -d $SRC --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 144000 | an
# phases in the order given (default: left right both anti); repeat names to check consistency
for p in ${@:-left right both anti}; do
	case $p in
	left) phase left "0.4*sin(2*PI*1000*t)|0" ;;
	right) phase right "0|0.4*sin(2*PI*1000*t)" ;;
	both) phase both "0.4*sin(2*PI*1000*t)|0.4*sin(2*PI*1000*t)" ;;
	anti) phase anti "0.4*sin(2*PI*1000*t)|-0.4*sin(2*PI*1000*t)" ;;
	esac
done
