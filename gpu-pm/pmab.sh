#!/bin/sh
# pmab.sh <secs> — GPU runtime PM A/B on an idle screen: power/control on vs auto.
# Per window: GPU suspended ms, runtime_status at end, sys/idle CPU %, battery current. -> ~/pmab.out
S=${1:-20}; O=$HOME/pmab.out; G=/sys/devices/platform/soc@0/1c00000.gpu/power
B=/sys/class/power_supply/max170xx_battery
cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $4, $5}' /proc/stat; }
win() {
  echo "${SUDO_PW:-147147}" | sudo -S -p '' sh -c "echo $1 > $G/control"; sleep 2
  set -- $1 $(cpu) $(cat $G/runtime_suspended_time) $(cat $G/runtime_active_time)
  mode=$1 t0=$2 s0=$3 i0=$4 su0=$5 a0=$6; n=0; isum=0
  end=$(( $(cut -d. -f1 /proc/uptime) + S ))
  while [ "$(cut -d. -f1 /proc/uptime)" -lt "$end" ]; do isum=$((isum + $(cat $B/current_now))); n=$((n+1)); sleep 1; done
  set -- $(cpu) $(cat $G/runtime_suspended_time) $(cat $G/runtime_active_time)
  dt=$(( $1 - t0 ))
  echo "$mode: gpu suspended $(( $4 - su0 )) ms / active $(( $5 - a0 )) ms, status=$(cat $G/runtime_status), sys $(( 100 * ($2 - s0) / dt ))% idle $(( 100 * ($3 - i0) / dt ))%, batt avg $(( isum / n / 1000 )) mA" >> "$O"
}
: > "$O"
win on; win auto; win on; win auto
echo "${SUDO_PW:-147147}" | sudo -S -p '' sh -c "echo on > $G/control"
echo "errors: $(echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep -c -E 'hangcheck|gpu fault|msm_gpu_fault|VBIF|Wait limit')" >> "$O"
echo done >> "$O"
