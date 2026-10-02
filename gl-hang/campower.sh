#!/bin/sh
# While Snapshot runs, average battery current over 15 s (on the charger: less charge current =
# more system load). Prints the idle baseline first.
#   campower.sh <tag>
tag=$1
avg() { s=0; for i in $(seq 1 15); do c=$(cat /sys/class/power_supply/max170xx_battery/current_now); s=$((s + c)); sleep 1; done; echo $((s / 15000)); }
echo "$tag: battery $(avg) mA (positive = charging)"
