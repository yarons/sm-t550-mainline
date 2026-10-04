#!/bin/sh
# nvtest.sh <nv.bin> — try a WCNSS NV file: install it as /lib/firmware/updates/wlan/prima/WCNSS_qcom_wlan_nv.bin
# (searched before /lib/firmware), restart the WCNSS remoteproc (the NV is downloaded at WCNSS boot), wait for the
# 5 GHz connection, then try the 2.4 GHz BSSID once and go back to 5 GHz. SELF-REVERTING: no 5 GHz connection within
# 120 s → remove the file and restart WCNSS again. Run as root (Wi-Fi may be the only link):
#   systemd-run --unit=nvtest --collect /home/user/nvtest.sh /home/user/wcnss-stock/WCNSS_qcom_wlan_nv.bin
[ -z "$NVTEST_INHIBITED" ] && NVTEST_INHIBITED=1 exec systemd-inhibit --what=sleep:idle --who=nvtest \
	--why="WCNSS NV test" "$0" "$@"
NV=$1; O=/home/user/nvtest.out; C=${NM_CON:-"HOME-WIFI"}; BG=${BSSID_2G:-AP-2G-BSSID}
D=/lib/firmware/updates/wlan/prima; RP=$(dirname "$(grep -l a204000.remoteproc /sys/class/remoteproc/*/name)")
log() { echo "$(date +%T) $*" >> $O; }
kc() { journalctl -k --no-pager --since "@$1" | grep -cE "$2"; }
restart_wcnss() { echo stop > "$RP/state"; sleep 2; echo start > "$RP/state"; }
wait_conn() {  # up to $1 s for wlan0 connected
	i=0; while [ $i -lt "$1" ]; do
		nmcli -t -f DEVICE,STATE dev | grep -q '^wlan0:connected$' && return 0; sleep 2; i=$((i + 2))
	done; return 1
}
freq() { nmcli -t -f IN-USE,BSSID,FREQ dev wifi list 2>/dev/null | grep '^\*' | cut -d: -f2- | tr -d '\\'; }

log "== NV $NV sha256 $(sha256sum "$NV" | cut -c1-16), remoteproc $RP"
mkdir -p $D && cp "$NV" $D/WCNSS_qcom_wlan_nv.bin
t0=$(date +%s); restart_wcnss
if wait_conn 120; then
	log "5 GHz back after $(( $(date +%s) - t0 ))s on $(freq); hal_join errors $(kc $t0 'hal_join response failed'), bmps errors $(kc $t0 'Can not enter BMPS')"
else
	log "NO connection in 120 s (hal_join errors $(kc $t0 'hal_join response failed')) → REVERT"
	rm -f $D/WCNSS_qcom_wlan_nv.bin; t1=$(date +%s); restart_wcnss
	wait_conn 120 && log "reverted, connected again on $(freq)" || log "reverted, STILL no connection"
	exit 1
fi
# One 2.4 GHz attempt, pinned to the 2.4 GHz BSSID; always back to the 5 GHz lock afterwards.
t2=$(date +%s)
nmcli con modify "$C" 802-11-wireless.band bg 802-11-wireless.bssid $BG
timeout 60 nmcli con up "$C" >/dev/null 2>&1; r=$?
sleep 15
log "2.4 GHz: nmcli rc=$r, state $(nmcli -t -f DEVICE,STATE dev | grep ^wlan0), on $(freq), hal_join errors $(kc $t2 'hal_join response failed'), config_bss errors $(kc $t2 'hal_config_bss response failed'), WRONG_KEY $(journalctl --no-pager --since "@$t2" | grep -c WRONG_KEY), beacon loss $(journalctl --no-pager --since "@$t2" | grep -c BEACON-LOSS)"
gw=$(ip -4 route show dev wlan0 | awk '/^default/{print $3; exit}')
[ -n "$gw" ] && log "2.4 GHz ping $gw: $(ping -c 5 -W 2 "$gw" 2>&1 | grep -E 'packets transmitted')"
nmcli con modify "$C" 802-11-wireless.band a 802-11-wireless.bssid ""
timeout 60 nmcli con up "$C" >/dev/null 2>&1
wait_conn 60; log "back on the 5 GHz lock: $(nmcli -g 802-11-wireless.band con show "$C") on $(freq)"
log done
