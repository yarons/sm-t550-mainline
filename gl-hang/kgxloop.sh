#!/bin/sh
# kgxloop.sh <tag> <n> — kgx under the gltest.sh hang watchdog n times; verdicts in ~/kgxloop-<tag>.out
T=$1; N=${2:-10}; O=~/kgxloop-$T.out; : > $O
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
i=0; while [ $i -lt $N ]; do i=$((i+1)); ~/gltest.sh 25 "$T-$i" kgx 2>&1 | tail -1 | sed "s/ dump=.*//" >> $O; done
echo "$(apk list -I mesa 2>/dev/null | cut -d" " -f1): hangs $(grep -c HANG $O)/$N" >> $O; echo done >> $O
