#!/bin/bash
# Runs inside the privileged t290-pmos container (colima profile t290).
# /src = ~/workspace/gt510-pmos (ro), /work = volume gt510-pmos-vol, /dist = output.
# Target: Samsung SM-T550 (gt510wifi) via generic device-qcom-msm8916 + lk2nd.
set -euo pipefail
sudo chown pmos:pmos /work /dist 2>/dev/null || true
git config --global --add safe.directory '*'
sudo git -C /opt/pmbootstrap pull -q --ff-only || true; pmbootstrap --version

git config --global http.version HTTP/1.1
for i in 1 2 3 4 5; do
	git -C /work/pmaports rev-parse HEAD >/dev/null 2>&1 && break
	rm -rf /work/pmaports
	git clone -q --depth 1 https://gitlab.postmarketos.org/postmarketOS/pmaports.git /work/pmaports && break
	sleep 10
done
git -C /work/pmaports pull -q --ff-only || true

CORES="libretro-snes9x,libretro-fceumm,libretro-nestopia,libretro-gambatte,libretro-mgba,libretro-genesis-plus-gx,libretro-picodrive,libretro-pcsx-rearmed,libretro-fbneo,libretro-mame2003,libretro-beetle-pce-fast,libretro-stella2014,libretro-parallel-n64,libretro-scummvm"
RA="retroarch,retroarch-assets,retroarch-joypad-autoconfig,libretro-core-info,libretro-database"
# Debug/measurement tools used by camera/, gl-hang/ and usb-otg/ (kmsgrab screenshots need ffmpeg).
# wlr-randr: rotate the output from SSH (gl-hang/rottest.sh).
TOOLS="ffmpeg,v4l-utils,libcamera-tools,gstreamer-tools,pipewire-tools,strace,i2c-tools,glmark2,perf,wlr-randr"
# Phone apps (Wi-Fi-only tablet, no modem): _pmb_recommends of postmarketos-base-ui-gnome-mobile.
# vvmd and mmsd-tng come in as their dependencies.
PHONE_APPS="calls chatty lpa-gtk vvmplayer"

mkdir -p ~/.config ~/.ssh /work/pmb
# Personal builds bake in the SSH keys from /src/pubkeys and the local timezone; the public release
# (install-public) gets neither -- see write_cfg calls below.
write_cfg() {  # $1 = ssh_keys True|False, $2 = timezone
cat > ~/.config/pmbootstrap_v3.cfg <<CFG
[pmbootstrap]
aports = /work/pmaports
work = /work/pmb
device = qcom-msm8916
kernel = extlinux
ui = phosh
user = user
hostname = gt510
jobs = $(nproc)
ssh_keys = $1
ssh_key_glob = ~/.ssh/*.pub
extra_packages = wireless-regdb,nano,htop,iw,openssh-server,gt510-tweaks,$TOOLS,$RA,$CORES
locale = en_US.UTF-8
timezone = $2
is_default_channel = False
CFG
}
if [ "${1:-}" = install-public ]; then
	write_cfg False UTC
else
	cp /src/pubkeys/*.pub ~/.ssh/ 2>/dev/null || true
	write_cfg True UTC
fi
[ -f /work/pmb/version ] || echo 8 > /work/pmb/version

PMB="pmbootstrap -y"
# Local packages (gt510-tweaks, patched gpsd/gtk4.0/phosh/libcamera/snapshot/greetd-phrog/mesa) live in /src/packages.
# A local package that overrides a pmaports one (e.g. extra-repos/systemd/phosh) replaces it in place,
# since pmbootstrap refuses duplicate package names; everything else goes to temp/.
copy_pkg() {
	dest=$(find /work/pmaports -mindepth 2 -maxdepth 3 -type d -name "$1" -not -path "*/temp/*" | head -1)
	[ -n "$dest" ] || { dest="/work/pmaports/temp/$1"; mkdir -p /work/pmaports/temp; }
	rm -rf "$dest"; cp -r "/src/packages/$1" "$dest"
}
build_pkgs() {
	for n in "$@"; do
		$PMB checksum "$n"
		$PMB build --force --arch aarch64 "$n"
	done
	mkdir -p /dist/localpkgs
	# Packages from extra-repos (e.g. systemd) land in their own channel dir (packages/systemd-edge/...).
	for n in "$@"; do find /work/pmb/packages -path "*/aarch64/*" -o -path "*/noarch/*" | grep -E "/$n-[0-9][^/]*\.apk$|/$n-[a-z-]+-[0-9][^/]*\.apk$" | xargs -r cp -v -t /dist/localpkgs/; done
}
case "${1:-all}" in
localpkgs)
	# Every local package visible to pmbootstrap: it also rebuilds any OUTDATED local dependency of the named
	# ones first (without the checksum step, so those must already be in the local repo).
	shift
	for d in /src/packages/*/; do copy_pkg "$(basename "$d")"; done
	build_pkgs "$@" ;;
localpkgs-only)
	# Only the named local packages visible (pmaports reset to git): all other dependencies come from the binary
	# repos, e.g. snapshot builds against Alpine's gtk4.0 instead of first rebuilding gtk4.0 and mesa.
	shift
	git -C /work/pmaports checkout -q -- . && git -C /work/pmaports clean -fdq
	for n in "$@"; do copy_pkg "$n"; done
	build_pkgs "$@" ;;
