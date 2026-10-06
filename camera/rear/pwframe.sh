#!/bin/sh
# pwframe.sh <W> <H> <tag> [frames] — grab the rear camera through PipeWire (the path Snapshot uses) and keep only
# the last frame as ~/vtest/cam/<tag>.png (+ <tag>-small.png), plus the lower-right-quarter YUV means (colour cast).
W=$1; H=$2; T=$3; N=${4:-50}
export XDG_RUNTIME_DIR=/run/user/$(id -u)
rm -f /dev/shm/$T-*.rgb
gst-launch-1.0 -q pipewiresrc target-object=libcamera_input._base_soc_0_cci_1b0c000_i2c-bus_0_camera_28 num-buffers=$N \
	! video/x-raw,width=$W,height=$H ! videoconvert ! video/x-raw,format=RGB \
	! multifilesink location=/dev/shm/$T-%03d.rgb max-files=1 > /tmp/$T.log 2>&1
F=$(ls /dev/shm/$T-*.rgb 2>/dev/null | tail -1)
[ -n "$F" ] || { echo "$T: no frame"; tail -3 /tmp/$T.log; exit 1; }
ffmpeg -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgb24 -s ${W}x$H -i "$F" -frames:v 1 -update 1 ~/vtest/cam/$T.png
rm -f /dev/shm/$T-*.rgb
ffmpeg -hide_banner -loglevel error -y -i ~/vtest/cam/$T.png -vf scale=648:-2 -update 1 ~/vtest/cam/$T-small.png
echo "$T: $(ffmpeg -hide_banner -nostdin -i ~/vtest/cam/$T.png -vf 'crop=iw/4:ih/4:iw*3/4:ih*3/4,signalstats,metadata=print' -f null - 2>&1 | grep -o -E '(YAVG|UAVG|VAVG)=[0-9.]*' | head -3 | tr '\n' ' ')"
