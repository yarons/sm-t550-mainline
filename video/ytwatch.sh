#!/bin/sh
# ytwatch.sh [seconds] — read-only snapshot of the user's OWN Firefox while it plays a video (no profile, no
# restart): Venus decoder open (= H.264 on the hardware decoder), libavcodec / ffvpx mapped in the RDD process, Firefox CPU %
# (one core = 100) with the busiest threads, MemAvailable / swap / memory PSI, frames shown per DRM plane.
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name | head -1)")")  # node moves between boots
N=${1:-10}
ff=$(pgrep -f firefox-esr | tr "\n" " ")
[ -n "$ff" ] || { echo "Firefox not running"; exit 1; }
venus=0; for p in $ff; do venus=$((venus + $(ls -l /proc/$p/fd 2>/dev/null | grep -c $VDEC))); done
libs=$(for p in $ff; do grep -ho -E "lib(avcodec\.so\.[0-9]+|mozavcodec\.so|dav1d[^ ]*\.so[.0-9]*|vpx[^ ]*\.so[.0-9]*)" /proc/$p/maps 2>/dev/null; done | sort -u | tr "\n" " ")
tt() { for p in $ff; do k=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | awk '{print $NF}'); case $k in rdd|tab|gpu|socket|utility) ;; *) k=main;; esac
	for t in /proc/$p/task/*; do printf "%s %s:%s %s\n" "${t##*/}" "$k" "$(tr ' ' '_' < $t/comm 2>/dev/null)" "$(awk '{print $14+$15}' $t/stat 2>/dev/null)"; done; done 2>/dev/null; }
mem() { awk '/MemAvailable/{a=$2} /SwapTotal/{st=$2} /SwapFree/{sf=$2} END{printf "avail %d MB, swap used %d MB", a/1024, (st-sf)/1024}' /proc/meminfo; }
tt > /tmp/ytw0; m0=$(mem)
PF=$(echo "${SUDO_PW:-147147}" | sudo -S -p "" python3 ~/vtest/planefps.py $N | grep -v "(off)" | tr "\n" ";")
tt > /tmp/ytw1; m1=$(mem)
tot=$(awk 'NR==FNR {a[$1]=$3; next} {d=$3-a[$1]; if (d > 0) s+=d} END {print int(s/'$N')}' /tmp/ytw0 /tmp/ytw1)
echo "venus fds=$venus  libs=[$libs]  firefox CPU ${tot}%  start: $m0  end: $m1  PSI full $(awk '/full/{print $2}' /proc/pressure/memory)  planes: $PF"
awk 'NR==FNR {a[$1]=$3; next} {d=$3-a[$1]; if (d > 0) s[$2]+=d} END {for (k in s) printf "    %4d%% %s\n", s[k]/'$N', k}' /tmp/ytw0 /tmp/ytw1 | sort -rn | head -8
rm -f /tmp/ytw0 /tmp/ytw1
