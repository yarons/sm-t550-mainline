#!/bin/sh
# Kernel dev tree (7.3-rc2 + kernel/0*.patch + the tablet's running config) for fast module builds.
# Runs in alpine:edge aarch64 (colima t290): -v gt510-pmos-vol:/work:ro -v gt510-kdev:/k -v .../gt510-pmos/kernel:/src
# Usage: kdev73.sh setup | msm | module <dir> | shell
set -eu
K=/k/linux
apk add -q build-base clang lld llvm bison flex perl python3 openssl-dev elfutils-dev linux-headers \
	findutils bash diffutils gmp-dev mpc1-dev mpfr-dev zstd dtc pahole patch
case "${1:-}" in
setup)
	rm -rf "$K"; mkdir -p /k && cd /k
	tar xzf /work/pmb/cache_distfiles/linux-postmarketos-qcom-msm8916-717e5e25225035d13c09b376aab5f23a5d7abe61.tar.gz
	mv linux-717e5e25225035d13c09b376aab5f23a5d7abe61 linux
	cd "$K"
	for p in /src/0*.patch; do echo "== $p"; patch -p1 -F0 -s < "$p"; done
	cp "/src/${KCONFIG:-running-config-r28}" .config
	make ARCH=arm64 LLVM=1 olddefconfig >/dev/null
	diff "/src/${KCONFIG:-running-config-r28}" .config | grep -E '^[<>] CONFIG' || echo "config identical"
	make ARCH=arm64 LLVM=1 -j"$(nproc)" modules_prepare >/dev/null
	make ARCH=arm64 LLVM=1 -s kernelrelease ;;
msm)
	cd "$K"; make ARCH=arm64 LLVM=1 -j"$(nproc)" M=drivers/gpu/drm/msm KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -vE "^  (CC|LD|AR|MODPOST|GEN|HOSTCC)|undefined!$|WARNING: modpost" || true
	mkdir -p /src/out && cp drivers/gpu/drm/msm/msm.ko /src/out/msm.ko && ls -la /src/out/msm.ko ;;
module)
	cd "$2"; make -C "$K" ARCH=arm64 LLVM=1 M="$PWD" KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -vE "^  (CC|LD|MODPOST)" ;;
shell)
	exec sh ;;
esac
