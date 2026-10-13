#!/bin/sh
# Test build of Mesa 26.2.4 (freedreno only) = the installed mesa r100 (packages/mesa 0100) + extra patches, for
# ~/mesatest264 on the tablet (LD_LIBRARY_PATH/LIBGL_DRIVERS_PATH/GBM_BACKENDS_PATH, see gl-hang/mtest.sh); nothing is
# installed system-wide. Runs in alpine:edge aarch64 (colima t290):
#   -v gt510-mesa-vol:/b -v ~/workspace/gt510-pmos:/src:ro -v ~/workspace/gt510-pmos/mesa-test/out:/out
# Env: PATCHES="<files under /src/packages/mesa>" (default: 0100 + 0101), TAG=<name> (output /out/mesatest-<TAG>.tgz).
set -e
TAG=${TAG:-264}
PATCHES=${PATCHES:-"0100-gt510-freedreno-a3xx-gtk4-gl.patch 0101-freedreno-a3xx-flush-hlsq-before-indirect-const-loads.patch"}
SHA512=42e793561661a567e72c7324d071ab9f82d3a9f1e000827ed989b8d5fcc2cd16e50c02808d43465b3135c25a3cad77649ba0bf9e35d95b848f8fc8d8b9ce327c
apk add -q build-base meson ninja python3 py3-mako py3-yaml py3-packaging bison flex curl \
	libdrm-dev wayland-dev wayland-protocols expat-dev zlib-dev zstd-dev patch diffutils \
	elfutils-dev glslang libx11-dev libxext-dev libxfixes-dev libxcb-dev libxshmfence-dev \
	libxxf86vm-dev libxrandr-dev libxdamage-dev xcb-util-keysyms-dev >/dev/null
cd /b
if [ ! -f mesa-26.2.4.tar.xz ]; then
	curl -sfL -o mesa-26.2.4.tar.xz.part https://archive.mesa3d.org/mesa-26.2.4.tar.xz
	echo "$SHA512  mesa-26.2.4.tar.xz.part" | sha512sum -c - && mv mesa-26.2.4.tar.xz.part mesa-26.2.4.tar.xz
fi
rm -rf "src-$TAG" && mkdir "src-$TAG" && tar xJf mesa-26.2.4.tar.xz -C "src-$TAG"
cd "src-$TAG/mesa-26.2.4"
for p in $PATCHES; do echo "== $p"; patch -p1 -F0 < "/src/packages/mesa/$p"; done
meson setup build -Dbuildtype=release -Db_ndebug=true -Dprefix=/usr \
	-Dgallium-drivers=freedreno -Dvulkan-drivers= -Dfreedreno-kmds=msm -Dplatforms=x11,wayland \
	-Dglx=dri -Dxlib-lease=enabled -Dopengl=true -Dgles1=disabled -Dgles2=enabled -Degl=enabled -Dgbm=enabled \
	-Dllvm=disabled -Dshader-cache=enabled -Dzstd=enabled -Dexpat=enabled -Dxmlconfig=enabled \
	-Dgallium-va=disabled -Dgallium-rusticl=false -Dvideo-codecs= -Dvalgrind=disabled \
	-Dlibunwind=disabled -Ddri-drivers-path=/usr/lib/dri >/dev/null
ninja -C build >/dev/null
rm -rf /tmp/root && DESTDIR=/tmp/root ninja -C build install >/dev/null
tar czf "/out/mesatest-$TAG.tgz" -C /tmp root
ls -la "/out/mesatest-$TAG.tgz"; ls /tmp/root/usr/lib /tmp/root/usr/lib/dri | head -20
