#!/bin/sh
# ht20test.sh [0|1] — does the 2.4 GHz BSSID join when HT40 is disabled? Takes wlan0 from NetworkManager for ~45 s,
# runs a private wpa_supplicant against the 2.4 GHz BSSID with disable_ht40=<arg> (default 1), logs whether the
# 4-way handshake completes and the firmware's hal_join/config_bss errors, then gives wlan0 back to NM (5 GHz lock).
# The PSK goes from NM's profile into a root-only file in /run and is deleted afterwards. Run as root:
#   systemd-run --unit=ht20test --collect [-E NM_CON=<connection> -E BSSID_2G=<bssid>] /home/user/ht20test.sh 1
H=${1:-1}; O=/home/user/ht20test.out; C=${NM_CON:-"HOME-WIFI"}; BG=${BSSID_2G:-AP-2G-BSSID}; W=/run/ht20test; L=$W/wpa.log
log() { echo "$(date +%T) $*" >> $O; }
kc() { journalctl -k --no-pager --since "@$1" | grep -cE "$2"; }
rm -rf $W; mkdir -p -m 700 $W
# The passphrase lives only in this root-only tmpfs file and is deleted at the end (never on argv).
(umask 077; {
	echo "ctrl_interface=$W/ctrl"
	echo "network={"
	printf '\tssid="%s"\n\tbssid=%s\n\tkey_mgmt=WPA-PSK\n\tdisable_ht40=%s\n' "$C" "$BG" "$H"
	printf '\t%s="%s"\n' psk "$(nmcli -s -g 802-11-wireless-security.psk con show "$C")"
	echo "}"
} > $W/wpa.conf)
t0=$(date +%s)
log "== disable_ht40=$H against $BG"
nmcli dev set wlan0 managed no; sleep 3
wpa_supplicant -i wlan0 -D nl80211 -c $W/wpa.conf -t > $L 2>&1 &
echo $! > $W/pid; sleep 1
i=0; while [ $i -lt 40 ]; do grep -q CTRL-EVENT-CONNECTED $L && break; sleep 2; i=$((i + 2)); done
sleep 5
log "result: connected=$(grep -c CTRL-EVENT-CONNECTED $L) handshake_fail=$(grep -c '4-Way Handshake failed' $L) beacon_loss=$(grep -c BEACON-LOSS $L) hal_join_err=$(kc $t0 'hal_join response failed') config_bss_err=$(kc $t0 'hal_config_bss response failed')"
log "link: $(iw dev wlan0 link 2>/dev/null | grep -E 'Connected|freq|tx bitrate|rx bitrate' | tr '\n\t' '  ')"
kill "$(cat $W/pid)" 2>/dev/null; sleep 2
grep -vE 'psk|PSK' $L | grep -E 'CTRL-EVENT|WPA:|Trying|Associated|auth' | tail -12 > $W/excerpt; cp $W/excerpt /home/user/ht20test-wpa-$H.txt
rm -rf $W
nmcli dev set wlan0 managed yes
i=0; while [ $i -lt 90 ]; do nmcli -t -f DEVICE,STATE dev | grep -q '^wlan0:connected$' && break; sleep 3; i=$((i + 3)); done
log "back to NM: $(nmcli -t -f DEVICE,STATE,CONNECTION dev | grep ^wlan0)"
log done
