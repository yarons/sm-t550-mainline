#!/bin/sh
# mictone2.sh — 16 kHz capture tone vs display state: tone-band RMS (14-18 kHz) from the Mic1 source, in memory.
export XDG_RUNTIME_DIR=/run/user/$(id -u) DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
SRC=alsa_input.platform-7702000.sound.HiFi__Mic1__source; BL=$(ls -d /sys/class/backlight/* | head -1)
psm() { gdbus call --session --dest org.gnome.Mutter.DisplayConfig --object-path /org/gnome/Mutter/DisplayConfig --method org.freedesktop.DBus.Properties.Set org.gnome.Mutter.DisplayConfig PowerSaveMode "<int32 $1>" >/dev/null; }
tone() { timeout 3 parec -d $SRC --format=s16le --rate=48000 --channels=1 2>/dev/null | head -c 96000 | ffmpeg -hide_banner -nostats -f s16le -ar 48000 -ac 1 -i - -af "bandpass=f=16000:width_type=h:w=4000,astats=metadata=0:measure_perchannel=RMS_level:measure_overall=none" -f null - 2>&1 | grep "RMS level" | sed "s/.*dB: //"; }
b0=$(cat $BL/brightness); echo "backlight $BL max $(cat $BL/max_brightness) now $b0"
echo "screen on, brightness $b0: $(tone)"
gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false 2>/dev/null
busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.freedesktop.DBus.Properties Set ssv org.gnome.SettingsDaemon.Power.Screen Brightness i 5 >/dev/null 2>&1; sleep 1
echo "screen on, brightness $(cat $BL/brightness): $(tone)"
busctl --user call org.gnome.SettingsDaemon.Power /org/gnome/SettingsDaemon/Power org.freedesktop.DBus.Properties Set ssv org.gnome.SettingsDaemon.Power.Screen Brightness i 100 >/dev/null 2>&1; sleep 1
echo "screen on, brightness $(cat $BL/brightness): $(tone)"
psm 3; sleep 2; echo "screen off: $(tone)"; psm 0; sleep 1
gsettings reset org.gnome.settings-daemon.plugins.power ambient-enabled 2>/dev/null
echo "restored brightness $(cat $BL/brightness) (auto-brightness re-enabled)"
