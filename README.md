# Samsung Galaxy Tab A 9.7 (SM-T550, gt510wifi) on mainline Linux + Phosh

An unofficial, ready-to-flash build for the 2015 Samsung Galaxy Tab A 9.7 Wi-Fi (SM-T550, APQ8016/MSM8916,
Adreno 306), based on postmarketOS/Nura with a mainline 7.3-rc2 kernel (msm8916-mainline) and a set of local
kernel, Mesa, GTK, libcamera and app patches that make the tablet usable day to day: accelerated GTK, both
cameras with autofocus, charging, USB OTG, GPU power management and a stable display.

**Not affiliated with or endorsed by postmarketOS/Nura.** It is built with their tooling (pmbootstrap, pmaports)
and their binary packages, but it is a separate, modified build. Please do not report problems with it to the
postmarketOS/Nura project; open an issue here instead.

**Made with AI assistance.** The investigation, patches, scripts and documentation in this repository were
produced together with an AI coding assistant (Anthropic's Claude), directed, reviewed and tested on the real
device by Yaron Shahrabani. `docs/session-notes/` keeps the working notes from those sessions as they were.

## Flash it

Download the latest release (`lk2nd-msm8916.img`, `gt510-unofficial-pmos-<date>-userdata.simg.xz`,
`SHA256SUMS`), then follow [docs/FLASHING.md](docs/FLASHING.md). In short:

1. Once, from Samsung download mode: flash `lk2nd-msm8916.img` to the **BOOT** partition (heimdall/samloader/Odin).
2. Boot holding **Volume Down** to reach lk2nd's fastboot, then
   `xz -d gt510-…-userdata.simg.xz && fastboot -S 64M flash userdata gt510-…-userdata.simg && fastboot reboot`.
3. First boot takes about 70 s and logs into Phosh automatically. User `user`, password **147147** — change it
   with `passwd`. SSH is installed but disabled: `sudo systemctl enable --now sshd`.

Flashing replaces Android and erases the tablet's data.

## What works

| Area | State |
|---|---|
| Display, touch, rotation (accelerometer), backlight + auto-brightness | works; DPMS on/off clean (kernel 0120/0121) |
| GPU (freedreno a306), GTK4 GL renderer, phoc | works without workarounds (local Mesa 0100); runtime PM on (0122) |
| Rear camera SR544 (5 MP, used at 1296x972) | ~22-24 fps preview in Snapshot, autofocus ~1.9 s, tuned colours (libcamera soft ISP on the GPU) |
| Front camera SR200PC20 | ~20-22 fps, 640x480 |
| Wi-Fi, Bluetooth, audio (speaker), sensors | works |
| Charging (MAX77849), battery gauge, USB networking | works |
| USB OTG host (micro-B OTG cable) | works (read tested) |
| CPU | 200-1209.6 MHz with CPR voltage scaling |
| Hardware video encoding (venus) | works, but rate control overshoots ~10x |
| GPS (Qualcomm PDS via gpsd) | service runs; no outdoor fix tested |
| Suspend, hall sensor, headphone jack, A2DP, 5 MP stills | not working / untested |

Known open problems are tracked in [ISSUES.md](ISSUES.md) (for example the camera service leaking ~8 MB of GPU
memory per Snapshot session).

## Build it yourself

Everything that goes into the image is in this repository: `pmos-gt510.sh` (pmbootstrap driver, runs in the
container from `build-host/Dockerfile`), `packages/` (local APKBUILDs + patches), `kernel/` (patches on top of
msm8916-mainline 7.3-rc2 @717e5e2 and the config fragment). See [docs/BUILDING.md](docs/BUILDING.md).
Release images are built with `pmos-gt510.sh install-public` + `release` (no personal keys or settings);
`MANIFEST.txt` in each release lists every installed package version and the pmaports commit.

## Repository map

| Path | Content |
|---|---|
| `kernel/` | kernel patches `0100`-`0124`, `gt510.config`, `apply-7.3.sh`, `kdev73.sh` (fast module dev tree) |
| `packages/` | gt510-tweaks (device integration), patched mesa, gtk4.0, libcamera, snapshot, phosh, gpsd, greetd-phrog |
| `build-host/` | builder container + job queue |
| `gl-hang/`, `gpu-pm/`, `gtk-fault/`, `display/`, `usb-otg/`, `shader-test/`, `camera/`, `libcamera-test/`, `mesa-test/` | measurement and debugging tools used during bring-up, with some evidence files |
| `upstream/` | patches and test reports prepared for upstream projects |
| `ISSUES.md` | the ordered work list with evidence for every fix |
| `docs/` | flashing, building, upstream status, session notes |

## Upstream

Several fixes are upstream bugs; see [docs/UPSTREAM.md](docs/UPSTREAM.md). Two kernel fixes carried here were
written by others and are carried verbatim: Sam Day's "drm/msm/a3xx: fix VBIF halt mask for A306/A306A" (0122)
and Dmitry Baryshkov's "drm/msm: fix dma-buf sharing on targets without per-process pgtables" (0123/0124).

## License

Scripts, tools and documentation in this repository: GPL-2.0 (see `LICENSE`). Patches are derivative works of
their projects and carry those projects' licenses: kernel patches GPL-2.0; Mesa patches MIT; GTK and libcamera
patches LGPL-2.1-or-later; Snapshot patches GPL-3.0-or-later; Phosh and phrog patches GPL-3.0-only; gpsd patches
BSD-2-Clause. The gt510-tweaks package is GPL-2.0-only.
Release images contain the binary packages of Alpine Linux and postmarketOS/Nura under their own licenses
(including redistributable firmware); sources are listed in each release's `MANIFEST.txt`.
