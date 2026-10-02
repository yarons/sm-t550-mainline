#!/bin/sh
# snapab.sh <n> — Snapshot launch A/B: n launches with GPU power/control=on, n with auto (alternating blocks of 3).
# Per launch: GPU iommu fault lines ("*** fault") + msm hang lines in the launch window. -> ~/snapab.out
N=${1:-12}; O=$HOME/snapab.out; G=/sys/devices/platform/soc@0/1c00000.gpu/power
S() { echo "${SUDO_PW:-147147}" | sudo -S -p '' "$@"; }
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
cnt() { S dmesg | grep -c -E '\*\*\* fault|hangcheck|gpu lockup'; }
: > "$O"; fon=0; fauto=0; i=0
while [ $i -lt "$N" ]; do
  for mode in on auto; do
    S sh -c "echo $mode > $G/control"
    for k in 1 2 3; do
      sleep 3; a=$(cnt)
      gapplication launch org.gnome.Snapshot >/dev/null 2>&1 & sleep 12; pkill -x snapshot; sleep 2
      d=$(( $(cnt) - a )); echo "$mode launch: faults+$d" >> "$O"
      [ $mode = on ] && fon=$((fon + (d > 0))) || fauto=$((fauto + (d > 0)))
    done
  done
  i=$((i + 3))
done
S sh -c "echo auto > $G/control"
echo "launches with faults: on=$fon/$N auto=$fauto/$N last-camera-id=$(gsettings get org.gnome.Snapshot last-camera-id 2>/dev/null)" >> "$O"
echo done >> "$O"
