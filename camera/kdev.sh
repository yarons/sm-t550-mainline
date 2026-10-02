#!/bin/sh
# Kernel dev tree for fast module/DTB iteration (runs in alpine:edge aarch64, volume at /k).
# Usage: kdev.sh setup | module <dir-with-Makefile> | dtb | shell
set -eu
K=/k/linux
# pahole matters: without it olddefconfig drops DEBUG_INFO_BTF, which changes struct module
# and the running kernel rejects the .ko ("this_module section size must match").
apk add -q build-base clang lld llvm bison flex perl python3 openssl-dev elfutils-dev linux-headers \
	findutils bash diffutils gmp-dev mpc1-dev mpfr-dev zstd dtc pahole
case "${1:-}" in
setup)
	if [ ! -d "$K" ]; then
		mkdir -p /k && cd /k
		tar xzf /work/pmb/cache_distfiles/linux-postmarketos-qcom-msm8916-717e5e25225035d13c09b376aab5f23a5d7abe61.tar.gz
		mv linux-717e5e25225035d13c09b376aab5f23a5d7abe61 linux
		cd "$K"; patch -p1 < /work/pmaports/device/testing/linux-postmarketos-qcom-msm8916/0100-gt510-max77849-charger.patch
	fi
	cd "$K"
	cp /work/pmaports/device/testing/linux-postmarketos-qcom-msm8916/config-postmarketos-qcom-msm8916.aarch64 .config
	cat /work/pmaports/device/testing/linux-postmarketos-qcom-msm8916/gt510.config >> .config
	make ARCH=arm64 LLVM=1 olddefconfig >/dev/null
	make ARCH=arm64 LLVM=1 -j"$(nproc)" modules_prepare >/dev/null
	make ARCH=arm64 LLVM=1 -s kernelrelease ;;
module)
	cd "$2"; make -C "$K" ARCH=arm64 LLVM=1 M="$PWD" KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -vE "^  (CC|LD|MODPOST)" ;;
dtb)
	cd "$K"; make ARCH=arm64 LLVM=1 -s qcom/msm8916-samsung-gt510.dtb && ls -la arch/arm64/boot/dts/qcom/msm8916-samsung-gt510.dtb ;;
shell)
	exec sh ;;
esac
