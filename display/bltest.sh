#!/bin/sh
# bltest.sh — write brightness while the display is off (as Phosh/logind do), then unblank. -> ~/bltest.out
O=$HOME/bltest.out; B=/sys/class/backlight/1a98000.dsi.0
psm() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig \
  --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 $1>" >/dev/null; }
orig=$(cat $B/brightness)
psm 3; sleep 2
{ echo "off: bl_power=$(cat $B/bl_power) brightness=$(cat $B/brightness)"
  busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetBrightness ssu backlight 1a98000.dsi.0 40 && echo "logind SetBrightness 40 while off: OK" || echo "logind SetBrightness while off: FAILED"
  echo "after write: brightness=$(cat $B/brightness)"; } > "$O" 2>&1
psm 0; sleep 2
echo "on: bl_power=$(cat $B/bl_power) brightness=$(cat $B/brightness) actual=$(cat $B/actual_brightness)" >> "$O"
busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session SetBrightness ssu backlight 1a98000.dsi.0 "$orig" && echo "restored $orig: OK" >> "$O"
echo "dcs errors: $(echo "${SUDO_PW:-147147}" | sudo -S -p '' dmesg | grep -c 'sending dcs data')" >> "$O"
echo done >> "$O"
