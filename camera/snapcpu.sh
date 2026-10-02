#!/bin/sh
# Per-thread CPU of the running Snapshot over N seconds (default 5).
P=$(pgrep -x snapshot) || { echo "snapshot not running"; exit 1; }
S=${1:-5}
snap() { for t in /proc/$P/task/*; do echo "${t##*/} $(tr ' ' _ < $t/comm) $(awk '{print $14+$15}' $t/stat)"; done; }
snap > /tmp/a; sleep "$S"; snap > /tmp/b
awk -v s="$S" 'NR==FNR{a[$1]=$3; next} {d=$3-a[$1]; if (d>0) printf "%-18s %5.1f%%\n", $2, d/s}' /tmp/a /tmp/b | sort -k2 -rn | head -6
