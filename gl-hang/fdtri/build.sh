#!/bin/sh
# Build fdtri for the tablet in alpine:edge aarch64 (colima t290): -v ~/workspace/gt510-pmos/gl-hang/fdtri:/s
set -e
apk add -q build-base mesa-dev >/dev/null
cc -O2 -Wall -o /s/fdtri /s/fdtri.c -lEGL -lGLESv2 -lgbm
ls -la /s/fdtri
