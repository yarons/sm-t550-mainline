#!/bin/sh
# While the rear camera streams, read 16-bit registers back over CCI (i2c bus 4).
sh /home/user/cam/reartest.sh 2592 1944 1900 200 1 48 >/dev/null 2>&1
MD=/dev/media0; VID=$(media-ctl -d $MD -e msm_vfe0_video0)
timeout -s KILL 12 v4l2-ctl -d "$VID" --stream-mmap --stream-count=200 --stream-to=/dev/null >/dev/null 2>&1 &
sleep 2
for r in 0x0000 0x0002 0x0004 0x0006 0x0008 0x003a 0x003c 0x0a02 0x0a04 0x0118 0x0f16; do
	hi=$(( (r >> 8) & 0xff )); lo=$(( r & 0xff ))
	printf "%s = " $r; i2ctransfer -f -y 4 w2@0x28 $hi $lo r2 2>&1
done
wait
