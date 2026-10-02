#!/bin/sh
# Test build of libcamera 0.7.2 + packages/libcamera patches (+ /src/extra/*.patch), minimal options,
# for LD_LIBRARY_PATH use by wireplumber@video-capture on the tablet. Volume /b keeps the build dir.
set -e
apk add -q build-base meson ninja python3 py3-yaml py3-jinja2 py3-ply yaml-dev eudev-dev libdrm-dev \
	mesa-dev libunwind-dev gnutls-dev openssl patch >/dev/null
cd /b
if [ ! -d libcamera-v0.7.2 ]; then
	tar xzf /src/libcamera-v0.7.2.tar.gz
	cd libcamera-v0.7.2
	for p in /pkg/0*.patch; do patch -p1 -s < "$p"; done
	cd ..
fi
cd libcamera-v0.7.2
for p in /src/extra/*.patch; do [ -e "$p" ] || continue; patch -p1 -s -N --dry-run < "$p" >/dev/null 2>&1 && patch -p1 -s -N < "$p" && echo "applied $p"; done
[ -d build ] || meson setup build -Dbuildtype=release -Dprefix=/usr -Dpipelines=simple -Dipas=simple \
	-Dcam=disabled -Dqcam=disabled -Dgstreamer=disabled -Dv4l2=false -Dpycamera=disabled \
	-Ddocumentation=disabled -Dtest=false -Dlc-compliance=disabled -Dtracing=disabled -Dudev=enabled
ninja -C build
rm -rf /out/root && DESTDIR=/out/root ninja -C build install >/dev/null
ls -la /out/root/usr/lib/ | head
