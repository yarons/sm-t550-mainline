# gt510 open issues — worked top to bottom (one at a time)

Status: OPEN / ACTIVE / DONE (with evidence). Details live in CONTINUATION-PROMPT.md; this file is the order.

1. DONE (Yaron confirmed 2026-10-01: rotation works) — "Rotation killed the rear preview" (2026-10-01 ~10:00). Cause: MY
   gl-hang/aftime.sh exit trap restarted wireplumber@video-capture while the Snapshot it launched was still open →
   "target not found" 09:58:24 → camerabin could not restart; the rotation happened at the same time. Rotation
   itself verified OK: gl-hang/rottest.sh (wlr-randr --transform normal/270 under a running Snapshot, rear):
   sensor 28/s throughout, preview on screen both ways. Fix: aftime.sh trap kills Snapshot first.
   TRAP for every script: never restart the camera service under an open Snapshot.
2. DONE (Yaron: "pretty fast") — **Autofocus slow**: 6.8 s → 1.9 s stream-start-to-"Focused at" (aftime.sh, 3 runs,
   lens 279-280; scan ≈ 1.1 s = 7 coarse + 3 fine steps × 3 frames). libcamera r109 + tweaks r29 INSTALLED
   2026-10-01 10:05. Faster options if wanted: settle 1, stopRatio 0.8 (risk: blurred/noisy measures).
