#!/bin/sh
# enctrace.sh <outfile> <cmd…> — (root) kprobe trace of the Venus HFI layer around a command run as `user`: every
# hfi_session_set_property (property id + first three words of its data) and every encoder ETB (timestamp in µs,
# flags, alloc/filled length). Compare a v4l2-ctl and a GStreamer encode to see what the firmware is told.
T=/sys/kernel/tracing
O=$1; shift
echo 0 > $T/tracing_on; echo > $T/trace; echo > $T/kprobe_events
cat >> $T/kprobe_events <<'K'
p:eprop hfi_session_set_property ptype=%x1:x32 d0=+0(%x2):x32 d1=+4(%x2):x32 d2=+8(%x2):x32
p:eetb pkt_session_etb_encoder ts=+16(%x2):u64 flags=+24(%x2):x32 alloc=+32(%x2):u32 filled=+36(%x2):u32
K
echo 8192 > $T/buffer_size_kb
echo 1 > $T/events/kprobes/enable; echo 1 > $T/tracing_on
su user -c "$*" > "$O.cmd" 2>&1
echo 0 > $T/tracing_on
grep -v "^#" $T/trace | sed -E 's/^.*\] [^ ]+ +([0-9.]+): /\1 /; s/\([a-z_0-9]+\+0x0\/0x[0-9a-f]+ \[venus_core\]\) //' > "$O"
echo 0 > $T/events/kprobes/enable; echo > $T/kprobe_events
chown user "$O" "$O.cmd"; wc -l < "$O"
