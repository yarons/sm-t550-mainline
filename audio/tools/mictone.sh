#!/bin/sh
# mictone.sh — where does the 16 kHz capture tone come from? Per codec setting: 1 s raw from hw:0,1 analyzed in memory
# (14-18 kHz band RMS, rest of the band RMS after removing it). Mixer state saved first and restored at the end.
# Run as root inside pasuspender.
S=/tmp/mictone.state; alsactl -f $S store 0
an() { ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 2 -i - -af "pan=mono|c0=c0,asplit[a][b];[a]bandpass=f=16000:width_type=h:w=4000,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none,anullsink;[b]aresample=8000:filter_size=256:cutoff=0.9,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep "RMS level" | sed "s/.*\] RMS level dB: //" | tr "\n" " "; echo; }
m() { amixer -q -c 0 cset "name=$1" "$2"; }
run() { printf "%-34s tone/below8k dB: " "$1"; arecord -q -D hw:0,1 -f S16_LE -c 2 -r 48000 -d 1 -t raw 2>/dev/null | an; }
run "default (DEC1=ADC1 AMIC, ADC1 vol 8)"
m "ADC1 Volume" 4; run "ADC1 vol 4"
m "ADC1 Volume" 0; run "ADC1 vol 0"
m "ADC1 Volume" 8
m "DEC1 MUX" ADC2; m "ADC2 MUX" INP2; run "DEC1=ADC2 (headset input, empty)"
m "DEC1 MUX" ADC3; run "DEC1=ADC3 (secondary mic)"
m "DEC1 MUX" ZERO; run "DEC1=ZERO (no input)"
m "DEC1 MUX" DMIC1; m "CIC1 MUX" DMIC; run "DEC1=DMIC1 (none fitted)"
alsactl -f $S restore 0; rm -f $S
run "restored"