3. DONE — **Mesa workarounds gone** (2026-10-01 10:55): mesa r101 + tweaks r30 + snapshot r112 INSTALLED.
   Verified without workarounds: 10 GTK apps × 25 s 0 hangs/0 faults, calculator 90 s, Snapshot 0/73 black frames;
   Snapshot env now only GSK_RENDERER=gl, rates sensor 29 / ISP 24.8 / phoc 22 per s. User manager env cleared with
   `systemctl --user unset-environment`; phosh keeps the old vars until the next log-out/reboot (harmless).
   Rollback: ~/mesa-r1-rollback/*.apk on the tablet (+ tweaks r29 / snapshot r111 in dist/laptop).
4. DONE — sqrt gamma DECLINED (Yaron: "the colors look great"): gamma stays 2.2.
5. WATCH (Yaron ok) — Front camera "no more input formats" (cleared by reboot 2026-09-30; not root-caused).
6. DONE (2026-10-01 11:47) — Laptop repo complete: greetd-phrog r100 + gtk4.0 r103 built as SEPARATE jobs (the
   multi-package `rest` job failed at chroot init for the 3rd package: `ln -s …ld-musl-x86_64.so.1` exists — build
   Rust/crossdirect packages one per job). Laptop repo now: libcamera r109, gt510-tweaks r30, snapshot r112, mesa
   r101, gpsd r101, phosh r100, greetd-phrog r100, gtk4.0 r103, kernel r28 → an `install`/image build can run there.
7. DONE (ongoing rule) — docs updated after each item (CONTINUATION-PROMPT.md + memory).
8. DONE (2026-10-01 15:47) — First Snapshot after boot opened the FRONT camera (last-camera-id=Back): the camera
   service is WantedBy=pipewire.service and pipewire was only socket-activated → it started with Snapshot itself
   (3.5 min after boot), cameras appeared ~3 s too late. tweaks r31 enables pipewire.service at login
   (post-install/upgrade + 80-gt510.preset). Verified after reboot: camera service up 20 s after boot, cameras
   enumerated at +24 s, first Snapshot opened the rear camera (28/s), 0 GPU faults on the new Mesa.
9. DONE (2026-10-01 19:40) — **Display faults at every DPMS on** (was "screen wakes / goes black on MUIC charger
   events": the charger event only triggers Phosh's unblank). display/blanktest.sh: 8/10 PowerSaveMode 3→0
   transitions logged "Unhandled context fault" (iova 0x302000/0x602000 = start of a 3 MB phoc buffer) + INTF1
   underrun (mdp5 errors 0x04000000) + often "vblank time out"; Snapshot open/closed irrelevant.
   display/blankgem.sh: the faulting iova = the buffer scanned out BEFORE the blank, which phoc frees at the unblank.
   Cause: mdp5_vid_encoder_enable() set TIMING_ENGINE_EN before the CTL flush → first frame used the pre-disable
   pipe state (DPU flushes first). FIX kernel/0120 (flush, then enable) + 0121 (s6d7aa0: no backlight DCS write
   while the panel is disabled; Phosh/logind wrote brightness with the DSI link down → -22/EPROTO).
   A/B (display/abrun.sh, results display/ab-2026-10-01/): stock 37 faults / 2 vblank timeouts / 9 underruns,
   fixed 0/0/0; every stock boot logs the boot-time underrun, fixed boots none; phoc stays double-buffered with the
   fix (3 buffers on stock = the stalled flip). logind SetBrightness while off: OK.
   INSTALLED: kernel r29 (#30, laptop build 2 min with warm ccache; APK sha256 8132eb5c…) — r29 msm.ko disassembly
   shows mdp5_ctl_commit before the TIMING_ENGINE_EN write (r28: after); updates/ emptied, tainted=0; after reboot
   no boot underrun, blanktest 10/10 clean. Test modules kept in ~/kmod-test/off on the tablet (not loaded).
10. DONE (2026-10-01 20:50) — **a306 GPU never runtime-suspended** (tweaks forced power/control=on since 2026-09-25:
   every suspend failed and was retried every 66 ms in kworkers). Cause: upstream be0e82b8e0c9 (2026-07, "drm/msm/
   a3xx: Drain VBIF before GPU suspend", for a320) waits for SIX VBIF XIN halt acks; a306 has THREE. Measured with
   gpu-pm/vbif.py (/dev/mem, blanked): 0x3f → HALT_CTRL0 reads 0x7, HALT_CTRL1 = 0x00070007 at once; kgsl's "VBIF2"
   offsets (0x3081/0x3082) do NOT ack here. Our fix = Sam Day's upstream patch (posted 2026-09-26, Reviewed-by Konrad,
   patchwork 756513) → kernel/0122 now carries HIS patch verbatim (ours in attic/kernel/).
   INSTALLED: kernel r31 (#32) + gt510-tweaks r34 (udev rule 62-gt510-gpu-runtime-pm.rules dropped → attic/,
   depends kernel>=r30). Boot: control=auto, GPU suspended ~82 % of idle uptime, sys CPU 1 %.
   Tests: pmab.sh idle 100 % suspended; gpustress.sh 72 (test module) + 123 (r30) cycles; soak.sh on r31 3× on /
   3× auto: 48/48 GTK runs OK, glmark2 81-82 both modes, 372 suspend/resume cycles, 0 hangs; resume 0.19 ms avg.
   Upstream: Tested-by draft upstream/tested-by-756513.txt (Yaron sends).
11. DONE (2026-10-01 23:10, kernel r32) — **GPU iommu fault storms at GTK4 app start/exit** (pre-existing; seen once per
   20-60 app launches; up to ~50k faults per burst; no hang). ROOT CAUSE (kernel, upstream regression 111fdd2198e6
   "drm/msm: drm_gpuvm conversion", 2025-07): a2xx-a5xx have no per-process pagetables, so every DRM file shares the
   GPU's ONE global VM; msm_gem_close() tears down the BO's mapping in that VM on ANY handle close. A client's window
   buffer is shared with phoc (dma-buf self-import = same GEM object); when the client drops it (first resize at
   start-up, or exit), phoc's next composite reads the torn-down iova (Mesa caches iovas; kernel ignores `presumed`,
   no relocs) → READ faults on rows of a 768-px RGBA buffer (GMEM restore of a 192x160 bin column).
   Evidence: gtk-fault/catch2/ (ftrace iommu:unmap + io_page_fault: a 2.5 MB window buffer unmapped by the exiting
   snapshot process while the GPU read it; the same range unmapped by kgx/nautilus/snapshot then phoc all run long);
   gtk-fault/resizetest.py + relaunch.sh (plain GTK4: 0 faults — needs the phoc-shared buffer churn).
   FIX = Dmitry Baryshkov's upstream series 172617 (2026-08-22, New): 0123 locking put_iova_spaces() wrapper + 0124
   no shared-VM teardown on handle close (teardown at the last vma_ref drop). Kernel r32 INSTALLED: gtk-fault/
   faultcatch2.sh 180 launches → 0 faults (r31: caught after 20 and 57). kprobe GEM lifetime check (gtk-fault/
   kprobe-leak.sh): no BO kept alive by the patch. Upstream: Tested-by draft upstream/tested-by-172617.txt.
12. DONE (2026-10-03 14:45, libcamera r110) — **camera service leaked ~8.1 MB GPU memory per Snapshot session**.
   Cause (libcamera, fixed upstream 2026-08-17 by a00a4ca2 + 4501b8a1, after our v0.7.2): DebayerEGL::start() calls
   eGL::initEGLContext() on every stream start, which created a NEW EGL context and overwrote the old one; only the
   last was ever destroyed → one leaked context (Mesa per-context BOs, shader variants from the ir3q0 thread) per
   session in the long-lived wireplumber@video-capture. FIX packages/libcamera/0108-egl-avoid-context-leaks.patch:
   eGL::resetEGLContext() called from DebayerEGL::stop(), double init refused (upstream's substance, ported without
   their EGL refactor series). gtk-fault/camleak.sh: r109 +8332 KiB/session (8436 → 16768 → 25100), r110 flat 4548 KiB
   over 4 sessions, RSS steady; rear camera 28/s in back-to-back sessions, new context logged each start, no errors.
   SIDE EFFECT while installing (fixed): `apk add -u <local apks>` upgraded libcamera's edge dependencies
   (device-mapper-libs r7→r8, util-linux libs, ffmpeg-libavutil) and PURGED device-mapper-udev → mkinitfs aborted
   ("failed to stat /usr/lib/udev/rules.d/10-dm.rules", /boot/initramfs left untouched). `apk add device-mapper-udev`
   (r8) + `apk fix` → OK, initramfs rebuilt. Use plain `apk add <file>` for local packages from now on.
13. ACTIVE (2026-10-03 15:40) — **Idle battery drain** (Yaron: "did you test discharge?"). Logged discharge on the public
   image (upower history): 98 → 66 % in 20 h with the screen off = 1.6 %/h (~62 h from full). power/powertest.sh
   (root, self-running on battery, gauge current_now, screen off): baseline 177 mA, Wi-Fi radio off 161 (Wi-Fi
   ~16 mA), modem DSP stopped 169 (~8 mA), baseline again 179, screen on 849 mA (power/powertest-2026-10-03.txt).
   BIGGEST FIND: after camera use the rear lens actuator (DW9804, /dev/v4l-subdev11) stayed powered at
   focus_absolute 1023 (AF sweep end) because libcamera keeps the lens subdevice open: 210 mA idle → 84 mA after
   `v4l2-ctl -c focus_absolute=0`. FIX libcamera 0109 (r111): SimplePipelineHandler::stopDevice() parks the lens at
   the control minimum. Verified: AF moves the lens during streams (493, 837), parked at 0 after every close, idle
   75 mA (SSH session open), rear camera 27-28/s. Next levers: Wi-Fi BMPS (5 "Can not enter BMPS" errors per boot,
   ~16 mA total for the radio), modem DSP (~8 mA, needed for audio), system suspend (none; biggest remaining).
   Remember: install local APKs with plain `apk add` (item 12 trap). Tablet Wi-Fi IP is T290-WIFI-IP now (gssh).
