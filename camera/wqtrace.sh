#!/bin/sh
# Which workqueue functions and which processes do I/O, over $1 seconds (root).
S=${1:-5}
T=/sys/kernel/tracing
echo 0 > $T/tracing_on; echo > $T/trace; echo nop > $T/current_tracer
echo 1 > $T/events/workqueue/workqueue_execute_start/enable
for p in /proc/[0-9]*; do echo "${p#/proc/} $(awk '/^(read|write)_bytes/{s+=$2} END{print s+0}' $p/io 2>/dev/null) $(tr -d '\0' < $p/comm 2>/dev/null)"; done > /tmp/io.a
awk '$3=="mmcblk0"{print $6, $10}' /proc/diskstats > /tmp/d.a
echo 1 > $T/tracing_on; sleep "$S"; echo 0 > $T/tracing_on
echo 0 > $T/events/workqueue/workqueue_execute_start/enable
for p in /proc/[0-9]*; do echo "${p#/proc/} $(awk '/^(read|write)_bytes/{s+=$2} END{print s+0}' $p/io 2>/dev/null) $(tr -d '\0' < $p/comm 2>/dev/null)"; done > /tmp/io.b
echo "== workqueue functions / ${S}s"
grep -o 'function=[A-Za-z0-9_.]*' $T/trace | sort | uniq -c | sort -rn | head -15
echo "== mmcblk0 sectors read/written / ${S}s"
awk '$3=="mmcblk0"{print $6, $10}' /proc/diskstats | paste /tmp/d.a - | awk '{print "read", $3-$1, "write", $4-$2}'
echo "== processes by I/O bytes / ${S}s"
awk 'NR==FNR{a[$1]=$2; next} ($1 in a) && $2-a[$1]>0 {print $2-a[$1], $3}' /tmp/io.a /tmp/io.b | sort -rn | head -10
