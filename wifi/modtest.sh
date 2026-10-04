#!/bin/sh
# modtest.sh <wcn36xx.ko> — load a test wcn36xx module from updates/, confirm 5 GHz comes back, then try the 2.4 GHz
# BSSID through NetworkManager and return to the 5 GHz lock. SELF-REVERTING: no 5 GHz connection within 120 s → remove
# the test module, depmod, reload the packaged one. Run as root (Wi-Fi may be the only link):
#   systemd-run --unit=modtest --collect /home/user/modtest.sh /home/user/wcn36xx.ko
KO=$1; O=/home/user/modtest.out; C=${NM_CON:-"HOME-WIFI"}; BG=${BSSID_2G:-AP-2G-BSSID}; U=/lib/modules/$(uname -r)/updates
log() { echo "$(date +%T) $*" >> $O; }
kc() { journalctl -k --no-pager --since "@$1" | grep -cE "$2"; }
jc() { journalctl --no-pager --since "@$1" | grep -cE "$2"; }
wait_conn() { i=0; while [ $i -lt "$1" ]; do nmcli -t -f DEVICE,STATE dev | grep -q '^wlan0:connected$' && return 0; sleep 2; i=$((i + 2)); done; return 1; }
freq() { nmcli -t -f IN-USE,BSSID,FREQ dev wifi list 2>/dev/null | grep '^\*' | cut -d: -f2- | tr -d '\\'; }
reload() { modprobe -r wcn36xx; sleep 2; modprobe wcn36xx; }
ht2g() { iw phy "$(ls /sys/class/ieee80211 | head -1)" info | awk '/Band 1:/{b=1} /Band 2:/{b=0} b && /HT20|HT40|Capabilities:/' | tr -d '\t' | tr '\n' ' '; }

log "== $KO ($(modinfo -F vermagic "$KO"))"
mkdir -p $U && cp "$KO" $U/wcn36xx.ko && depmod -a
t0=$(date +%s); reload
if wait_conn 120; then
	log "5 GHz back after $(( $(date +%s) - t0 ))s on $(freq); module $(modinfo -n wcn36xx); taint $(cat /proc/sys/kernel/tainted); 2.4 GHz caps: $(ht2g)"
else
	log "NO connection in 120 s → REVERT"; rm -f $U/wcn36xx.ko; depmod -a; reload
	wait_conn 120 && log "reverted, connected on $(freq)" || log "reverted, STILL no connection"; exit 1
fi
t2=$(date +%s)
nmcli con modify "$C" 802-11-wireless.band bg 802-11-wireless.bssid $BG
timeout 60 nmcli con up "$C" >/dev/null 2>&1; r=$?
sleep 20
log "2.4 GHz via NM: rc=$r, $(nmcli -t -f DEVICE,STATE dev | grep ^wlan0) on $(freq); hal_join errors $(kc $t2 'hal_join response failed'), config_bss errors $(kc $t2 'hal_config_bss response failed'), WRONG_KEY $(jc $t2 WRONG_KEY), beacon loss $(jc $t2 BEACON-LOSS)"
log "2.4 GHz link: $(iw dev wlan0 link | grep -E 'freq|tx bitrate|rx bitrate|signal' | tr -d '\t' | tr '\n' ' ')"
gw=$(ip -4 route show dev wlan0 | awk '/^default/{print $3; exit}')
[ -n "$gw" ] && log "2.4 GHz ping $gw: $(ping -c 10 -W 2 "$gw" 2>&1 | grep -E 'packets transmitted|round-trip')"
nmcli con modify "$C" 802-11-wireless.band a 802-11-wireless.bssid ""
timeout 60 nmcli con up "$C" >/dev/null 2>&1
wait_conn 60; log "back on the 5 GHz lock: $(nmcli -g 802-11-wireless.band con show "$C") on $(freq)"
log done
