set -e
apk add -q build-base meson ninja python3 py3-mako py3-yaml py3-packaging bison flex libdrm-dev wayland-dev \
	wayland-protocols expat-dev zlib-dev zstd-dev elfutils-dev glslang libx11-dev libxext-dev libxfixes-dev \
	libxcb-dev libxshmfence-dev libxxf86vm-dev libxrandr-dev libxdamage-dev xcb-util-keysyms-dev diffutils >/dev/null
cd /b/mesa-26.2.3 && python3 /src/log-staging.py && python3 /src/fix16.py && python3 /src/direct32.py && python3 /src/align64.py && python3 /src/cap128.py && python3 /src/frag256.py && ninja -C build >/dev/null && rm -rf /out/root && DESTDIR=/out/root ninja -C build install >/dev/null
cd /tmp && mkdir -p d/a/src/gallium/drivers/freedreno d/b/src/gallium/drivers/freedreno && cp /b/freedreno_resource.c.orig d/a/src/gallium/drivers/freedreno/freedreno_resource.c && cp /b/mesa-26.2.3/src/gallium/drivers/freedreno/freedreno_resource.c d/b/src/gallium/drivers/freedreno/ && (cd d && diff -u a/src/gallium/drivers/freedreno/freedreno_resource.c b/src/gallium/drivers/freedreno/freedreno_resource.c || true) > /out/0001-gt510-fd-upload-toggles.patch
echo REBUILT
