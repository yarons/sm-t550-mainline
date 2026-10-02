#!/bin/sh
# soak.sh <rounds> — alternate gpustress.sh on / auto, <rounds> each; summary of bad lines per run -> ~/soak.out
R=${1:-3}; O=$HOME/soak.out; : > "$O"; i=1
while [ $i -le "$R" ]; do
  for m in on auto; do
    ~/gpustress.sh $m soak-$m-$i
    echo "$m #$i: $(grep -o 'bad-lines[^ ]*=[0-9]*' ~/gpustress-soak-$m-$i.out | tr '\n' ' ') $(grep -c ': OK' ~/gpustress-soak-$m-$i.out)/8 gtk OK, $(grep -o 'Score: [0-9]*' ~/gpustress-soak-$m-$i.out), $(grep -o 'TOTAL resumes=[0-9]*' ~/gpustress-soak-$m-$i.out)" >> "$O"
  done
  i=$((i + 1))
done
echo "${SUDO_PW:-147147}" | sudo -S -p '' sh -c 'echo auto > /sys/devices/platform/soc@0/1c00000.gpu/power/control'
echo done >> "$O"
