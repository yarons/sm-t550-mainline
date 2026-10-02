#!/bin/sh
# Probe the DW9804 (0x0c on CCI bus 4) with the rear sensor powered and streaming.
sh /home/user/cam/reartest.sh 1296 972 1900 64 1 48 >/dev/null 2>&1
MD=/dev/media0; VID=$(media-ctl -d $MD -e msm_vfe0_video0)
timeout -s KILL 12 v4l2-ctl -d "$VID" --stream-mmap --stream-count=200 --stream-to=/dev/null >/dev/null 2>&1 &
sleep 2
for r in 0 1 2 3 4 5 6 7; do printf "reg %d = " $r; i2ctransfer -f -y 4 w1@0x0c $r r1 2>&1; done
printf "write CTL=0 (power on): "; i2ctransfer -f -y 4 w2@0x0c 0x02 0x00 2>&1 && echo ok
wait
