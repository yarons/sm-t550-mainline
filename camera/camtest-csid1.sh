#!/bin/sh
# Front camera bring-up test on the T550 (run as root). Loads modules, wires the
# CAMSS pipeline csiphy1 -> csid1 -> ispif0 -> vfe0_rdi0 and grabs raw UYVY frames.
set -u
W=${W:-800}; H=${H:-600}; N=${N:-5}
modprobe i2c-qcom-cci
modprobe qcom-camss
modprobe sr200pc20
sleep 2
dmesg | grep -iE "sr200|camss|cci" | tail -20
MD=$(for m in /dev/media*; do media-ctl -d "$m" -p 2>/dev/null | grep -q camss && echo "$m"; done | head -1)
[ -n "$MD" ] || { echo "no camss media device"; exit 1; }
SENS=$(media-ctl -d "$MD" -p | sed -n 's/.*entity [0-9]*: \(sr200pc20 [^ ]*\).*/\1/p' | head -1)
echo "media=$MD sensor='$SENS'"
[ -n "$SENS" ] || { echo "sensor entity missing"; exit 1; }
media-ctl -d "$MD" -r
media-ctl -d "$MD" -l '"msm_csiphy1":1->"msm_csid1":0[1],"msm_csid1":1->"msm_ispif1":0[1],"msm_ispif1":1->"msm_vfe0_rdi0":0[1]'
F="UYVY8_1X16/${W}x${H} field:none"
media-ctl -d "$MD" -V "'$SENS':0[fmt:$F],\"msm_csiphy1\":0[fmt:$F],\"msm_csid1\":0[fmt:$F],\"msm_ispif1\":0[fmt:$F],\"msm_vfe0_rdi0\":0[fmt:$F]"
media-ctl -d "$MD" -p | grep -A3 -E "msm_vfe0_rdi0|$SENS" | head -30
VID=$(media-ctl -d "$MD" -e msm_vfe0_video0)
echo "video=$VID"
v4l2-ctl -d "$VID" --set-fmt-video=width=$W,height=$H,pixelformat=UYVY
v4l2-ctl -d "$VID" --stream-mmap --stream-count=$N --stream-to=/tmp/cam.raw --verbose 2>&1 | tail -8
ls -la /tmp/cam.raw
dmesg | tail -15
