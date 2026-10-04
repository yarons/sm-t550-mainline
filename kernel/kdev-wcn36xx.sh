#!/bin/sh
# Build wcn36xx.ko against the tablet's r34 config in colima t290 (kdev73.sh tree), output out/wcn36xx.ko.
cd "$(dirname "$0")"
D() { docker --context colima-t290 run --rm -e KCONFIG=running-config-r34 -v gt510-pmos-vol:/work:ro -v gt510-kdev:/k -v "$PWD:/src" alpine:edge sh /src/kdev73.sh "$@"; }
D setup > kdev-setup-r34.log 2>&1; echo "setup rc=$?"; tail -5 kdev-setup-r34.log
D module /k/linux/drivers/net/wireless/ath/wcn36xx > kdev-wcn36xx.log 2>&1; echo "module rc=$?"; tail -5 kdev-wcn36xx.log
docker --context colima-t290 run --rm -v gt510-kdev:/k -v "$PWD:/src" alpine:edge sh -c 'apk add -q llvm >/dev/null 2>&1; mkdir -p /src/out; llvm-strip --strip-debug -o /src/out/wcn36xx.ko /k/linux/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko; ls -la /src/out/wcn36xx.ko; grep -c SUP_WIDTH_20_40 /k/linux/drivers/net/wireless/ath/wcn36xx/main.c'
strings out/wcn36xx.ko | grep -m1 vermagic
