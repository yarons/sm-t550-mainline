#!/bin/sh
# blankgem.sh <cycles> — per unblank/blank: faulting iovas + MDP-mapped GEM iovas + plane fb/hwpipe -> ~/blankgem.out
N=${1:-4}; OUT=$HOME/blankgem.out
psm() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 $1>" >/dev/null; }
snap() { echo "${SUDO_PW:-147147}" | sudo -S -p '' sh -c 'D=/sys/kernel/debug/dri/0
  echo "  mdp vmas: $(grep -B1 mdp_kms $D/gem | grep -o "mdp_kms: vm=[0-9a-f]*, [0-9a-f]*, [a-z]*" | awk "{print \$3\$4}" | tr "\n" " ")"
  echo "  plane0: $(sed -n "/plane-0/,/stage=/p" $D/state | grep -E "fb=|hwpipe=" | tr -d "\t" | tr "\n" " ")"
  echo "  fbs: $(grep -A12 "^framebuffer" $D/framebuffer | grep -E "allocated by|start=" | tr -d "\t" | tr "\n" " ")"'; }
faults() { echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep "context fault" | grep -o "iova=0x[0-9a-f]*" | sed 's/0x0*/0x/' ; }
: > "$OUT"
echo "== start (off)" >> "$OUT"; snap >> "$OUT"
i=1
while [ $i -le $N ]; do
  b=$(faults | wc -l)
  psm 0; sleep 3
  a=$(faults | wc -l)
  echo "== cycle $i ON: new faults $((a-b)): $(faults | tail -n $((a-b)) | sort -u | head -2 | tr '\n' ' ')" >> "$OUT"; snap >> "$OUT"
  psm 3; sleep 3
  echo "== cycle $i OFF" >> "$OUT"; snap >> "$OUT"
  i=$((i+1))
done
echo done >> "$OUT"
