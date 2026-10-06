#!/bin/sh
# cprtest.sh [seconds-per-step] [freqs…] — CPR / VDD_APC check per CPU frequency (ISSUES 28). Pins policy0 (all four
# cores) to each frequency, reads the APC supply (PM8916 S2) voltage, runs a 4-core sha256 load (64 MiB of zeros per
# round, every hash compared with the reference) for the step time, and reports rounds, mismatches, the average
# frequency under load (cpufreq time_in_state: lower than the pinned one = thermal throttling), the hottest thermal
# zone and new kernel errors. Restores the cpufreq limits afterwards. Run as root on the tablet.
T=${1:-60}; [ $# -gt 0 ] && shift
P=/sys/devices/system/cpu/cpufreq/policy0
FREQS=${*:-$(cat $P/scaling_available_frequencies)}
min0=$(cat $P/scaling_min_freq); max0=$(cat $P/scaling_max_freq)
restore() { echo "$max0" > $P/scaling_max_freq; echo "$min0" > $P/scaling_min_freq; }
trap 'restore; exit 1' INT TERM
trap restore EXIT
R=""; for r in /sys/class/regulator/regulator.*; do [ "$(cat "$r/name")" = s2 ] && R=$r; done
REF=$(head -c 67108864 /dev/zero | sha256sum | cut -d' ' -f1)
hottest() { for z in /sys/class/thermal/thermal_zone*; do echo "$(cat "$z/temp") $(cat "$z/type")"; done | sort -n | tail -1; }
pin() { # freq: lower min first when going down, raise max first when going up
	if [ "$1" -lt "$(cat $P/scaling_min_freq)" ]; then echo "$1" > $P/scaling_min_freq; echo "$1" > $P/scaling_max_freq
	else echo "$1" > $P/scaling_max_freq; echo "$1" > $P/scaling_min_freq; fi
}
worker() { # seconds → prints rounds and mismatches
	end=$(( $(date +%s) + $1 )); n=0; bad=0
	while [ "$(date +%s)" -lt "$end" ]; do
		h=$(head -c 67108864 /dev/zero | sha256sum | cut -d' ' -f1); n=$((n + 1)); [ "$h" = "$REF" ] || bad=$((bad + 1))
	done
	echo "$n $bad"
}
k0=$(dmesg | wc -l)
tis() { awk '{t += $2; w += $1 * $2} END {printf "%.0f %.0f\n", w, t}' $P/stats/time_in_state; }
echo "freq_kHz  avg_kHz  APC_uV(idle)  APC_uV(load)  rounds  bad  hottest"
for f in $FREQS; do
	pin "$f"; sleep 1
	v0=$(cat "$R/microvolts"); set -- $(tis); w0=$1; t0=$2
	for i in 1 2 3 4; do worker "$T" > /tmp/cprtest.$i & done
	sleep $((T / 2)); v1=$(cat "$R/microvolts"); hot=$(hottest); wait
	set -- $(tis); cur=$(( ($1 - w0) / ($2 - t0 > 0 ? $2 - t0 : 1) ))
	set -- $(cat /tmp/cprtest.* | awk '{n += $1; b += $2} END {print n, b}'); rm -f /tmp/cprtest.*
	printf "%-9s %-8s %-13s %-13s %-7s %-4s %s\n" "$f" "$cur" "$v0" "$v1" "$1" "$2" "$hot"
done
dmesg | tail -n +"$((k0 + 1))" | grep -i -E "cpr|regulator|oops|panic|bug|error|fail" | head -20
