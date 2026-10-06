#!/bin/sh
# lastframe.sh <W> <H> <tag> [frames] — run cam on the rear camera (output cap lifted for this process) for N frames
# (auto-exposure converges) and keep ONLY the last frame: cam writes /dev/shm/<tag>-<seq>.bin, a cleaner deletes all
# but the newest two while it runs. Result: ~/vtest/cam/<tag>.png (XRGB8888 → PNG, stride padding cropped).
W=$1; H=$2; T=$3; N=${4:-45}
export XDG_RUNTIME_DIR=/run/user/$(id -u)
rm -f /dev/shm/$T-*.bin
XDG_CONFIG_HOME=/tmp/stills5m-conf cam -c 2 -s width=$W,height=$H,role=still --capture=$N --file="/dev/shm/$T-#.bin" > /tmp/$T.log 2>&1 &
P=$!
while kill -0 $P 2>/dev/null; do ls -t /dev/shm/$T-*.bin 2>/dev/null | tail -n +3 | xargs -r rm -f; sleep 0.1; done
F=$(ls -t /dev/shm/$T-*.bin 2>/dev/null | head -1)
[ -n "$F" ] || { echo "$T: no frame"; tail -3 /tmp/$T.log; exit 1; }
S=$(( $(stat -c %s "$F") / 4 / H ))
mkdir -p ~/vtest/cam
ffmpeg -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba -s ${S}x$H -i "$F" -vf crop=$W:$H:0:0 -frames:v 1 -update 1 ~/vtest/cam/$T.png
rm -f /dev/shm/$T-*.bin
echo "$T: $(grep -c seq: /tmp/$T.log) frames, stride $S, $(ffmpeg -hide_banner -nostdin -i ~/vtest/cam/$T.png -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG -f null - 2>&1 | grep -o 'YAVG=[0-9.]*' | head -1)"
