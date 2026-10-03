# Continuation prompt: Samsung Galaxy Tab A 9.7 (SM-T550, gt510wifi) on postmarketOS

Paste this into a new session to continue. Everything lives in `~/workspace/gt510-pmos/`.
- `ISSUES.md` — the ordered issue list. Yaron (2026-10-01): "collect all the issues in a side note and work on them
  sequentially". Add new issues there, work top to bottom, update it after every step.
- `CONTINUATION-PROMPT.2026-09-27-history.md` — how every fix was found (camera bring-up, venus, SD card, OTG, GL
  renderer, CPR, camera texture path, co-sited Bayer, Mesa a3xx bugs, autofocus…), including every earlier version of
  this file verbatim (the last one = "as of 2026-10-01 18:10"). Read the relevant part before re-investigating.
- Memory: `samsung-t550-gt510.md`, `upstream-ai-policies.md`, `check-ai-policy-before-upstreaming.md`.

## State (2026-10-01 evening) — everything below is INSTALLED and verified on the tablet

2026-10-02: the tablet runs the PUBLIC release image (rebranded, gt510-tweaks r35 + kernel r32), boot-tested OK, then
restored to the personal setup by hand: password <password>, timezone UTC, SSH key, sshd enabled, Pictures/
Videos + test scripts from backup-2026-10-02/ (Wi-Fi + RetroArch were already back via the user / the SD card).
Release assets (flashable): `dist/release-20261002/` (userdata.simg.xz sha256 05714cdc…, lk2nd, MANIFEST, SHA256SUMS,
RELEASE-NOTES.md for GitHub). Personal baseline image `dist/qcom-msm8916-2026-10-01-r34-k32.simg` lacks tweaks r35.
PUBLIC REPO: github.com/yarons/sm-t550-mainline (push with `core.sshCommand` = ~/.ssh/old_id_rsa, the personal
key; ~/.ssh/id_ed25519 and gh are the WORK account). Built from gt510-pmos by review/assemble-public.sh (local only:
curated copy + scrub map review/scrub-map.tsv + leftover scan); commits e492aca, 4ca122b (rebrand).
Release images: `pmos-gt510.sh install-public` (no keys, sshd off, UTC, password 147147) + `release`.
`ISSUES.md`: everything DONE except item 5 (front-camera "no more input formats" — WATCH, cleared by a reboot).
`/lib/modules/7.3.0-rc2-msm8916/updates/` is EMPTY (keep it that way; test modules shadow the package).
OPEN: ISSUES 12 (camera service leaks ~8.1 MB GPU memory per Snapshot session; user space). Upstream hand-off for
Yaron: `upstream/README.md` (mdp5 0120 patch ready to sign+send; Tested-by replies for Sam Day's a306 patch and
Dmitry Baryshkov's shared-VM series). 
| Package | Version | Local patches |
|---|---|---|
| linux-postmarketos-qcom-msm8916 | 7.3_rc2-**r32** (#33) | msm8916-mainline 7.3-rc2 @717e5e2 + `kernel/0100`–`0107`, `0109`–`0118`, **`0120`–`0124`** + `kernel/gt510.config` |
| gt510-tweaks | **r34** | see "gt510-tweaks" (r34: GPU runtime-PM udev rule gone, depends kernel>=r30) |
| libcamera | 99990.7.2-**r111** | pmOS fork + 0100 YUV passthrough/SR544 helper · 0101 soft-ISP contrast AF · 0102 cap only scalable outputs · 0103 YUV sensors via CAMSS PIX as NV12 · 0104 skip the neutral contrast curve · **0105 co-sited Bayer cells** · **0106 black level+AWB as one multiply-add** · **0107 faster AF** |
| mesa (+dri-gallium, egl, gbm, gl, gles) | 26.2.3-**r101** | LOCAL slim build (freedreno + llvmpipe; GL/GLES/EGL/GBM only) + **0100 freedreno a3xx fixes** |
| snapshot | 51.0-**r112** | 0100 aperture paintable orientation (+EXIF/mp4 tags) · 0101 viewfinder sink sync=false · **0102 QrScreenBin snapshots its child once** (enables offload); Exec env `GSK_RENDERER=gl` only |
| gtk4.0 | 4.24.0-**r103** | 0100 no powf sRGB round trip (YUV, cairo) · 0101 cairo quarter-turn textures · 0102 import LINEAR dmabufs without explicit modifier |
| phosh | 99990.57.0-**r100** | 0100 cellular tile hidden without a modem |
| gpsd | 3.27.3-**r101** | Qualcomm PDS (`pds://any`) |
| greetd-phrog | 0.53.0-**r100** | 0100 no greetd session for an empty username ("password twice") |

Kernel patches: 0100 MAX77849 charger/MUIC · 0101 charger = USB supply of the gauge · 0102 front camera SR200PC20 +
DT + camss CSID1 fix · 0103 s6d7aa0 1-byte brightness · 0104 msm DSI no link-clock re-set per command · 0105 rear
SR544 + DT · 0106 DW9804 lens · 0107/0109/0110/0111 venus encoder on HFI 1.x · 0112 USB OTG host (dual-role DT,
MAX77849 boost regulator + shutdown hook, MUIC ADCLow/CHGDETEN fixes) · 0113 CPR + cpufreq to 1209.6 MHz · 0114 camss:
restore the MSM8916 VFE PIX line (line_num 3→4) · 0115 SR200PC20 640x480 preview mode · 0116 MUIC: CDP is USB data too
(USB networking on the Mac's port) · 0117 sr544 + sr200pc20 probe retries the chip-id read · 0118 extcon-max77693
per-group pending bits (OTG unplug was lost → boost stayed on). REVERTED: 0119 (RDI bpl 32; attic/kernel/).
r32 adds **0123/0124** = Dmitry Baryshkov's upstream series 172617 "drm/msm: fix dma-buf sharing on targets without
per-process pgtables" (verbatim): msm_gem_close() no longer tears down mappings in a2xx-a5xx's single global GPU VM →
the GTK4 app-start/exit GPU fault storms are gone (ISSUES 11).
r31 also carries **0122** = Sam Day's upstream "drm/msm/a3xx: fix VBIF halt mask for A306/A306A" (patchwork 756513,
verbatim; a306 has 3 VBIF XIN clients, be0e82b8e0c9 waited for 6 → runtime suspend never worked).
r29 (2026-10-01): **0120** mdp5: flush the CTL
BEFORE enabling the video timing engine (the first frame after every CRTC enable scanned the pre-disable pipe state →
iommu faults at a freed phoc buffer, INTF1 underrun, vblank timeout, boot-time underrun) · **0121** s6d7aa0: no
backlight DCS write while the panel is disabled (logind/Phosh brightness writes during blank → -22/EPROTO).

### gt510-tweaks r33 (what it ships)
charger module autoload, accel mount matrix, GPU runtime PM left on (r34; the udev "on" rule is gone), hkdm keys (Home/Recents) + Back touch key =
Escape (hwdb), gpsd-pds.service, THP madvise, zram lz4, animations off, auto-brightness, tile/service masks,
`/etc/profile.d/zz-gt510-gtk-gl.sh` (GSK_RENDERER=gl — the ONLY GTK GL setting now), libcamera config
(`gt510-libcamera.yaml` → /etc/libcamera/configuration.yaml: soft ISP for camss, output cap 1296x972,
`software_isp: cosited_max_width: 1296`), SR544 tuning `sr544.yaml` (CCM/AWB from a screen chart, Af: coarseStep 93,
fineStep 24, settle 2 frames), wireplumber split (`90-gt510-split-video.conf` + wireplumber@video-capture),
auto-login (greetd initial_session, `/etc/gt510/greetd-autologin.toml`), lock/idle gschema overrides (+`:Phosh` and
`:Phrog` sections), gt510-persist (dconf + ~/.config/retroarch mirrored to `<SD>/.gt510-persist/`, restored once after
a reflash), RetroArch defaults (pointer, wayland input, fullscreen, StartupNotify=false), and since 2026-10-01:
- r30: the GTK freedreno workarounds are GONE (no environment.d/61-gt510-freedreno.conf, no wireplumber unset
  drop-in); depends `mesa>=26.2.3-r101` + `mesa-dri-gallium<26.2.4` — an unpatched Alpine Mesa would hang the GPU
  within seconds of a GTK app starting. When Alpine moves past 26.2.3: rebuild packages/mesa on the new version
  FIRST, then move both pins (until then `apk upgrade` holds Mesa back).
- r31: `pipewire.service` enabled at login (the camera service is WantedBy=pipewire.service; socket activation made it
  start with the first Snapshot → the first Snapshot after boot opened the front camera).
- r32: presets for fresh images — user `enable wireplumber@.service video-capture`, system 80-gt510.preset
  `enable gpsd-pds/hkdm/rmtfs` (the preset run after post-install had disabled the camera service and gpsd-pds).
- r33: `gt510-camera-permission` (user oneshot at login): portal PermissionStore devices/camera
  org.gnome.Snapshot=['yes'] only if NO decision exists yet (Yaron's choice; a later "no" is kept).

## How the cameras work now (measured 2026-09-30 / 10-01)
- REAR SR544: binned modes (1296x972, 1280x720) deliver CO-SITED Bayer cells (all 4 samples of a 2x2 cell at one spot;
  standard demosaic misplaced red/blue by ~1 px = purple/yellow fringes). libcamera 0105: the CPU unpacks each cell into
  one (R,G,B,G) RGBA texel (648x486 real colour samples), the GPU debayer is ONE bilinear lookup + 0106 folded colour
  math. ISP GPU 25 → 13 ms/frame. The 5 MP mode is not co-sited (never used: config caps 1296x972).
- Snapshot → GtkGraphicsOffload works since snapshot 0102 (Snapshot 51 drew the viewfinder twice): phoc composites the
  camera dmabuf as a subsurface with the 90° transform; Snapshot's own GPU time ~0. Rear preview ~22-24 fps shown,
  ISP 25-27 frames/s, sensor 28-29 (was 13 at the start of 2026-09-30). gl-hang/disprate.sh = GPU jobs/s per process.
- AF (0107): focus measure every frame (SwIspStats::focusValid; AGC/AWB still every 4th frame via `valid`),
  early-stop coarse sweep from 0 + parabola + 3 fine steps, settle 2 frames: 6.8 → 1.9 s stream-start-to-focus
  (gl-hang/aftime.sh). Yaron: "pretty fast". Faster knobs if ever wanted: settle 1, stopRatio 0.8.
- Gamma stays 2.2 (Yaron: "the colors look great"; sqrt gamma would save 2.8 ms ISP).
- FRONT SR200PC20: YUV via the CAMSS PIX line as NV12/NV21 640x480, imported as GL_TEXTURE_EXTERNAL_OES, ~20-22 fps.
- Rotation: verified with gl-hang/rottest.sh (wlr-randr transform under a running Snapshot) + Yaron by hand.

## Mesa a3xx (packages/mesa r101, patch 0100) — why the GTK workarounds could go
- nouboopt HANG = CP_LOAD_STATE SS_INDIRECT into the FRAGMENT shader state block (VS indirect loads are fine; 128-byte
  UBO alignment alone did not fix it) → FS const_bo loads copied into the cmdstream (SS_DIRECT from fd_bo_map).
- inorder BLACK FRAMES = freedreno's staging upload of GTK's per-frame UBO (no hw blitter → recursive unsynchronised
  map) → buffers without a hw blitter always shadow, never staging.
- a3xx constant_buffer_offset_alignment 128 (ir3's own rule for indirect sources).
- Verified without workarounds: 10 GTK apps × 25 s 0 hangs / 0 GPU faults (the fault storms at GTK app start are gone
  too), calculator 90 s (used to hang in 3-8 s), Snapshot 0/73 black frames, phoc/phosh fine after reboots.
- The workarounds had cost: every uniform became a per-pixel ldg (Snapshot 38.7 → 24.7 ms GPU without nouboopt);
  RetroArch 59 → 37 fps with them.
- Slim build because pmbootstrap's crossdirect compiles Rust (rusticl, nouveau NAK) for x86_64 → link fails; the tablet
  only ever installed mesa, dri-gallium, egl, gbm, gl, gles. Rollback: Alpine r1 APKs were in ~/mesa-r1-rollback on the
  tablet (wiped by the reflash — re-fetch with `apk fetch` before ever touching Mesa again).

## Open / next (Yaron's order of interest; ISSUES.md is authoritative for anything in flight)
1. WATCH: front camera "no more input formats" in Snapshot (2026-09-30; reboot cleared it; not root-caused).
2. DONE (ISSUES 9, kernel r29): "screen wakes / goes black on charger events" = Phosh's normal unblank on a power
   event + the MDP5 enable-order bug (0120).
3. DONE (ISSUES 10): a306 GPU runtime suspend works (kernel r31 0122 + tweaks r34). New ISSUES 11: rare GPU fault
   bursts at GTK4 app start (pre-existing, both runtime-PM modes).
4. CPR fuse-based open-loop voltages (downstream cpr-regulator fuse rows) to run TURBO below 1.35 V.
5. Venus rate control overshoot (~10x under GStreamer), 5 MP stills, hall/jack/A2DP untested, suspend off.
6. OTG write path untested.
7. Upstreaming (memory upstream-ai-policies; Yaron decides/writes where required): kernel 0114 (camss regression) / 0120 (mdp5
   enable order — plain upstream bug, A/B data in display/ab-2026-10-01/) /
   0116 (MUIC CDP) / venus / CPR (coordinate with Stephan Gerhold) with `Assisted-by:`; Mesa 0100 (Yaron writes all
   text); GTK 0102 narrow MR (disclose, no trailers); libcamera 0103/0105/0106/0107 to the list (no policy, disclose,
   DCO); Snapshot 0102 (QrScreenBin double snapshot = plain upstream bug) + sync=false as issues first; phrog 0100 as a
   PR (github samcday/phrog, AGENTS.md, no AI ban); NOTHING to postmarketOS/Nura (forbidden) — the wiki audit is
   Yaron's own work.

## Results worth knowing
- CPU: speed bin 0 → 200…1209.6 MHz (VDD_APC ≤400 MHz 1.05 V, 533–998.4 MHz 1.1625 V, 1094–1209.6 MHz 1.35 V); stress
  0 errors, ≤79 °C, throttles at 75 °C; +21 % single core. KPTI on (kpti=0 not applied).
- Front camera needed 4 fixes: packed UYVY/NV16 never import into EGL on a3xx; NV12 imports only with the implicit
  modifier and widths that are multiples of 64 (a3xx linear pitch = width aligned to 32 texels).
- a3xx textures are ALWAYS linear (tiling only with FD_MESA_DEBUG=ttile); fp16 ALUs only on gen ≥ 5.
- USB OTG: real micro-B OTG cable → auto host; reboot with the boost on is safe; a cable present at boot is picked up
  ~37 s after boot.
- CPU debayer (software_isp mode cpu) rejected by Yaron (+680 mA vs +180 mA).

## Tools (gl-hang/, usb-otg/, display/, gpu-pm/, gtk-fault/)
- gtk-fault/ (2026-10-01): `faulttrace.sh <tag> <cmd…>` exact GPU fault count via ftrace iommu:io_page_fault (+unmap,
  msm submit/shrink/purge) around a command · `faultcatch2.sh <n>` app-launch loop that stops at the first fault ·
  `resizetest.py` (PyGObject GTK4, no cairo) + `relaunch.sh` · `memhog.py` · `leakper.sh` per-app GEM count ·
  `kprobe-leak.sh` kprobes on msm GEM new/open/close/export/vma_get/put/free · `camleak.sh` camera-service GPU memory
  per Snapshot session (fdinfo drm-total-memory). Camera scripts now restore Snapshot's last-camera-id on exit.
- gpu-pm/ (2026-10-01): `vbif.py dump|probe <reg> <val>|halt <c0> <c1> <mask>` a3xx VBIF registers via /dev/mem
  (root; refuses unless the GPU is runtime-active; blank the screen first) · `pmab.sh <secs>` GPU power/control on
  vs auto on an idle screen · `gpustress.sh` runtime-PM stress (rpm_status ftrace counts resumes; gltest hang
  watchdog) · `snapab.sh` / `soak.sh` on-vs-auto A/B · `faultcatch.sh <n>` app-launch loop under ftrace
  (drm_msm_gpu submit/retire/resume/suspend) that freezes the trace + dmesg + GEM list at the first GPU fault burst.
- display/ (2026-10-01): `blanktest.sh <n> [on] [off]` PowerSaveMode cycles → per-unblank fault/vblank/DCS-error deltas
  · `blankgem.sh <n>` + MDP-mapped GEM iovas and plane fb/hwpipe per state · `abrun.sh <tag>` fixed A/B protocol
  after a fresh boot · `bltest.sh` logind SetBrightness while blanked · `fbstate.sh <tag>` DRM debugfs dump.
  Run them as user units: `systemd-run --user --unit=x --collect ~/x.sh …` (nohup over ssh dies with the scope).
- Kernel module fast path (2026-10-01): `kernel/kdev73.sh` in colima (aarch64 native): volume `gt510-kdev` = pristine
  7.3-rc2 + ALL kernel/0*.patch + the tablet's own config (`kernel/running-config-r28` from /proc/config.gz);
  `setup` ~6 min, `msm` ~3 min, `module <dir>`; output kernel/out/*.ko (strip with llvm-strip --strip-debug).
  Install: updates/ + depmod + mkinitfs (msm and the panel are in the initramfs), reboot; check /sys/module/X/srcversion.
Copy them to the tablet's ~ first: the 2026-10-01 reflash wiped them (fronttest, camrate, disprate, aftime, rottest,
snapenv and gltest are back on the device).
- `fronttest.sh <Front|Back>` sensor rate + Snapshot journal · `disprate.sh` GPU jobs/s per process (displayed fps
  with offload) · `camrate.sh <tag>` sensor/delivered/rendered fps · `aftime.sh [runs]` AF time (closes Snapshot
  before restarting the camera service) · `rottest.sh <Front|Back> <transform>…` rotation under a running Snapshot ·
  `snapenv.sh <secs> "<env>"` Snapshot via D-Bus with extra env (service restored) · `gltest.sh <secs> <tag> <app>
  [VAR=val…]` GL app under a hang watchdog (+devcoredump) · `ispshader.sh <variant>…` (shader-test/) ISP GPU ms per
  debayer shader variant via Mesa shader replacement · `ispab.sh` soft-ISP frames GPU vs CPU debayer.
- Test-Mesa era (needs mesa-test/ + ~/mesatest): `mtest.sh`, `fdtest.sh`, `fdperf.sh`, `fdvar.sh`; older:
  flicker.sh, gputime.sh, gpujobs.sh, raspeed.sh/ratest.sh (RetroArch), faultwho.sh, camcombo.sh, grab6.sh,
  camshot.sh, campower.sh, snaptry.sh. `usb-otg/ulpi.py` ULPI viewport + PORTSC via /dev/mem.
- Raw-frame analysis: `cam -c /base/soc@0/cci@1b0c000/i2c-bus@0/camera@28 -s role=raw,width=1296,height=972 -C12
  --file=/tmp/raw-#.bin` with wireplumber@video-capture STOPPED (restart it after); plane offsets by FFT
  cross-correlation (method in libcamera 0105's commit text).

## The device / access
- SM-T550, APQ8016, 1.5 GB RAM, 768x1024 portrait, Adreno 306. adb/fastboot serial **ADB-SERIAL** (the T290
  T290-ADB-SERIAL is often on the same USB — always `-s`). Samsung BL → lk2nd 23.1 on BOOT → pmOS on `userdata`; lk2nd
  loads the FLAT `/boot/msm8916-samsung-gt510.dtb`.
- `./gssh '<cmd>'`: USB network 172.16.42.1 (cable on the Mac's CDP port) else Wi-Fi **TABLET-WIFI-IP** (since the
  2026-10-01 reflash; a new install gets a new lease). Key `~/.ssh/ssh-key`; user `user` / **<password>**; sudo via
  `echo "${SUDO_PW:-147147}" | sudo -S -p ''`. scp sometimes drops — `./gssh 'cat > /tmp/x' < file` works. ssh sometimes hangs AFTER
  the remote command finished — write results to files on the device and read them back.
- Boot session is auto-logged-in and unlocked. Unblank: `gdbus … DisplayConfig … PowerSaveMode "<0>"` (a blanked screen
  = an unmapped Snapshot = no stream, sensor 0/s). Screenshots: `sudo ffmpeg -device /dev/dri/card0 -f kmsgrab -i -
  -vf hwdownload,format=bgr0 -frames:v 1 x.png`. ssh-launched GUI apps die with the ssh scope — `systemd-run --user`
  or `gapplication launch org.gnome.Snapshot`.
- lk2nd fastboot from SSH: `sudo python3 -c "import ctypes; ctypes.CDLL(None).syscall(142,0xfee1dead,672274793,
  0xA1B2C3D4,ctypes.c_char_p(b'bootloader'))"` (the ssh then hangs — kill it by PID before running fastboot).
- Flash: `fastboot -s ADB-SERIAL -S 64M flash userdata dist/qcom-msm8916-2026-10-01-r33.simg` (49 chunks,
  6.5 min), `fastboot -s … reboot`; first boot ~70 s + resize to 10.4 GB. Before a flash: back up ~ (minus .cache) and
  /etc/NetworkManager/system-connections (backup-2026-10-01/ has the last one); after: restore the NM profile over
  USB networking, Pictures/Videos (pack with COPYFILE_DISABLE=1 on the Mac), dconf + RetroArch come back from the SD
  card by themselves (gt510-persist). The camera permission is pre-granted (r33).

## Build pipeline — Yaron's laptop builder (since 2026-09-30)
- Host `builder@BUILDER-HOST` (ThinkPad, Manjaro, x86_64, 12 threads, 16 GB RAM, key login, `sudo -n docker` ONLY — any
  other host sudo goes through Yaron, e.g. `sudo modprobe loop`). SHARED with the T290 Lineage builds
  (`lineage-build*`, ~12 GB RAM): `build-host/gt510-queue.sh "<name>:<target…>"…` waits before EVERY job until no
  gt510-* and no lineage-build* container runs; logs `~/gt510-pmos/logs/<name>.log`, progress `logs/queue.out`.
  Run it under `nohup systemd-inhibit --what=sleep:idle --who=gt510 …` — the laptop SLEEPS when idle (the queue's
  inhibitor ends with the queue). Yaron may ask for a session-long keep-awake (`--who=gt510-session`); release it
  when done (kill the PID from `systemd-inhibit --list`).
- Tree `~/gt510-pmos` = rsync of pmos-gt510.sh, .password, pubkeys, packages/, kernel/{0*.patch,gt510.config,
  apply-7.3.sh}, build-host/ (rsync replaces files by rename: safe while a job runs). Image `gt510-pmos`
  (build-host/Dockerfile = debian:trixie-slim + pmbootstrap), volume `gt510-pmos-vol`, outputs `~/gt510-pmos/dist/`.
  Signing key = the colima one (pmos@local-6ab5310e, trusted by the tablet) in /work/pmb/config_abuild AND its .pub in
  /work/pmb/config_apk_keys (mixed keys → "UNTRUSTED signature" at index time → wipe /work/pmb/packages + chroots).
- Targets: `localpkgs-only <pkg>` (pmaports reset to git + only that local package copied in, deps from the binary
  repos — USE THIS; build Rust/crossdirect packages ONE per job, the 3rd package in one job failed at chroot init),
  `localpkgs <pkgs>` (exposes all local packages; pmbootstrap 3 then rebuilds every outdated LOCAL dependency without
  checksums → fails; `build -i` does not prevent it), `kernel73` (bump pkgrel in kernel/apply-7.3.sh + the APK name in
  pmos-gt510.sh; cross-native clang; 53 min cold), `install` (zap + rootfs + image; needs the host `loop` module —
  Manjaro has it as a module, Yaron loaded it 2026-10-01; ~5.5 min), `lk2nd` (aarch64 buildroot), `simg` (img2simg →
  dist/qcom-msm8916.simg + sha256). Fresh image = `"install:install" "simg:simg"` (lk2nd only if BOOT changes).
  Build times: libcamera ~3-6 min, snapshot ~30 min, greetd-phrog ~30 min, gtk4.0 ~19 min, mesa (slim) ~9 min,
  tweaks ~30 s. Laptop repo holds every local package (2026-10-01).
- Verify an image without mounting it: read /work/pmb/chroot_rootfs_qcom-msm8916/lib/apk/db/installed and the
  /etc/systemd/{system,user}/*.wants links in the volume.
- Colima (OLD, Mac, profile t290): was FULL 2026-09-30; 24.8 GB free on 2026-10-01 19:00. gt510 chroots + apk cache
  deleted there; volumes gt510-pmos-vol (has the kernel tarball) + gt510-mesa-vol + gt510-kdev (module dev tree) exist.
  Packages/images still on the laptop; colima only for the kdev73.sh module fast path.

## Traps (don't repeat)
- `apk add -u <local .apk>` also UPGRADES the package's edge dependencies from the repos (partial upgrade): on
  2026-10-03 it purged device-mapper-udev and mkinitfs then failed (`10-dm.rules` missing; the old initramfs stays).
  Install local APKs with plain `apk add <file>`; if mkinitfs breaks: `apk add device-mapper-udev && apk fix`.
- pmOS presets every NEW unit AFTER post-install (99-default: disable *) → `systemctl [--global] enable` in post-install
  is undone on a fresh image. Ship presets: user `/usr/lib/systemd/user-preset/80-gt510.preset` (template syntax
  `enable wireplumber@.service video-capture`), system `/usr/lib/systemd/system-preset/80-gt510.preset`. Check with
  `systemctl [--global] preset <unit>`. Upgrades never show this — only a fresh flash does.
- Never restart wireplumber@video-capture while a Snapshot is open (stream dies, "target not found", camerabin can't
  recover — looked like "rotation killed the preview"). Every test script's trap must close Snapshot first.
- pmbootstrap's APKBUILD parser ignores `case $CARCH` blocks → makedepends/subpackages inside them don't exist for it;
  crossdirect builds Rust for x86_64 inside meson (Mesa NAK link: "Relocations in generic ELF (EM: 62)").
- `./gssh 'echo "${SUDO_PW:-147147}" | sudo -S tee FILE' < local` writes an EMPTY file (sudo eats the pipe) — copy to /tmp, `sudo cp`.
- `pkill -f <pattern>` over ssh kills its own ssh shell when the pattern is in the command line — kill by PID; a
  killed queue shell leaves its running `docker run` job alive (and SIGTERM to a waiting sh can still start the next
  job — use SIGKILL).
- macOS tar adds AppleDouble `._*` files — `COPYFILE_DISABLE=1 tar …`.
- A GPU hang can make phoc segfault while re-creating its renderer → the whole session dies. (The Mesa fix makes
  hang tests rare now; still never on the live session if avoidable.)
- `grep -c fault` in dmesg matches "default" — grep "context fault|hangcheck|\*\*\* fault|msm_gpu_fault".
- ffmpeg `blackframe` is wrong for limited-range black — use signalstats YAVG < 20.
- Files written by root under /tmp shadow later user-shell redirects — write to $HOME.
- zsh: no word-split of `$var` in `for` (use `${=pk}`); `echo =====` is `=` expansion; `{ diff …; } > f && mv` never
  moves (diff exits 1 — end with `true`); foreground `sleep` is blocked in the harness — use Monitor/background jobs.
- pmbootstrap installs local APKs with `apk add -u`; gnome-settings-daemon-mobile provides 999948.0 → tweaks keeps
  `gnome-settings-daemon<999`.
- Never set Phosh lockscreen keys without a `:Phrog` counterpart (the greeter reads the same schemas); gschema
  `[schema:Phosh]` sections beat plain overrides; ssh `gsettings get` lacks XDG_CURRENT_DESKTOP (test with
  `XDG_CONFIG_HOME=$(mktemp -d) XDG_CURRENT_DESKTOP=Phosh:GNOME gsettings get …`).
- Audio server is PulseAudio (`pactl`); wpctl shows no audio sinks (normal). Sound card appears ~60 s after boot.
- Snapshot opens the camera in gsettings org.gnome.Snapshot last-camera-id, not wpctl's default. Launch it for tests
  with `gapplication launch org.gnome.Snapshot`; change its env by editing the D-Bus service Exec and ALWAYS restore.
- A direct `cam` run while the camera service is up can wedge negotiation — stop wireplumber@video-capture first.
- `gst-launch pipewiresrc target-object=… ! fakesink` without video caps never links; an unlinkable target silently
  falls back to the DEFAULT source.
- `msm_gpu_fault_handler: N callbacks suppressed` = N more faults, not lines. a3xx msm_gpu_submit_retired gap timing
  is only valid while the GPU is saturated (useless once offload made it idle — use disprate.sh).
- Monitors started right after `> log` read the PREVIOUS log first.
- Kernel 0119 lesson: A/B any "garbled" camera frame against a known-good kernel before calling it a scene.
- Never mount a built image's rootfs without `e2fsck -f` afterwards (first-boot resize2fs refuses).
- macOS fastboot can die mid-flash (`usb_read failed … e00002ed`) — always `-S 64M`; recover lk2nd with
  Power+VolDown, keep VolDown.
- `cam -c1` index flips — select by path. `LIBCAMERA_LOG_LEVELS`: `*:WARN` FIRST.
- GitHub raw is rate-limited — `gh api -H "Accept: application/vnd.github.raw" …`; no full kernel `git fetch`
  (Yaron rejected it). crates.io needs a User-Agent (403) — fetch crate sources from gitlab tags instead.
- venus enc/dec /dev/videoN swap between boots — `v4l2-ctl -D`.
- Tablet busybox has no `time` and no `date +%N`; the Mac has no `timeout` command.
