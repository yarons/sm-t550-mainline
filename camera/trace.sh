#!/bin/sh
T=/sys/kernel/tracing
[ -d $T/options ] || mount -t tracefs nodev $T
echo 0 > $T/tracing_on
echo > $T/trace
echo ':mod:qcom_camss' > $T/set_ftrace_filter
echo function_graph > $T/current_tracer
echo 1 > $T/options/funcgraph-retval 2>/dev/null
echo 1 > $T/tracing_on
VID=$(media-ctl -d /dev/media0 -e msm_vfe0_video0)
v4l2-ctl -d "$VID" --stream-mmap --stream-count=3 --stream-to=/tmp/cam.raw 2>&1 | tail -2
echo 0 > $T/tracing_on
cat $T/trace | head -120
echo ---
grep -nE "s_power|set_clock|link_freq|pixel_clock" $T/trace | head -40
echo nop > $T/current_tracer
