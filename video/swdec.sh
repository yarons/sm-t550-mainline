#!/bin/sh
# swdec.sh <clip> [ffmpeg decoder] [threads] — decode-only throughput of one clip with ffmpeg (as fast as possible,
# no display): fps, real time, and CPU time as % of one core. Real time playback at 25 fps needs fps >= 25 with
# headroom; CPU % / fps * 25 estimates the CPU playback would cost. Decoder e.g. h264, vp9, libdav1d, h264_v4l2m2m.
C=$1; D=${2:+-c:v $2}; T=${3:-4}
ffmpeg -hide_banner -nostdin -benchmark -threads "$T" $D -i "$C" -an -f null - 2>&1 |
	awk -v c="${C##*/}" -v d="${2:-auto}" -v t="$T" '
	/^frame=/ { for (i = 1; i <= NF; i++) if ($i ~ /^frame=/) { f = $i; sub("frame=", "", f); if (f == "") f = $(i+1) } }
	/bench: utime/ { split($0, a, /[= s]+/); for (i in a) { if (a[i] == "utime") u = a[i+1]; if (a[i] == "stime") s = a[i+1]; if (a[i] == "rtime") r = a[i+1] } }
	END { if (r > 0) printf "%-12s %-13s thr=%s frames=%s  %.1f fps  real %.2fs  CPU %.0f%% of one core (usr %.1fs sys %.1fs)\n", c, d, t, f, f / r, r, 100 * (u + s) / r, u, s; else print c, d, "FAILED" }'
