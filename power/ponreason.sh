#!/bin/sh
# ISSUES 30 (off-mode charging): decode why the PM8916 last powered on / off, plus charger and battery state.
# Reads only the PON block 0x800-0x80F of the PMIC regmap (SPMI SID 0) by seeking, nothing else. Run as root.
D=/sys/kernel/debug/regmap/0-00
reg() { dd if=$D/registers bs=9 skip=$(($1)) count=1 2>/dev/null | cut -d' ' -f2; }
bits() { # $1 = hex value, rest = names for bit 0..7
	v=$((0x$1)); shift; out=
	for n in "$@"; do [ $((v & 1)) = 1 ] && out="$out $n"; v=$((v >> 1)); done
	echo "${out:- (none)}"
}
r1=$(reg 0x808) w1=$(reg 0x80A) p1=$(reg 0x80C) p2=$(reg 0x80D)
echo "uptime: $(cut -d' ' -f1 /proc/uptime) s   boot: $(uptime -s 2>/dev/null)"
echo "PON_REASON1  0x808 = $r1:$(bits $r1 HARD_RESET SMPL RTC DC_CHG USB_CHG PON1 CBLPWR_N KPDPWR_N)"
echo "WARM_RESET1  0x80A = $w1:$(bits $w1 SOFT PS_HOLD PMIC_WD GP1 GP2 KPDPWR_AND_RESIN RESIN_N KPDPWR_N)"
echo "POFF_REASON1 0x80C = $p1:$(bits $p1 SOFT PS_HOLD PMIC_WD GP1 GP2 KPDPWR_AND_RESIN RESIN_N KPDPWR_N)"
echo "POFF_REASON2 0x80D = $p2:$(bits $p2 - - - CHARGER TFT UVLO OTST3 STAGE3)"
echo "cmdline androidboot: $(tr ' ' '\n' < /proc/cmdline | grep -E '^androidboot|lpm|charger' | tr '\n' ' ')"
for s in /sys/class/power_supply/*; do
	printf '%s: ' "${s##*/}"
	for a in online status capacity voltage_now current_now charge_now; do
		[ -r "$s/$a" ] && printf '%s=%s ' "$a" "$(cat "$s/$a")"
	done
	echo
done
