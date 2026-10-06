#!/bin/sh
# showdiag.sh <clip> <tag> [ENV=val …] — where does GNOME Showtime's GTK main thread go while it plays a clip? Starts
# Showtime (Play via MPRIS if needed), then in sequence: threadsample.py (per-thread CPU, main-thread state + kernel
# stack, 6 s), strace -T of the main thread (5 s: syscall summary + calls >= 15 ms), perf of the main thread (5 s, top
# DSOs/symbols), planefps.py (6 s), "too many pending frames" count from Showtime's stderr. Needs a clip >= 45 s.
# Output ~/vtest/logs/<tag>.txt, Showtime stdout/stderr <tag>.err. Run as the session user via
# `systemd-run --user --unit=showdiag --collect ~/vtest/showdiag.sh …` (sudo password <password>).
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
VDEC=/dev/$(basename "$(dirname "$(grep -l qcom-venus-decoder /sys/class/video4linux/video*/name)")")  # node numbers move between boots
C=$1; T=$2; shift 2
L=$HOME/vtest/logs; mkdir -p $L; O=$L/$T.txt; : > $O; : > $L/$T.err
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
	--method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<0>" >/dev/null
systemd-run --user --unit=showtime-$T --collect -p StandardOutput=append:$L/$T.err -p StandardError=append:$L/$T.err \
	env "$@" showtime "$C" >/dev/null 2>&1
M=; i=0
while [ -z "$M" ] && [ $i -lt 20 ]; do
	sleep 1; i=$((i + 1))
	M=$(busctl --user list 2>/dev/null | awk '/org.mpris.MediaPlayer2/ && /howtime/ {print $1; exit}')
done
st() { gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 --method org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null | tr -d "()<>',"; }
s0=$(st)
case "$s0" in *Playing*) ;; *) gdbus call --session --dest "$M" --object-path /org/mpris/MediaPlayer2 --method org.mpris.MediaPlayer2.Player.Play >/dev/null 2>&1;; esac
sleep 3
P=$(pgrep -x showtime | head -1)
{
	echo "== $T  clip $C  env: $*"
	echo "mpris ${M:-none} after ${i}s, status ${s0:-?} -> $(st); venus fds $(ls -l /proc/$P/fd 2>/dev/null | grep -c "$VDEC")"
	S python3 ~/vtest/threadsample.py $P 6
	S timeout -s INT 5 strace -p $P -T -o $L/$T.strace >/dev/null 2>&1
	echo "strace main thread 5 s: calls by syscall (count, total s):"
	sed -n 's/^\([a-z_0-9]*\)(.*<\([0-9.]*\)>$/\1 \2/p' $L/$T.strace |
		awk '{n[$1]++; s[$1]+=$2} END {for (k in n) printf "  %-16s %6d %8.3f\n", k, n[k], s[k]}' | sort -k3 -rn | head -10
	echo "calls >= 15 ms:"
	awk -F'<' '{t=$NF; sub(/>.*/, "", t); if (t+0 >= 0.015) print "  " substr($0, 1, 110) " <" t ">"}' $L/$T.strace | head -15
	S perf record -q -t $P -F 997 -o $L/$T.perf -- sleep 5 >/dev/null 2>&1
	echo "perf main thread 5 s (top dso/symbol):"
	S perf report -q -i $L/$T.perf --stdio --no-children --sort dso,sym 2>/dev/null | grep -v "^$" | head -20
	echo "planes:"
	S python3 ~/vtest/planefps.py 6 | grep -v "(off)"
	echo "status at end $(st); 'too many pending frames': $(grep -c 'too many pending' $L/$T.err)"
} >> $O 2>&1
systemctl --user stop showtime-$T 2>/dev/null; pkill -x showtime; sleep 2
echo DONE >> $O
