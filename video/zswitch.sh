#!/bin/sh
# zswitch.sh <algo> — (root) rebuild the zram swap with another compressor at runtime, as zramstart does (same size,
# priority 300). swapoff first pulls every swapped page back into RAM. A reboot restores deviceinfo's lz4.
A=$1; Z=/sys/block/zram0; S=$(cat $Z/disksize)
t0=$(date +%s)
swapoff /dev/zram0 || exit 1
echo 1 > $Z/reset && echo "$A" > $Z/comp_algorithm && echo "$S" > $Z/disksize && mkswap /dev/zram0 >/dev/null && swapon -p 300 /dev/zram0 || exit 1
echo "zram0 → $(grep -o '\[[a-z0-9-]*\]' $Z/comp_algorithm) $((S / 1048576)) MB (swapoff+rebuild $(( $(date +%s) - t0 )) s)"
