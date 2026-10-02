#!/bin/sh
# Rear camera (SR544) raw capture: csiphy0 -> csid0 -> ispif0 -> vfe0_rdi0, SRGGB10 packed.
# Usage (root): reartest.sh [W H] [EXPOSURE_LINES] [GAIN_0x10=1x] [FRAMES]
W=${1:-2592}; H=${2:-1944}; EXP=${3:-1900}; GAIN=${4:-64}; N=${5:-6}; VBL=${6:-40}
MD=$(for m in /dev/media*; do media-ctl -d "$m" -p 2>/dev/null | grep -q camss && echo "$m"; done | head -1)
SENS=$(media-ctl -d "$MD" -p | sed -n 's/.*entity [0-9]*: \(sr544 [^ ]*\).*/\1/p' | head -1)
[ -n "$SENS" ] || { echo "sr544 entity missing"; exit 1; }
SUB=$(media-ctl -d "$MD" -e "$SENS")
media-ctl -d "$MD" -r
media-ctl -d "$MD" -l '"msm_csiphy0":1->"msm_csid0":0[1],"msm_csid0":1->"msm_ispif0":0[1],"msm_ispif0":1->"msm_vfe0_rdi0":0[1]'
F="SBGGR10_1X10/${W}x${H} field:none"
media-ctl -d "$MD" -V "'$SENS':0[fmt:$F],\"msm_csiphy0\":0[fmt:$F],\"msm_csid0\":0[fmt:$F],\"msm_ispif0\":0[fmt:$F],\"msm_vfe0_rdi0\":0[fmt:$F]"
v4l2-ctl -d "$SUB" -c vertical_blanking=$VBL -c exposure=$EXP -c analogue_gain=$GAIN 2>&1
VID=$(media-ctl -d "$MD" -e msm_vfe0_video0)
v4l2-ctl -d "$VID" --set-fmt-video=width=$W,height=$H,pixelformat=pBAA
v4l2-ctl -d "$VID" --get-fmt-video | grep -E "Bytes per Line|Size Image"
timeout -s KILL 15 v4l2-ctl -d "$VID" --stream-mmap --stream-count=$N --stream-to=/tmp/rear.raw --verbose 2>&1 | grep -E "fps|STREAMON|error" | tail -3
ls -la /tmp/rear.raw
dmesg | grep -iE "sr544|camss|csid|vfe" | tail -4
