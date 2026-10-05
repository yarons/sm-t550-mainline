#!/bin/sh
# micfmt.sh — raw ALSA capture from hw:0,1 in several formats, analyzed in memory (nothing written): per-channel RMS,
# peak, crest factor, zero-crossing rate. Run inside pasuspender (PulseAudio holds the device otherwise).
an() {  # $1 ffmpeg sample format, $2 channels
	ffmpeg -hide_banner -nostats -f "$1" -ar 48000 -ac "$2" -i - -af "astats=metadata=0:measure_perchannel=RMS_level+Peak_level+Crest_factor+Zero_crossings_rate:measure_overall=none" -f null - 2>&1 |
		grep -E "Channel:|RMS level|Peak level|Crest|Zero crossings rate" | sed "s/.*\] //" | tr -s " " | tr "\n" " "; echo
}
for cfg in "S16_LE 1 s16le" "S16_LE 2 s16le" "S24_LE 2 s32le"; do
	set -- $cfg
	printf "%s %sch: " "$1" "$2"
	arecord -q -D hw:0,1 -f "$1" -c "$2" -r 48000 -d 2 -t raw 2>/dev/null | an "$3" "$2"
done
