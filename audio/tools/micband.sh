#!/bin/sh
# micband.sh — 3 s from hw:0,1 (S16, 2ch), analyzed in memory per band: <8 kHz (speech band) vs 14-18 kHz.
an() { ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 2 -i - -af "pan=mono|c0=c0,$1,astats=metadata=0:measure_perchannel=RMS_level+Peak_level+Crest_factor+Zero_crossings_rate:measure_overall=none" -f null - 2>&1 | grep -E "RMS level|Peak level|Crest|Zero crossings rate" | sed "s/.*\] //" | tr -s " " | tr "\n" " "; echo; }
printf "lowpass 8k:  "; arecord -q -D hw:0,1 -f S16_LE -c 2 -r 48000 -d 3 -t raw 2>/dev/null | an "lowpass=f=8000:poles=2,lowpass=f=8000:poles=2"
printf "300-3400 Hz: "; arecord -q -D hw:0,1 -f S16_LE -c 2 -r 48000 -d 3 -t raw 2>/dev/null | an "highpass=f=300,lowpass=f=3400"
printf "14-18 kHz:   "; arecord -q -D hw:0,1 -f S16_LE -c 2 -r 48000 -d 3 -t raw 2>/dev/null | an "bandpass=f=16000:width_type=h:w=4000"
