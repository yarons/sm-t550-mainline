#!/bin/sh
# mesasoak.sh <tag> — Mesa acceptance pass on the session: 10 GTK4 apps × 25 s and the calculator 90 s under the
# gltest.sh hang watchdog, then Snapshot black frames (flicker.sh), glmark2 score, GPU fault count over the whole
# run. One line per step in ~/mesasoak-<tag>.out. Run as the session user (sudo password <password> for dmesg):
#   systemd-run --user --unit=mesasoak --collect ~/mesasoak.sh m2624
T=${1:?tag}; O=~/mesasoak-$T.out; : > "$O"
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
faults() { echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep -cE 'context fault|hangcheck|\*\*\* fault|msm_gpu_fault'; }
f0=$(faults)
echo "== $T: mesa $(apk list -I mesa 2>/dev/null | cut -d' ' -f1), kernel $(uname -v | cut -d' ' -f1), faults before $f0" >> "$O"
for app in gnome-calculator gnome-text-editor nautilus gnome-clocks kgx gnome-contacts gnome-control-center loupe \
	gnome-calendar gnome-weather; do
	~/gltest.sh 25 "$T-$app" "$app" 2>&1 | tail -1 >> "$O"
done
~/gltest.sh 90 "$T-calc90" gnome-calculator 2>&1 | tail -1 >> "$O"
~/flicker.sh "$T" 2>&1 | tail -1 >> "$O"
glmark2-wayland --off-screen -b build -b texture -b shading -b refract 2>/dev/null | grep -E 'glmark2 Score' >> "$O"
echo "GPU faults during the run: $(( $(faults) - f0 ))" >> "$O"
echo done >> "$O"
