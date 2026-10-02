#!/bin/sh
# abrun.sh <tag> — fixed protocol after a fresh boot: blanktest 10, blankgem 6, Snapshot + blankgem 6.
# Results ~/ab-<tag>.out (+ total MDP fault/vblank/underrun/dcs counts). Run as a user unit (systemd-run --user).
T=$1; O=$HOME/ab-$T.out
c() { echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep -c -E "$1"; }
{ echo "## $T $(uname -r) msm=$(cat /sys/module/msm/srcversion) up=$(cut -d' ' -f1 /proc/uptime)"; } > "$O"
~/blanktest.sh 10 3 3; cat ~/blanktest.out >> "$O"
~/blankgem.sh 6; grep -E "^==|mdp vmas" ~/blankgem.out >> "$O"
gapplication launch org.gnome.Snapshot >/dev/null 2>&1 & sleep 15
~/blankgem.sh 6; echo "# with Snapshot" >> "$O"; grep -E "^==|mdp vmas" ~/blankgem.out >> "$O"
pkill -x snapshot
echo "TOTAL faults=$(c 'context fault') vblank=$(c 'vblank time out') underrun=$(c 'mdp5_irq_error') dcs=$(c 'sending dcs data')" >> "$O"
echo done >> "$O"
