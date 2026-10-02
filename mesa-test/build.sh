#!/bin/sh
# Test build of Mesa 26.2.3 (freedreno only) with the FD_GT510 upload-path toggles.
set -e
apk add -q build-base meson ninja python3 py3-mako py3-yaml py3-packaging bison flex \
	libdrm-dev wayland-dev wayland-protocols expat-dev zlib-dev zstd-dev patch diffutils \
	elfutils-dev glslang libx11-dev libxext-dev libxfixes-dev libxcb-dev libxshmfence-dev \
	libxxf86vm-dev libxrandr-dev libxdamage-dev xcb-util-keysyms-dev >/dev/null
cd /b
[ -d mesa-26.2.3 ] || tar xJf /src/mesa-26.2.3.tar.xz
cd mesa-26.2.3
if ! grep -q FD_GT510 src/gallium/drivers/freedreno/freedreno_resource.c; then
	cp src/gallium/drivers/freedreno/freedreno_resource.c /b/freedreno_resource.c.orig
	python3 /src/mk-toggle.py
fi
mkdir -p /tmp/d/a/src/gallium/drivers/freedreno /tmp/d/b/src/gallium/drivers/freedreno
cp /b/freedreno_resource.c.orig /tmp/d/a/src/gallium/drivers/freedreno/freedreno_resource.c
cp src/gallium/drivers/freedreno/freedreno_resource.c /tmp/d/b/src/gallium/drivers/freedreno/
(cd /tmp/d && diff -u a/src/gallium/drivers/freedreno/freedreno_resource.c b/src/gallium/drivers/freedreno/freedreno_resource.c || true) > /out/0001-gt510-fd-upload-toggles.patch
rm -rf build
meson setup build -Dbuildtype=release -Db_ndebug=true -Dprefix=/usr \
	-Dgallium-drivers=freedreno -Dvulkan-drivers= -Dfreedreno-kmds=msm -Dplatforms=x11,wayland \
	-Dglx=dri -Dxlib-lease=enabled -Dopengl=true -Dgles1=disabled -Dgles2=enabled -Degl=enabled -Dgbm=enabled \
	-Dllvm=disabled -Dshader-cache=enabled -Dzstd=enabled -Dexpat=enabled -Dxmlconfig=enabled \
	-Dgallium-va=disabled -Dgallium-rusticl=false -Dvideo-codecs= -Dvalgrind=disabled \
	-Dlibunwind=disabled -Ddri-drivers-path=/usr/lib/dri
ninja -C build
rm -rf /out/root && DESTDIR=/out/root ninja -C build install >/dev/null
ls -la /out/root/usr/lib | head -30
