#!/bin/sh
sh /home/user/cam/reartest.sh 2592 1944 1900 16 1 48 >/dev/null 2>&1
MD=/dev/media0; VID=$(media-ctl -d $MD -e msm_vfe0_video0)
timeout -s KILL 15 v4l2-ctl -d "$VID" --stream-mmap --stream-count=300 --stream-to=/dev/null >/dev/null 2>&1 &
sleep 2
rd() { printf "%s: " "$1"; i2ctransfer -f -y 4 w2@0x28 0x00 0x3a r2; }
i2ctransfer -f -y 4 w4@0x28 0x00 0x3a 0x00 0xc8; rd "w 0x00c8"
i2ctransfer -f -y 4 w4@0x28 0x00 0x3a 0xc8 0x00; rd "w 0xc800"
i2ctransfer -f -y 4 w3@0x28 0x00 0x3a 0xc8; rd "w8 0xc8"
i2ctransfer -f -y 4 w3@0x28 0x00 0x3b 0xc8; rd "w8 3b=0xc8"
wait
