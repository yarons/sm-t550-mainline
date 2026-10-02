#!/bin/sh
# Stream 40 frames at 16x-less settings, change a control mid-stream, compare first/last frame stats.
sh /home/user/cam/reartest.sh 2592 1944 1900 16 1 48 >/dev/null 2>&1   # set up links/formats
MD=/dev/media0; SUB=$(media-ctl -d $MD -e "$(media-ctl -d $MD -p | sed -n 's/.*entity [0-9]*: \(sr544 [^ ]*\).*/\1/p' | head -1)")
VID=$(media-ctl -d $MD -e msm_vfe0_video0)
( sleep 0.8; v4l2-ctl -d $SUB -c "$1" ; echo "set $1" ) &
timeout -s KILL 20 v4l2-ctl -d "$VID" --stream-mmap --stream-count=40 --stream-to=/tmp/mid.raw 2>&1 | tail -1
wait
python3 - <<'PY'
import math
d=open('/tmp/mid.raw','rb').read(); fs=6298560
for n in (2, 39):
    f=d[n*fs:(n+1)*fs]; v=[]
    for i in range(0,len(f)-5,5*53):
        lo=f[i+4]; v+=[(f[i]<<2)|(lo&3),(f[i+1]<<2)|((lo>>2)&3),(f[i+2]<<2)|((lo>>4)&3),(f[i+3]<<2)|(lo>>6)]
    m=sum(v)/len(v); sd=math.sqrt(sum((x-m)**2 for x in v)/len(v))
    print(f"frame {n}: mean {m:.2f} sd {sd:.2f} max {max(v)}")
PY
