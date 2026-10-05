#!/bin/sh
# Retarget pmaports linux-postmarketos-qcom-msm8916 (6.12.1) at msm8916-mainline wip/msm8916/7.3-rc2.
set -eu
SHA=717e5e25225035d13c09b376aab5f23a5d7abe61
d=/work/pmaports/device/testing/linux-postmarketos-qcom-msm8916
git -C /work/pmaports checkout -q -- "$d"
cd "$d"
sed -i \
	-e 's/^pkgver=.*/pkgver=7.3_rc2/' \
	-e 's/^pkgrel=.*/pkgrel=0/' \
	-e "s|^_tag=.*|_commit=$SHA|" \
	-e 's|\$pkgname-\$_tag.tar.gz::\$url/archive/\$_tag.tar.gz|$pkgname-$_commit.tar.gz::$url/archive/$_commit.tar.gz|' \
	-e '/0001-kbuild-Add-fno-builtin-wcslen.patch/d' \
	-e 's|^builddir=.*|builddir="$srcdir/linux-$_commit"|' \
	-e 's|cp "\$srcdir/config-\$_flavor.\$CARCH" .config|cp "$srcdir/config-$_flavor.$CARCH" .config\n\tmake ARCH="$_carch" LLVM=1 olddefconfig|' \
	APKBUILD
rm -f 0001-kbuild-Add-fno-builtin-wcslen.patch

# gt510 local changes: MAX77849 charger/MUIC, gauge supply link, front+rear cameras + AF lens, panel brightness, DSI clock, MDP5 enable order, a306 VBIF halt mask, shared-VM dma-buf fix (patches + config fragment)
rm -f 0*.patch  # the aport dir persists between runs: drop stale local patches first
cp /src/kernel/0*.patch /src/kernel/gt510.config .
sed -i \
	-e 's/^pkgrel=.*/pkgrel=37/' \
	-e "s|^\tconfig-\$_flavor.aarch64$|&\n\tgt510.config\n$(ls 0*.patch | sed 's/^/\\t/' | tr '\n' '@' | sed 's/@$//; s/@/\\n/g')|" \
	-e 's|^\tmake ARCH="\$_carch" LLVM=1 olddefconfig$|\tcat "$srcdir/gt510.config" >> .config\n&|' \
	APKBUILD
grep -nE '^pkgver|^pkgrel|^_commit|archive|^builddir|olddefconfig|wcslen' APKBUILD