kernel73)
	sh /src/kernel/apply-7.3.sh
	$PMB checksum linux-postmarketos-qcom-msm8916
	$PMB build --force --arch aarch64 linux-postmarketos-qcom-msm8916
	mkdir -p /dist/kernel
	cp -v /work/pmb/packages/edge/aarch64/linux-postmarketos-qcom-msm8916-7.3_rc2-r39.apk /dist/kernel/ ;;
install)
	# pmbootstrap can only drop ALL recommends (--no-recommends), so strip the phone apps from the
	# local pmaports copy for this install and put the file back afterwards.
	GM=main/postmarketos-base-ui-gnome-mobile/APKBUILD
	trap 'git -C /work/pmaports checkout -- "$GM"' EXIT
	for a in $PHONE_APPS; do sed -i "/^[[:space:]]*$a\$/d" "/work/pmaports/$GM"; done
	sed -n '/_pmb_recommends=/,/"/p' "/work/pmaports/$GM"
	# Fresh chroots: no leftovers from earlier UI choices in the rootfs.
	$PMB zap
	$PMB install --password "${PMOS_PASSWORD:?}"
	$PMB export /dist/pmos
	ls -laL /dist/pmos/ ;;
install-public)
	# Generic image for the public release: no SSH keys, sshd disabled, UTC, documented default password
	# (PUBLIC_PASSWORD, default 147147 -- users change it with passwd). Same packages as a personal install.
	GM=main/postmarketos-base-ui-gnome-mobile/APKBUILD
	trap 'git -C /work/pmaports checkout -- "$GM"' EXIT
	for a in $PHONE_APPS; do sed -i "/^[[:space:]]*$a\$/d" "/work/pmaports/$GM"; done
	$PMB zap
	$PMB install --no-sshd --password "${PUBLIC_PASSWORD:-147147}"
	$PMB export /dist/pmos
	ls -laL /dist/pmos/ ;;
release)
	# Release assets from the install-public rootfs: xz'd sparse userdata image (GitHub assets max 2 GB),
	# lk2nd boot image, package manifest with source pointers, SHA256SUMS.
	img=/work/pmb/chroot_native/home/pmos/rootfs/qcom-msm8916.img
	R=/dist/release; D=$(date -u +%Y%m%d); N=gt510-unofficial-pmos-$D
	mkdir -p "$R"; rm -f "$R"/*
	img2simg "$img" "$R/$N-userdata.simg"
	xz -T0 -6 "$R/$N-userdata.simg"
	cp /dist/lk2nd.img "$R/lk2nd-msm8916.img"
	{ echo "# $N -- installed packages (name version); local patches: packages/ and kernel/ in this repo"
	  echo "# pmaports commit: $(git -C /work/pmaports rev-parse HEAD)"
	  echo "# kernel: msm8916-mainline/linux @717e5e25225035d13c09b376aab5f23a5d7abe61 + kernel/0*.patch"
	  awk '/^P:/{p=substr($0,3)} /^V:/{print p" "substr($0,3)}' /work/pmb/chroot_rootfs_qcom-msm8916/lib/apk/db/installed | sort
	} > "$R/MANIFEST.txt"
	(cd "$R" && sha256sum *.xz *.img MANIFEST.txt > SHA256SUMS)
	ls -la "$R"; cat "$R/SHA256SUMS" ;;
lk2nd)
	# Prebuilt lk2nd-msm8916 from the pmOS binary repo, extracted from the native chroot.
	# aarch64 buildroot, not the native chroot: native is x86_64 on the laptop builder (no such package there).
	$PMB chroot --buildroot aarch64 -- apk add lk2nd-msm8916
	$PMB chroot --buildroot aarch64 -- sh -c 'cat $(apk info -L lk2nd-msm8916 | grep "lk2nd.img$" | sed "s|^|/|")' > /dist/lk2nd.img
	$PMB chroot --buildroot aarch64 -- apk info lk2nd-msm8916 | head -1
	ls -la /dist/lk2nd.img ;;
simg)
	# Flashable sparse image (macOS fastboot needs it) from the install target's rootfs image.
	img=/work/pmb/chroot_native/home/pmos/rootfs/qcom-msm8916.img
	ls -la "$img"
	img2simg "$img" /dist/qcom-msm8916.simg
	sha256sum /dist/qcom-msm8916.simg /dist/lk2nd.img 2>/dev/null
	ls -la /dist/qcom-msm8916.simg ;;
image)
	# Full image: kernel with local patches, local packages, rootfs, lk2nd.
	"$0" kernel73 && "$0" image-rest ;;
image-tail)
	"$0" localpkgs gt510-tweaks && "$0" install && "$0" lk2nd ;;
image-rest)
	"$0" localpkgs gt510-tweaks gpsd gtk4.0 phosh libcamera snapshot greetd-phrog && "$0" install && "$0" lk2nd ;;
all)
	"$0" install && "$0" lk2nd ;;
shell)
	exec bash ;;
esac
