#!/bin/sh
# awbab.sh — green-cast A/B on the rear camera at 1296x972: GPU debayer on freedreno (default), the same GLES shader
# on llvmpipe (LIBGL_ALWAYS_SOFTWARE=1), and CPU debayer (software_isp: mode: cpu), both via a per-process config copy (XDG_CONFIG_HOME), 45 frames each, last frame kept. Prints the
# lower-right YUV means (neutral = U,V ≈ 128) and the AWB gains the simple IPA logged at the end of each run.
export XDG_RUNTIME_DIR=/run/user/$(id -u)
# Rear SR544 by camera ID: cam's index order (-c 1/2) changes between boots (ISSUES 32: -c 2 became the front
# camera after the 2026-10-06 11:23 reboot).
REAR=/base/soc@0/cci@1b0c000/i2c-bus@0/camera@28
for m in gpu llvmpipe cpu; do
	c=$m; [ $m = llvmpipe ] && c=gpu
	C=/tmp/awbab-$m; mkdir -p $C/libcamera
	sed -E "s/^( *)software_isp:\$/\1software_isp:\n\1  mode: $c/" /etc/libcamera/configuration.yaml > $C/libcamera/configuration.yaml
	grep -q "mode: $c" $C/libcamera/configuration.yaml || printf "  software_isp:\n    mode: %s\n" $c >> $C/libcamera/configuration.yaml
	rm -f /dev/shm/awb-$m-*.bin
	SW=; [ $m = llvmpipe ] && SW=1
	LIBGL_ALWAYS_SOFTWARE=$SW LIBCAMERA_LOG_LEVELS="IPASoftAwb:0,*:2" XDG_CONFIG_HOME=$C cam -c "$REAR" -s width=1296,height=972 --capture=45 \
		--file="/dev/shm/awb-$m-#.bin" > /tmp/awbab-$m.log 2>&1 &
	P=$!
	while kill -0 $P 2>/dev/null; do ls -t /dev/shm/awb-$m-*.bin 2>/dev/null | tail -n +3 | xargs -r rm -f; sleep 0.1; done
	F=$(ls -t /dev/shm/awb-$m-*.bin 2>/dev/null | head -1)
	S=$(( $(stat -c %s "$F") / 4 / 972 ))
	ffmpeg -hide_banner -loglevel error -y -f rawvideo -pix_fmt rgba -s ${S}x972 -i "$F" -vf crop=1296:972:0:0 -frames:v 1 -update 1 ~/vtest/cam/awb-$m.png
	rm -f /dev/shm/awb-$m-*.bin
	echo "$m: $(grep -c seq: /tmp/awbab-$m.log) frames, fps $(grep -o '([0-9.]* fps)' /tmp/awbab-$m.log | tail -1), $(ffmpeg -hide_banner -nostdin -i ~/vtest/cam/awb-$m.png -vf 'crop=iw/4:ih/4:iw*3/4:ih*3/4,signalstats,metadata=print' -f null - 2>&1 | grep -o -E '(YAVG|UAVG|VAVG)=[0-9.]*' | head -3 | tr '\n' ' ')"
	grep -i -E "awb|gain|debayer|mode" /tmp/awbab-$m.log | grep -v -i "exposure 4-" | tail -3 | cut -c1-200
done
