#!/bin/sh
# encbench.sh <tag> <src-fps> <sparm-fps> <bitrate> <mode 0=VBR|1=CBR> [minqp] [maxqp] [pattern] [WxH] [frames]
# Encode <frames> videotestsrc frames with the Venus encoder (v4l2h264enc). Buffer timestamps are spaced 1/<src-fps>;
# the encoder's S_PARM (HFI CONFIG_FRAME_RATE) is <sparm-fps> (capssetter relabels the caps). Prints the output size,
# bits per frame, and the bitrate that size means at <src-fps> and at <sparm-fps>, next to the target.
T=$1; SF=$2; PF=$3; BR=$4; M=$5; MIN=${6:-1}; MAX=${7:-51}; PAT=${8:-smpte}; WH=${9:-640x480}; N=${10:-150}
W=${WH%x*}; H=${WH#*x}; O=/tmp/encbench-$T.h264
gst-launch-1.0 -q videotestsrc num-buffers=$N pattern=$PAT horizontal-speed=4 \
	! video/x-raw,format=NV12,width=$W,height=$H,framerate=$SF/1 \
	! capssetter join=true replace=false caps="video/x-raw,framerate=(fraction)$PF/1" \
	! v4l2h264enc extra-controls="encode,video_bitrate=$BR,video_bitrate_mode=$M,h264_minimum_qp_value=$MIN,h264_maximum_qp_value=$MAX" \
	! filesink location=$O > /tmp/encbench-$T.log 2>&1
rc=$?
S=$(stat -c %s $O 2>/dev/null || echo 0)
awk -v t=$T -v s=$S -v n=$N -v sf=$SF -v pf=$PF -v br=$BR -v m=$M -v mn=$MIN -v mx=$MAX -v p=$PAT -v rc=$rc 'BEGIN {
	bpf = s * 8 / n
	printf "%-10s rc=%d %s mode=%s qp=%s-%s pts@%sfps sparm=%sfps target=%.2fM: %d B, %.1f kbit/frame = %.2fM @pts, %.2fM @sparm (x%.2f)\n",
		t, rc, p, (m ? "CBR" : "VBR"), mn, mx, sf, pf, br / 1e6, s, bpf / 1000, bpf * sf / 1e6, bpf * pf / 1e6, bpf * sf / br
}'
rm -f $O
