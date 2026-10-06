#!/bin/sh
# vtrace.sh <outfile> <cmd…> — (root) ftrace of the Venus decoder around a command run as `user`: every venus_core/
# venus_dec function call (function tracer) plus kprobes with arguments: STREAMON/OFF per queue (type 9 = OUTPUT/
# bitstream, 10 = CAPTURE/frames), QBUF, buffers sent to the firmware, buffers back (buf_type 1 input, 2 output,
# tag, bytesused, HFI flags), flushes, firmware events (ev 4 = session error, err = HFI error code).
T=/sys/kernel/tracing
O=$1; shift
echo 0 > $T/tracing_on; echo nop > $T/current_tracer; echo > $T/trace
echo 0 > $T/events/kprobes/enable 2>/dev/null; echo > $T/kprobe_events
cat >> $T/kprobe_events <<'EOF'
p:von vdec_start_streaming type=+0(%x0):u32 count=%x1:u32
p:voff vdec_stop_streaming type=+0(%x0):u32
p:vqbuf vdec_vb2_buf_queue idx=+8(%x0):u32 type=+12(%x0):u32
p:vsub session_process_buf idx=+8(%x1):u32 type=+12(%x1):u32
p:vdone vdec_buf_done bt=%x1:u32 tag=%x2:u32 used=%x3:u32 hfl=%x6:x32
p:vflush hfi_session_flush t=%x1:u32
p:vevt vdec_event_notify ev=%x1:u32 err=+0(%x2):x32 etype=+12(%x2):u32
EOF
echo 8192 > $T/buffer_size_kb
echo ':mod:venus_core' > $T/set_ftrace_filter; echo ':mod:venus_dec' >> $T/set_ftrace_filter
echo function > $T/current_tracer
echo 1 > $T/events/kprobes/enable
echo 1 > $T/tracing_on
su user -c "$*" > "$O.cmd" 2>&1
echo 0 > $T/tracing_on
grep -v "^#" $T/trace > "$O"
echo 0 > $T/events/kprobes/enable; echo > $T/kprobe_events; echo nop > $T/current_tracer; echo > $T/set_ftrace_filter
chown user "$O" "$O.cmd"
wc -l < "$O"
