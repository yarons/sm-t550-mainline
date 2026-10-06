#!/bin/sh
# battab.sh run <tag> [frames] [role] — ISSUES 32 (rear camera slow on battery): stream the rear camera at 1296x972 through
# the soft ISP (same path as stills5m.sh: cam, output cap lifted for this process only) and record what the clocks
# did meanwhile: delivered fps, libcamera's soft-ISP benchmark (Debayer / CPU stats us/frame), GPU devfreq and CPU
# cpufreq time-in-state deltas, CPU busy %, battery current, charger state, temperatures. Writes ~/battab/<tag>.txt.
# role = still (default) | viewfinder (cam's default role; d5c224's 8.5 fps runs) | video.
# battab.sh wait-unplug <tag> [frames] [role] — wait (up to 30 min) until the charger goes offline, settle 15 s, then run.
# Session user, camera idle (refuses while Snapshot runs). Writes no frames.
mode=$1; tag=$2; N=${3:-150}; ROLE=${4:-still}
export XDG_RUNTIME_DIR=/run/user/$(id -u)
G=/sys/class/devfreq/1c00000.gpu; P=/sys/devices/system/cpu/cpufreq/policy0
CHG=/sys/class/power_supply/max77693-charger/online; BAT=/sys/class/power_supply/max170xx_battery
OUT=$HOME/battab; mkdir -p $OUT; R=$OUT/$tag.txt
if [ "$mode" = wait-unplug ]; then
	i=0; while [ "$(cat $CHG)" = 1 ] && [ $i -lt 1800 ]; do sleep 1; i=$((i + 1)); done
	[ "$(cat $CHG)" = 1 ] && { echo "still plugged after 30 min" > $R; exit 1; }
	sleep 15
elif [ "$mode" != run ]; then
	echo "usage: $0 run|wait-unplug <tag> [frames] [role]"; exit 2
fi
pgrep -x snapshot >/dev/null && { echo "Snapshot is running: camera busy"; exit 3; }
C=/tmp/battab-conf; mkdir -p $C/libcamera
# per-process config: no output cap (as stills5m.sh) + soft-ISP benchmark (skip 30, measure 90 frames)
grep -v -E "max_output_(width|height)" /etc/libcamera/configuration.yaml |
	sed 's/^  software_isp:$/  software_isp:\n    measure:\n      skip: 30\n      number: 90/' > $C/libcamera/configuration.yaml
CAM=$(cam -l 2>/dev/null | grep -i -m1 -E "back|sr544" | sed -E 's/^ *([0-9]+):.*/\1/')
busy() { awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat; }
{
	echo "tag=$tag role=$ROLE frames=$N $(date +%T) charger_online=$(cat $CHG) bat=$(cat $BAT/status) $(cat $BAT/capacity)% camera=${CAM:-?}"
	echo "governors: cpu $(cat $P/scaling_governor) [$(cat $P/scaling_min_freq)-$(cat $P/scaling_max_freq)] gpu $(cat $G/governor) [$(cat $G/min_freq)-$(cat $G/max_freq)]"
	echo "tuned: $(tuned-adm active 2>/dev/null | head -1)"
	echo "temps before: $(for t in /sys/class/thermal/thermal_zone*; do printf '%s=%s ' $(cat $t/type) $(( $(cat $t/temp) / 1000 )); done)"
} > $R
cp $G/trans_stat /tmp/battab-g0; cp $P/stats/time_in_state /tmp/battab-c0 2>/dev/null; b0=$(busy)
LIBCAMERA_LOG_LEVELS=Benchmark:INFO XDG_CONFIG_HOME=$C cam -c "$CAM" -s width=1296,height=972,role=$ROLE \
	--capture="$N" > /tmp/battab-cam.log 2>&1 &
CP=$!
# 0.2 s samples while cam runs: GPU cur_freq, CPU cur_freq, battery current (uA)
: > /tmp/battab-samples
while kill -0 $CP 2>/dev/null; do
	echo "$(cat $G/cur_freq) $(cat $P/scaling_cur_freq) $(cat $BAT/current_now)" >> /tmp/battab-samples; sleep 0.2
done
b1=$(busy)
{
	n=$(grep -c "seq:" /tmp/battab-cam.log)
	fps=$(grep -o "([0-9.]* fps)" /tmp/battab-cam.log | tr -d "(fps)" | tail -n +3 | awk '{s+=$1; c++} END {printf "%.1f", c ? s/c : 0}')
	echo "cam: $n frames, mean $fps fps (frames 3+); $(grep -m1 -o '[0-9]*x[0-9]*-[A-Z0-9]*' /tmp/battab-cam.log)"
	grep -h "processed .* us/frame" /tmp/battab-cam.log | sed 's/.*\] /bench: /'
	echo "$b0 $b1" | awk '{printf "CPU busy %.0f %% of 4 cores\n", 100 * ($3 - $1) / ($4 - $2)}'
	awk '{g[$1]++; c[$2]++; i += $3; n++} END {
		printf "samples %d | GPU MHz:", n; for (f in g) printf " %d=%d%%", f / 1e6, 100 * g[f] / n
		printf " | CPU MHz:"; for (f in c) printf " %d=%d%%", f / 1e3, 100 * c[f] / n
		printf " | battery current avg %.0f mA\n", i / n / 1000 }' /tmp/battab-samples
	echo "GPU trans_stat delta (ms per freq):"
	# trans_stat marks the current state with a leading '*'; drop it so both files have the same columns
	paste /tmp/battab-g0 $G/trans_stat | sed 's/\*/ /g' | awk '$1 ~ /^[0-9]+:$/ {printf "  %s %d ms\n", $1, $NF - $(NF/2)}'
	[ -f /tmp/battab-c0 ] && { echo "CPU time_in_state delta (ms per kHz):"; paste /tmp/battab-c0 $P/stats/time_in_state | awk '{d = ($4 - $2) * 10; if (d) printf "  %d %d ms\n", $1, d}'; }
	echo "temps after: $(for t in /sys/class/thermal/thermal_zone*; do printf '%s=%s ' $(cat $t/type) $(( $(cat $t/temp) / 1000 )); done)"
	grep -i -E "error|fail" /tmp/battab-cam.log | sort | uniq -c | head -4
} >> $R
cat $R
