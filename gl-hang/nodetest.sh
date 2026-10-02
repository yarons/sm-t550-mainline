#!/bin/sh
# Render each node file with GTK's GL renderer; report hang per node. Args: node files.
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0
S() { echo "${SUDO_PW:-147147}" | sudo -S -p "" "$@"; }
for f in "$@"; do
	S dmesg -c >/dev/null
	timeout 20 gtk4-rendernode-tool render --renderer gl "$f" "/tmp/out-$(basename "$f" .node).png" >/tmp/rn.log 2>&1
	rc=$?
	sleep 2
	h=$(S dmesg | grep -c "hangcheck detected gpu lockup")
	if [ "$h" -gt 0 ]; then v=HANG; sleep 6; else v=ok; fi
	echo "$(basename "$f"): $v rc=$rc $(head -c 120 /tmp/rn.log | tr '\n' ' ')"
done
