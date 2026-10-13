#!/bin/sh
# memwatch.sh <tag> [seconds] — every 2 s: uptime, MemFree/MemAvailable/SwapFree (MB), zram RAM used (MB), DMA zone
# free/min/boost (MB), memory PSI some avg10, and the 3 biggest processes by RSS+swap (MB) → /tmp/memwatch-<tag>.txt.
# Run as a service (systemd-run --user) so an ssh disconnect does not kill it.
T=$1; D=${2:-600}; end=$(( $(date +%s) + D ))
while [ "$(date +%s)" -lt "$end" ]; do
	m=$(awk '/^MemFree|^MemAvailable|^SwapFree/ {printf "%s=%d ", $1, $2 / 1024}' /proc/meminfo)
	z=$(awk '{printf "zram=%d", $3 / 1048576}' /sys/block/zram0/mm_stat 2>/dev/null)
	w=$(awk '/^Node 0, zone/ {zn=$4} zn == "DMA" && /pages free/ {f=$3} zn == "DMA" && $1 == "boost" {b=$2} zn == "DMA" && $1 == "min" {mi=$2} END {printf "dma_free=%d min=%d boost=%d", f * 4 / 1024, mi * 4 / 1024, b * 4 / 1024}' /proc/zoneinfo)
	p=$(awk '/some/ {print $2}' /proc/pressure/memory)
	top=$(for s in /proc/[0-9]*/status; do awk '/^Name/ {n=$2} /^VmRSS/ {r=$2} /^VmSwap/ {w=$2} END {if (r + w > 0) printf "%d:%s\n", (r + w) / 1024, n}' "$s" 2>/dev/null; done | sort -t: -k1 -n -r | head -3 | tr '\n' ' ')
	echo "$(cut -d' ' -f1 /proc/uptime) $m$z $w psi_$p top: $top"
	sleep 2
done > /tmp/memwatch-$T.txt
