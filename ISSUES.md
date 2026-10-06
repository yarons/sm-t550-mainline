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
13. DONE (2026-10-04 13:10, Yaron: keep suspend) — **Idle battery drain** (Yaron: "did you test discharge?"). Logged discharge on the public
   image (upower history): 98 → 66 % in 20 h with the screen off = 1.6 %/h (~62 h from full). power/powertest.sh
   (root, self-running on battery, gauge current_now, screen off): baseline 177 mA, Wi-Fi radio off 161 (Wi-Fi
   ~16 mA), modem DSP stopped 169 (~8 mA), baseline again 179, screen on 849 mA (power/powertest-2026-10-03.txt).
   BIGGEST FIND: after camera use the rear lens actuator (DW9804, /dev/v4l-subdev11) stayed powered at
   focus_absolute 1023 (AF sweep end) because libcamera keeps the lens subdevice open: 210 mA idle → 84 mA after
   `v4l2-ctl -c focus_absolute=0`. FIX libcamera 0109 (r111): SimplePipelineHandler::stopDevice() parks the lens at
   the control minimum. Verified: AF moves the lens during streams (493, 837), parked at 0 after every close, idle
   75 mA (SSH session open), rear camera 27-28/s. Next levers: Wi-Fi BMPS (5 "Can not enter BMPS" errors per boot,
   ~16 mA total for the radio), modem DSP (~8 mA, needed for audio), system suspend (none; biggest remaining).
   Remember: install local APKs with plain `apk add` (item 12 trap).
   2026-10-03 later: deep idle is out of reach (qcom_stats vmin/xosd Count 0; cpuidle driver qcom_spm = per-core
   states only; cluster/SoC states need PSCI firmware Samsung's signed TZ lacks) → floor ~75 mA. Trying s2idle:
   kernel r33 (CONFIG_SUSPEND=y in kernel/gt510.config) INSTALLED, plugged 30 s test resumed fine (woke early,
   10.5 s, non-RTC source). IN FLIGHT: root unit `suspendab` (power/suspendtest.sh: suspend 900 s with per-wake
   source logging, then idle 900 s; coulomb counter) → ~/suspendtest.out. Tablet Wi-Fi is TABLET-WIFI-IP (./gw).
   2026-10-03 22:15: that run NEVER STARTED — the cable was still in (Mac USB) and at 100 % the gauge says "Full", not
   "Discharging". Instead logind suspended at 21:56:15 on "Lid closed" (hall sensor, "Lid opened" the same second;
   HandleLidSwitch=suspend applies on AC too) → 17 min s2idle, power key woke it (Wi-Fi back ~1 min later, wcn36xx
   hal_join/config_bss -5 errors, then reconnected). Side finds: the HALL SENSOR WORKS; the screen-on suspend broke
   display blanking → item 14. Harness fixed: power/suspendab.sh waits for charger online=0 and holds a logind
   sleep:idle:handle-lid-switch block inhibitor (GNOME would suspend the 15-min idle phase). Re-armed after a reboot
   (22:19), waiting for the unplug.
14. DONE (2026-10-03 23:31, kernel r34/0125) — **Screen can't turn off after a suspend with the panel lit** (found via item 13's lid
   suspend). After resume: `WARNING … mdp5_pipe.c:138 mdp5_pipe_release` + phoc "Atomic commit failed: Invalid
   argument"; every later DPMS off fails ("Failed to commit power mode change", CRTC stays active, backlight on)
   until reboot. Cause (upstream mdp5, no fix in torvalds or msm-next; patchwork search blocked by Anubis):
   drm_atomic_helper_suspend()'s snapshot keeps the planes' hwpipe pointers but not the mdp5 global private state; the
   suspend commit releases the pipes; resume restores plane-0 on DMA0 with the pipe unowned; the next release WARNs →
   -EINVAL. Suspends with the screen already blank (GNOME idle path, our RTC test) are unaffected. FIX kernel/0125
   (mdp5_plane_atomic_check: a plane that is not visible in the current state owns no hwpipe → drop any restored one
   and assign afresh). Evidence: power/dmesg-r33-lidsuspend.txt.
   VERIFIED on kernel r34 (#35, built 3 min on the laptop, APK sha256 c34c0540…, INSTALLED 22:33 with plain `apk add`):
   power/stalepipe.sh (lit → s2idle, RTC +10 s → resume → PowerSaveMode 3 → state): r34 3/3 cycles CRTC inactive
   when blanked, plane released, 0 WARN, 0 phoc failures; s2wake lit + 2 hand blank/unblank cycles clean. r33: WARN +
   "Failed to commit power mode change", backlight stuck on (22:17).
   SIDE ISSUE — 2 SPONTANEOUS RESETS during a lit s2idle (tablet reboots by itself ~2.5 min after suspend entry; no
   log: watchdog0 = PM8916 PON WDT inactive, journal stops before the freeze; pstore ramoops at 0xdc000000 added to the
   INSTALLED dtb by fdtput (backup /boot/msm8916-samsung-gt510.dtb.orig-r34, dtc installed) — the bootloader zeroes
   that RAM on reset, so nothing survives; Samsung's preserved log region unknown). (1) 22:21 r33, stalepipe cycle 1,
   fresh boot; (2) 23:13 r34, stalepipe cycle 1 but with console_suspend=N + loglevel 7 set by me (printing to the
   suspended msm UART = classic hang; never do that again). Since then on r34, defaults: s2wake blank 10 s OK, lit 60 s
   OK, lit 10 s OK, stalepipe 3/3 OK, 20-cycle stalepipe soak 20/20 (23:23-23:31): 26 suspends, 0 fail, 0 GPU faults/
   underruns/WARN, untainted, Wi-Fi held on 5 GHz. Unexplained: (1) — maybe the stale pipe scanning without SMP blocks
   on r33 (0125 removes that), unproven. Power A/B re-armed 23:31, never started (cable stayed in until 00:47) → DISARMED (it would blank + re-suspend
   the tablet for 15 min under a user). Re-arm only when Yaron is about to unplug and leave it.
   RESULT 2026-10-04 07:35-08:06 (unplugged, 99 %, screen off, power/suspendab.sh): s2idle 900 s (one clean cycle,
   RTC wake at 901 s) avg 63 mA vs awake idle 900 s avg 78 mA (coulomb counter; charge_now 67 vs 82) → -15 mA (-19 %),
   ~95 h vs ~77 h standby. DECISION (Yaron 2026-10-04): KEEP CONFIG_SUSPEND (kernel r33+). Remaining levers: Wi-Fi BMPS
   (works with the stock NV, item 15), modem DSP ~8 mA (audio).
15. DONE (2026-10-04 13:13, kernel r35) — **Wi-Fi never works on 2.4 GHz** (Yaron: "enter the wifi password over and over"). Journal
   since 09-26: 2.4 GHz BSSID AP-2G-BSSID (ch 9) 0/37 joins, 5 GHz 8e:1f (ch 44) 16/16. Every 2.4 GHz try:
   wcn36xx "hal_join response failed err=-5" + "hal_config_bss … failed" → CTRL-EVENT-BEACON-LOSS during the 4-way
   handshake → wpa_supplicant "WRONG_KEY" → after 3 NM asks for the password. Trigger: a beacon loss on 5 GHz makes
   it roam to 2.4 GHz; today's many suspends/reboots made it frequent. Not r34 (same on r32/r33 boots). MITIGATION
   (Yaron OK'd): `nmcli con modify "HOME-WIFI" 802-11-wireless.band a` → connected on 5 GHz. Lead: the NV
   calibration in use is the DragonBoard 410c one (/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin from
   firmware-qcom-db410c-wcnss-nv) — the tablet's own NV may still be on the stock system/persist partitions (read-only
   look first; never write those partitions). Also: BMPS enter/exit errors (err 5) at every connect (item 13 lever).
   2026-10-04: ROOT CAUSE = HT40 in 2.4 GHz, not the NV. The 2.4 GHz AP runs HT40 on ch 9 with the secondary ABOVE
   (= ch 13), plus VHT/HE. wifi/ht20test.sh (private wpa_supplicant, NM unmanaged ~45 s, self-restoring) A/B against
   that BSSID: disable_ht40=1 → connected, keys negotiated, no beacon loss; disable_ht40=0 → 0/3, 3× beacon loss +
   "4-Way Handshake failed" + WRONG_KEY, hal_join 3 / config_bss 6. Stock prima config (WCNSS_qcom_cfg.ini) has
   gChannelBondingMode24GHz=0. FIX kernel/0126 (wcn36xx: 2.4 GHz ht_cap without SUP_WIDTH_20_40/SGI_40/DSSSCCK40);
   r35 = r34 + 0126 (laptop asleep → test module via kernel/kdev-wcn36xx.sh in colima t290 with running-config-r34,
   test with wifi/modtest.sh, self-reverting). The 5 GHz lock stays until Yaron decides.
   VERIFIED 13:02 (test module, vermagic 7.3.0-rc2-msm8916, taint E+O): 2.4 GHz caps now HT20 only; NM joined the
   2.4 GHz BSSID first try, 0 hal_join / 0 config_bss / 0 WRONG_KEY / 0 beacon loss, HT20 rx 65 Mbit/s MCS 6 SGI,
   ping gw 10/10 avg 11 ms; back on the 5 GHz lock after. TEST MODULE LEFT INSTALLED:
   /lib/modules/7.3.0-rc2-msm8916/updates/wcn36xx.ko (shadows the packaged one, survives reboots) → DELETE it +
   depmod when r35 is installed, else r35's own module never loads. r35 not built yet (laptop asleep).
   r35 (#36, laptop build 2 min, APK sha256 6676ffa3…, pmb log shows 0125+0126 applied) INSTALLED 13:10; test module
   deleted + depmod; ramoops dtb node gone (boot-deploy rewrote the dtb), .orig-r34 backup + dtc removed. After reboot:
   untainted, boot 26.9 s, 2.4 GHz caps 0x803c (HT20 only), 0 hal_join / 0 BMPS errors, power save on; NM 2.4 GHz join
   with the packaged module: connected, HT20 MCS 7 72 Mbit/s rx, ping 10/10, back on the 5 GHz lock. The lock stays
   (Yaron didn't ask to remove it; 5 GHz is faster). NV packaging DONE (Yaron OK'd): gt510-tweaks r36
   gt510-wcnss-nv copies it once from the stock system partition (early path before WCNSS boot verified by a reboot
   with the file removed; late path restarts WCNSS). Pushed to the public repo as ea60f0b (Samsung files excluded).
   STOCK NV: found on the stock system partition (mmcblk0p25, T550XXU1CQL5, mounted ro,noload then unmounted) →
   wifi/stock-T550XXU1CQL5/ (local only: proprietary, never in the public repo). wifi/nvtest.sh: it loads (atime) and
   5 GHz works with 0 hal_join and 0 BMPS errors (db410c NV: BMPS failed at every connect = power save never on);
   2.4 GHz still failed with it. HAND-INSTALLED on the tablet: /lib/firmware/updates/wlan/prima/WCNSS_qcom_wlan_nv.bin
   (stock NV; remove to go back). Power save on with it: 24/24 pings, ~45 ms RTT. WATCH: 08:15-09:57 the tablet was
   unreachable over Wi-Fi while NM stayed connected (DHCP renew 09:12 worked) — cause unknown (BMPS? scan?).
   Archived pmaports firmware-samsung-gt510-wcnss-nv (pastebin base64) sha512 matches none of the stock file's base64
   encodings (format unknown).
16. DONE (2026-10-05 10:30, Yaron: rebuild on 26.2.4) — **Mesa 26.2.4** (Alpine moved past 26.2.3; tweaks pins held the
   local 26.2.3-r101). packages/mesa 26.2.4-r100 = Alpine 26.2.4-r0 (only pkgver + tarball hash changed; its three
   patches byte-identical) + 0100 unchanged (upstream 26.2.3..26.2.4: 107 commits, none in 0100's three files; ir3
   got "Lower quad votes" + "const global offset unsigned"). gt510-tweaks r37 moves the pins (mesa>=26.2.4-r100,
   mesa-dri-gallium<26.2.5). Laptop build 16 min (slim), all 4 patches applied.
   A/B (gl-hang/mesasoak.sh: 10 GTK apps × 25 s + calculator 90 s under gltest.sh, Snapshot black frames, glmark2
   subset, GPU fault count; gl-hang/kgxloop.sh; evidence gl-hang/mesa2624-ab-2026-10-04.txt):
   r101 54 runs 0 hangs, glmark2 101-103 (a first 42 was an outlier); 26.2.4 108 runs 1 hang (kgx 3 s after start,
   hangcheck recovered, session survived, devcoredump gl-hang/gpucrash-m2624-kgx.bin), glmark2 100-107, 0 GPU faults,
   0 black frames in portrait. Rule agreed with Yaron: r101 clean → 54 more on 26.2.4 → clean → PASS. One run showed
   40/40 black frames = test artifact (tablet in landscape, Snapshot on the front camera; portrait recheck 0/36, 0/37).
   INSTALLED on the tablet (rollback APKs ~/mesa-r101-rollback/ + dist/mesa-r101-rollback/). WATCH: the kgx start hang.
17. DONE (2026-10-05, Yaron asked: what would a device-specific kernel change) — **boot-parameter A/B: kpti=0 and no
   serial console** (power/kptiab.sh, results power/kptiab-2026-10-05.txt). KPTI is "forced ON by KASLR" on these
   A53s (not Meltdown-affected). A (default) vs B1 (kpti=0) vs B2 (kpti=0 console=tty0; lk2nd's DT stdout-path keeps
   ttyMSM0 as a console unless console= is given): perf bench syscall basic 0.467 → 0.409 µs/op (-12.5 %), sched
   pipe / messaging within noise, system CPU while streaming the rear camera 26.1 / 24.5 / 25.8 % (noise), glmark2
   102, stability pass 11/11 OK. No user-visible gain → REVERTED to the default (KPTI on, serial console) on Yaron's
   tablet; not worth weakening KASLR. Other findings from the config review (not changed): KVM=y is useless (EL1
   boot), ~546 of ~630 modules unused (disk/build only), DWARF5+BTF debug info costs build time only; ftrace/kprobes/
   debugfs/devmem stay (our tooling).
18. DONE (2026-10-05, kernel r36) — **Wake from suspend with Home / cover** (Yaron's #1 after the hardware review). Only
   the PMIC power key woke the tablet: the gpio-keys Home button and the gpio-keys hall switch (SW_LID) had no
   wakeup-source (downstream DT: home_key gpio-key,wakeup; hall via Samsung's flip-cover driver). kernel/0127 adds
   wakeup-source to both from msm8916-samsung-gt510.dts (path references; the nodes live in gt5-common.dtsi).
   Verified first with fdtput on the installed DTB, then r36 (#37): gpio-keys + gpio-hall-sensor power/wakeup=enabled;
   Home woke the tablet from s2idle (16:56:19 → 16:56:31, gpio-keys event_count 2, screen on). Cover path untested:
   Yaron's cover is not magnetic (the 2026-10-03 21:56 "Lid closed" suspend was some other magnet nearby).
19. DONE (2026-10-05, kernel r37 installed) — **Microphone: 16 kHz tone** (Yaron chose root cause over a filter). The
   primary mic (Mic1 = AMIC1, MIC BIAS External1) works — a 1 kHz speaker beep lifted the band 30 dB — but every
   capture carried a ~16 kHz tone at -11 dBFS (ADC1 gain 8): crest 1.45, zero-crossing rate 0.66, frequency wandering
   15.91-16.08 kHz (not locked to the 48 kHz clock), level following ADC1 gain exactly (12 dB per 4 steps), absent on
   ADC2/ADC3/ZERO/DMIC, unchanged with the screen off. Rejected: display/backlight, L13 (mic-bias LDO) or S4 (codec
   CP/PX buck, 770 mA like downstream) forced to high-power mode. ROOT CAUSE: CDC_A_MICB_1_INT_RBIAS (0xf143) keeps
   its power-on 0x49 = TX1N/TX2N/TX3N internally pulled up to MIC BIAS, so bias-rail noise is captured differentially;
   mainline's PM8950/PM8953 sequences write 0x00, the PM8916 one doesn't; Samsung's msm8x16-wcd writes 0x00
   (CONFIG_SAMSUNG_JACK). Runtime test (kernel/cdcpoke test module, mask 0x49 -> 0): tone band -17.4 -> -75.3 dB
   (-58 dB), loopback beep still +34 dB. FIX kernel/0128 (PM8916 sequence writes MICB_1_INT_RBIAS 0x00; MBHC/DAPM set
   bit 4 for the headset mic later). Upstream candidate. Tools: audio/ (downstream sources, register dumps), the
   tablet's ~/{micloop2,mictone,micband,micfmt,tonemeas}.sh + goertzel.py/tonetrack.py (analysis in RAM only).
   VERIFIED on r37 (#38, laptop build 3 min) without poking: f143 = 0x10 after boot, tone band -77.1 dB (r36 -17.4),
   rest -62 dB, loopback beep +36 dB, untainted. Secondary mic (AMIC3) and headset mic untested.
20. CLOSED (2026-10-05, hardware) — **Vibration motor does not move.** Software path verified against Samsung's
   ss_vibrator.c (CHIP_ISAXXX, GP2 clock on GPIO 50 + enable GPIO 76; gt510 M=3/N=140 = 25.7 kHz, ~98 % duty, set
   once at probe; on/off = GPIO 76 + pin mux). Mainline: pwm-vibrator on clk-pwm (GCC_GP2_CLK, 10 kHz, 75 %) +
   motor_vdd fixed regulator on GPIO 76; feedbackd tags it (FEEDBACKD_TYPE=vibra, uaccess). Checked during effects:
   regulator on, GPIO 76 pad high (TLMM in=1), GP2 CBCR/RCGR on with the expected M/N/D (/dev/mem), GPIO 50 muxed to
   gcc_gp2_clk_a. Drove 10 kHz 75 %, 25.7 kHz 98 % / 75 % / 50 % / 2 %, and GPIO 50 static high: Yaron felt nothing in
   any test, and the mic (motor sits in the display frame) shows no 80-400 Hz rise (-64 dB in every mode). SM-T550 is
   listed with a vibra module (GH31-00724A) → connector/motor fault or not fitted on this unit; needs opening the
   tablet. Yaron does not remember whether it ever vibrated on Android. Tools: haptics/ (ffrumble.py, gp2regs.py,
   gp2set.py, tlmm.py, vibmic.sh). Hardware review: #3 done → #4 hardware video decode next.
21. IN FLIGHT (2026-10-06, session 392683) — **Hardware video decode (Venus)** (hardware review #4). Venus decoder
   /dev/video5 (H264/VP8/VC1/MPEG-4/MPEG-2/H.263 → NV12) is auto-picked by GStreamer 1.28.7 (v4l2h264dec primary+1):
   1080p decode-only 60 fps at 8 % CPU vs avdec 66 fps at 80 %. Problems found: (a) GNOME Showtime puts glsinkbin in
   front of gtk4paintablesink (GL upload stalls/drops dmabufs here) → local patch video/patch-showtime-play.py
   (gtk4paintablesink direct unless SHOWTIME_GLSINKBIN=1; SW decode 8 → 27 fps shown, 116 → 61 % CPU), TEST copy only;
   (b) every Venus seek froze (Showtime seeks after preroll → stuck on the first frame): capture buffers QBUF'd before
   capture STREAMON in a seek never reached the firmware → **kernel/0129** (submit them at output STREAMON after the
   ETBs, and hold capture buffers back in vdec_vb2_buf_queue during SEEK so none goes twice; an earlier draft
   double-submitted → firmware Err_Fatal vbuffer.c:623) + **kernel/0130** (capture STREAMOFF left READONLY-parked
   buffers linked on delayed_process; after the seek the delayed work submitted a stale one while userspace owned it,
   userspace queued it again → firmware "session error 1004" a few frames after every seek; found with
   video/vtrace.sh, trace video/traces/vt-seek0-v3.txt). Test module ~/venus-dec-0129v4.ko (= 0129+0130) on an idle
   tablet: preroll 0.44 s, seek 0 → 5.01 s after 5 s (×3), seek 10 → 13.34 s (×2), no kernel errors; patched Showtime
   on Venus PLAYS (was: frozen on the first frame). (c) waylandsink sees no dmabuf formats: phoc's wlroots 0.20.2 sends
   v3 clients only the implicit modifier when a format has just {INVALID, LINEAR} (XWayland workaround); GStreamer
   binds v3 and drops implicit → no zero-copy. Not fixed (low value: Showtime uses gtk4paintablesink). (d) OPEN:
   Showtime on Venus shows only 10 fps (planefps plane-0 composited), 71× "too many pending frames": main thread
   blocked 62 % in MSM_WAIT_FENCE (40-60 ms per frame) → GTK renders the 1080p NV12 frames itself on the GPU instead
   of offloading them to phoc (gst-launch → gtk4paintablesink showed 10 fps on screen too; its "30 fps" was the sink's
   count). Cause: GTK's colorstate rule (BT.709 not offloaded without colour management) → see (e). TODO was:
   CPU/battery, packages/showtime, kernel r38 INSTALLED 2026-10-06 09:17 (0129+0130), upstream candidates.
   (e) FIXED 2026-10-06 10:32: gtk4.0 4.24.1-r100 (0103) + gt510-tweaks pin installed → Showtime on Venus shows 29.2
   fps via offload (was 10), 0 refusals, Showtime 27 % of one core.
   (f) POWER (video/vidpower.sh, 2026-10-06 11:05, battery, backlight 138 fixed, 1080p30 H.264 4 Mbit/s, 40 s phases;
   video/traces/vidpower-r39-2026-10-06.txt): idle screen on 468 mA / CPU 19 % of 400 · Venus + offload 658 mA, 24.5 fps
   shown, CPU 92 % (Showtime 22 % of a core) · Venus, GDK_DISABLE=offload 614 mA but only 10 fps · avdec_h264 + offload
   993 mA, 25 fps, CPU 211 % (Showtime 170 %) · idle again 463 mA. → playback costs +190 mA over the idle screen with
   Venus vs +525 mA in software: ~6000 mAh ≈ 9 h vs 6 h of 1080p. Remaining: packages/showtime (the Showtime
   gtk4paintablesink patch is still a TEST copy in ~/vtest/st). UPSTREAM: prepared 2026-10-06 in upstream/venus/README.md
   (0129 duplicates David Heidelberg's posted seek patch → review reply with our buf_queue fixup; 0130 new patch).
22. CLOSED (2026-10-06, nothing to implement) — **Touch-key LEDs** (hardware review #9). Recents/Back are maXTouch
   1664T T15 keys (mainline keycodes KEY_APPSELECT 0x244, KEY_BACK 0x9e). Stock never lit them: Samsung's gt510 driver
   (Galaxy-MSM8916 lineage-17.1 drivers/input/touchscreen/mxt_t/, DT compatible "atmel,mxt_t") has
   touchkey_led_control() and its sec_touchkey/brightness attribute under `#if 0`, pdata->led_power_ctrl is never
   assigned and the shutdown call is commented out. The gt510 r07 DT has no key-LED regulator or GPIO (the only
   vdd_led lines sit in a commented-out coreriver tc360 node). Live pins checked: GPIO 8 = regulator-lcd-vmipi,
   GPIO 97 = DSI panel, 9/10 unclaimed inputs. Downstream pinctrl `gpio_led_pins` (GPIO 8/9/10, state gpio_led_off
   output-low) is a template leftover: the gpio_led_off phandle is referenced nowhere, GPIO 8 is panel-extra-power-gpio1,
   GPIO 9 the LTE-only sx9500 grip IRQ, GPIO 10 only spi0_cs0/tpiu template groups. The driver's EV_LED/LED_MISC bits
   have no input ->event handler (dead advertisement). → SM-T550 keys are not backlit (or nothing on the board drives them);
   no driver or DT work. Sources kept in touchkey/ref/ (not published).
   Blink test 2026-10-06 (touchkey/blink.py, 1 Hz × 10 s per phase, Yaron watching): TLMM GPIO 9, TLMM GPIO 10,
   PM8916 GPIO 1-4, maXTouch T19 GPIOs (DIR 0xFD) → nothing lit in any phase. TRAP: pinctrl-spmi-gpio
   direction_input only sets input_enabled (output_enabled stays) → PM8916 GPIO 1-4 left in INPUT_OUTPUT mode,
   driven low (same level as their old pull-down; no consumer on the T550); a reboot restores plain input (verified: r38 reboot 09:17 → in, pull-down).
   Phase 5 = TLMM GPIO 60 (key-LED pin on mainline grandmax gpio-leds / serranove key_led regulator; unclaimed and
   unused downstream on gt510) → nothing. Mainline Samsung lit keys always copy stock wiring (separate tc360/ABOV/
   tm2 touchkey MCU with LED vdd-supply + I2C LED cmd, or a plain GPIO); gt510 has keys inside the maXTouch and its
   tc360 node is commented out → design dropped the touchkey MCU and the LED. LineageOS gt510wifi overlay:
   config_buttonBrightnessSettingDefault 0. Final: no key LED on the board.
   Stock Android check (Yaron remembered lit keys): Android Authority Tab A 8.0/9.7 review "no backlighting with these
   capacitive keys"; Best Buy Q&A on the 9.7" 16GB = 3 of 4 answers "no"; Android Central (Tab A with S Pen) moderator:
   no lights behind the buttons in the Tab A line → keys were never lit on stock either.
23. ACTIVE (2026-10-06, Yaron: "playing 1080p video, stuttering as hell, non responsive") — **Firefox 1080p playback.**
   Clip = YouTube pVaeEK1WC2M at 1080p25 (offered as H.264 High avc1.640028 itag 137 2.4 Mbit/s, VP9, AV1; Firefox
   picks VP9/AV1 by default). During Yaron's playback: memory thrash — MemAvailable 0, zram 1.77/2.0 GB, memory PSI
   full 40 %, kswapd 23 %, 71 % sys CPU; the tab process had 605 MB swapped out.
   Measured (video/clips/ = synthetic high-motion 1080p25 clips at YouTube bitrates; video/swdec.sh, video/fxbench.sh):
   - ffmpeg decode alone, 4 threads: H.264 72.5 fps (1.2 cores at 25 fps), VP9 69.6 (1.0), AV1 dav1d 45.8 (1.8) →
     decoding is NOT the limit. Venus via ffmpeg h264_v4l2m2m: 65.9 fps at 6 % of one core.
   - Firefox 140.14 ESR, local H.264 clip, warm profile: 410 % CPU (all 4 cores), 17.7 fps shown: 3 decode threads
     222 % + WebRender Renderer 93 % (hardware GL; per-frame 1080p YUV texture upload) + rest. Each Firefox start
     also burns ~1 core for >30 s (pmOS policy force-installs uBlock Origin; IndexedDB/sqlite at start).
   - media.hardware-video-decoding.force-enabled=true: "V4L2 FFmpeg init successful" on Venus, then "Got non-DRM-PRIME
     frame from FFmpeg V4L2" → video stalls (0.1 fps). Upstream FFmpeg never returns DRM PRIME from v4l2m2m (Mozilla
     bug 1852765 = this exact Venus case).
   FIX CANDIDATE: packages/ffmpeg = Alpine 8.1.2-r3 + 0100 LibreELEC v4l2-drmprime (applies cleanly; NOT BUILT) +
   gt510-tweaks Firefox prefs (force-enabled HW decode; YouTube H.264 only: VP9/AV1 off for MSE) → decode on Venus and
   dmabuf zero-copy into WebRender (no texture upload). Seeks use the patch's capture STREAMOFF/ON flush → needs the
   Venus seek-restart fix (kernel 0129, ISSUES 21). Waiting for Yaron's go (laptop build).
   ffmpeg r100 BUILT + INSTALLED (2026-10-06 10:07; 55 min LTO link under qemu): h264_v4l2m2m offers drm_prime.
   Firefox (force-enabled) now decodes on Venus zero-copy ("Using V4L2 DMABufSurface", libavcodec.so.62 mapped, 0
   session errors) BUT every frame has pts=AV_NOPTS_VALUE: Firefox sets neither pkt_timebase nor time_base, and
   v4l2_get_timebase() rescales through {0,1} → INT64_MIN → frames "late", 62 flushes, the clip skipped to EOS in
   ~30 s. FIX packages/ffmpeg 0101 (identity µs timebase fallback) → r101, LTO off; queued "ffmpeg101" on the laptop
   after 392683's chain (~11:10). Then: fxbench with force-enabled → expect ~25 fps shown, low CPU; then YouTube.
   ffmpeg r101 built NATIVELY in colima t290 (aarch64, no qemu, LTO off: 6 min; laptop job cancelled) + INSTALLED
   10:19. **WORKS**: Firefox force-enabled, local 1080p25 H.264: Firefox CPU 57 % (was 410 %; RDD decoder 3 %,
   Renderer 13 %, the rest bench-profile uBlock IndexedDB), 28.1 fb changes/s, Venus open, pts correct, 0 Venus
   errors; video/fxseek.sh: 4× wtype Right (+5 s) → pts 18.3 → 46.1 → 51.8 s, 4 flushes, 29.6 fb/s, 0 errors.
   gt510-tweaks r39 (built in colima, repo seeded with kernel r39/gtk r100/mesa r100 from the laptop) = r38 +
   gt510-firefox-video.js (/usr/lib/firefox-esr/defaults/pref/: force-enabled, MSE VP9 off, AV1 off) + depends
   ffmpeg-libavcodec=8.1.2-r101 + e173ce's gt510-rebrand; handed to 392683's kernel r39 install batch.
   TODO after that: Yaron's YouTube clip (pVaeEK1WC2M) at 1080p in his own Firefox (expect avc1 itag 137 on Venus);
   memory (1.36 GB, zram) with YouTube's page weight is the remaining risk.
   YouTube (Yaron, 10:55): plays on Venus but GARBLED (blocks of other frames in moving areas) + colours shifted +
   green band. Venus itself is bit-exact (framemd5 h264_v4l2m2m copy path vs software: 600/600 identical). Causes
   (video/ref/firefox-140/: FFmpegVideoDecoder.cpp, FFmpegVideoFramePool.cpp): (1) Firefox calls
   ReleaseUnusedVAAPIFrames() before every avcodec_receive_frame() and unrefs every frame the compositor has not
   marked used → the V4L2 capture buffer goes back to Venus while it still waits for display / is on screen
   (media.video-queue.hw-accel-size=1 did not help); (2) FFmpegDescToVA puts the NV12 UV plane at pitch*frame->height
   (ffmpeg said 1080, buffer has 1088 rows) and av_frame_apply_cropping() folds any bottom crop away for hw formats.
   FIX ffmpeg 0102 (r102): released capture buffers wait 8 later releases before QBUF, num_capture_buffers 20→24;
   DRM PRIME frames report the coded height. Built in colima (repo un-seeded of mesa: the slim local mesa breaks
   ffmpeg's makedepends via mesa-rusticl). r102 + tweaks r41 (4d591a; pin ffmpeg-libavcodec=8.1.2-r102) INSTALLED
   11:19 (apk 109 s). Test pending (video/fxshot.sh burst on testsrc2, then YouTube).
24. ACTIVE (2026-10-06, hardware review #7, session d5c224) — **Full 5 MP stills (rear SR544).** The sensor streams
   2592x1944 at 27.9 fps; /etc/libcamera/configuration.yaml caps the soft ISP output at 1296x972 because 5 MP once
   debayered at 0.7 fps (2026-09-25, before the GPU debayer / Mesa a3xx work). Remeasured on r38 with the cap lifted for
   one process (camera/rear/stills5m.sh: XDG_CONFIG_HOME copy of the config without max_output_*; `cam --capture=N`):
   1296x972 25.7 fps, **2592x1944 9.5 fps** (XRGB8888, stride 2624, 20.4 MB/frame). So a 5 MP frame costs ~105 ms.
   Snapshot/aperture saves stills FROM the viewfinder stream and caps the viewfinder at 1080 tall (utils.rs best_mode
   MAX_HEIGHT), so 5 MP stills need a stream reconfigure on shutter (stop → 5 MP → let AE settle → grab → back) or a
   5 MP viewfinder (9.5 fps preview). Quality check pending: both test frames black (YAVG 25 — lens face-down); needs
   Yaron to aim the camera. camera/rear/lastframe.sh keeps only the last frame (cam --file without '#' APPENDS every
   frame to one file: 918 MB in /tmp once — deleted). The 5 MP mode is not co-sited (standard Bayer path).
   Window test (Yaron aimed it, 09:47): libcamera's simple pipeline reads the FULL 2592x1944 sensor mode for 1296x972
   output too (soft ISP 2:1) — the co-sited binned path (0105) only runs for outputs it cannot get from the full mode,
   e.g. 1280x720 (Input 1296x972). Full output = 2584x1944 (ISP margin), ABGR8888 (memory R,G,B,A). So 5 MP stills
   need no sensor mode change: same exposure/gain, only the ISP output size changes. Every `cam` capture (720p binned,
   1296, 5 MP) shows a strong GREEN cast (lower-right U≈117 V≈100) and soft focus (cam runs no AF); checking whether
   Snapshot's PipeWire path looks the same (camera/rear/pwframe.sh: pipewiresrc offers only RGBA, caps need format).
   RESULT (10:05-10:15): Snapshot's own preview is green too in the window scene (392683 kmsgrab), so not cam/5 MP.
   camera/rear/awbab.sh A/B in an INDOOR scene (wall + cushion): freedreno GPU, the same shader on llvmpipe and CPU
   debayer all neutral (U≈129 V≈122) → no Mesa/shader regression. Facing the bright window again → green again →
   grey-world AWB is skewed by clipped highlights (raw G clips first; sums underestimate G → R/B gains too low). FIX
   FIX WRITTEN, NOT BUILT: packages/libcamera 0110-gt510-softisp-awb-skip-saturated.patch (r112): SwStatsCpu also
   sums only blocks below 240/255 in every channel (awbSum_/awbCount); Awb uses them with the matching black-level
   offset, falls back to all blocks under 1/16 coverage; sum_/histogram (AGC, AF) unchanged. Waits for Yaron's go
   (laptop queue + Lineage build waiting).
   libcamera r112 INSTALLED 11:17 (Yaron OK), wireplumber@video-capture restarted, camera works. Observation: ON
   BATTERY (tuned balanced-battery) rear 1296 delivers 8.5 fps vs 25-28 on USB power — same on r111 (A/B in the same
   scene), sensor at full rate (VBLANK 48, exposure max) → soft-ISP side slower on battery; separate item, not 0110.
   Soft frames were AF, not the GPU: cam runs ~45 frames before AF settles at 28 fps; 150 frames → sharp. 5 MP
   (GPU, 2584x1944) is real native detail; the CPU debayer can't scale and crops the centre instead.
   DECISION (Yaron 11:25, via e173ce): OPTION 1 = reconfigure on shutter (viewfinder stays <=1080 tall; shutter:
   stop -> 2584x1944 -> AE/AWB settle -> grab -> back), not a 5 MP viewfinder. Config cap 1296x972 still in place.
   PLAN (option 1, d5c224): Snapshot/aperture already uses GStreamer camerabin (camera/snapshot/viewfinder.rs) and
   never sets `image-capture-caps`, so stills = viewfinder caps. camerabin's wrappercamerabinsrc renegotiates the
   source to image-capture-caps for the shot and back afterwards = reconfigure-on-shutter built in. Steps: (1)
   prototype in Python (camerabin + 2584x1944 image caps, time shutter→file, check the first frame's exposure: the
   sensor mode does not change — 1296 output already reads the full 2592x1944 — so AE/AWB state should carry, else
   drop a few frames); (2) aperture patch: image-capture-caps = largest 4:3 size, viewfinder kept ≤972 tall; (3)
   config: raise max_output_* (gt510-libcamera.yaml) so 2584x1944 is offered. Snapshot rebuild = Rust (colima).

25. ACTIVE (2026-10-06, session 4d591a) — **A2DP / Bluetooth audio** (hardware review #5). Headset = Yaron's Jabra
   Evolve2 65 (paired by Yaron, now trusted). Sound server is PulseAudio 17 (module-bluez5-discover,
   module-bluetooth-policy, pmOS module-switch-on-connect); PipeWire only serves the camera.
   WORKS: connect → profile a2dp_sink, default sink switches to bluez_sink automatically; L/R channel tones correct
   (Yaron heard both); 60 s stream on SBC and on SBC-XQ 552 kbps clean (no underruns or BlueZ/PA errors), pulseaudio
   6 % / 8 % CPU, bluetoothd 0 % (audio/a2dp/a2dprun.sh); AVRCP absolute volume works (Yaron); HFP battery level
   reported (75-80 %). Codecs offered: sbc, sbc_xq_453/512/552 (PA 17 has no AAC).
   AVRCP buttons WORK: Decibels Playing → Paused 09:35:20 → Playing 09:35:21 on Yaron's presses (path BlueZ →
   mpris-proxy → MPRIS; the "(AVRCP)" uinput device stays silent while mpris-proxy runs — expected).
   HFP (headset mic/earpiece) DOES NOT CARRY AUDIO: profile handsfree_head_unit + mSBC negotiate, eSCO link comes
   up (Setup Synchronous Connection → Complete, Success, eSCO, air mode Transparent), recording = 0 frames, btmon
   0 SCO Data packets either way. Cause: mainline btqcomsmd only opens APPS_RIVA_BT_ACL/CMD and returns -EILSEQ for
   SCO (btqcomsmd.c:87); WCNSS sends voice over its internal PCM link into LPASS, which downstream reaches through
   QDSP6 AFE ports INT_BT_SCO_RX/TX (0x3000/0x3001) — mainline q6afe has no such ports. Fix = kernel (q6afe/q6dsp
   ports + gt5 DT dai links) + userspace that routes SCO audio via ALSA (PulseAudio can't; PipeWire bluez5 SCO
   offload could) — big; Yaron to decide. Scripts: audio/a2dp/{a2dprun,avrcptest,hfptest}.sh.
   MITIGATION (Yaron chose it over the big fix): packages/gt510-tweaks/gt510-bt-policy.pa → /etc/pulse/default.pa.d/
   reloads module-bluetooth-policy with auto_switch=0. Live A/B: default flips the Jabra to handsfree_head_unit (silent)
   during a media.role=phone recording; auto_switch=0 keeps a2dp_sink and records from the tablet mic. Applied at
   runtime on the tablet (lost on PA restart); packaging = fold into 392683's open tweaks r38 bump (asked).
   RECONNECT: headset power cycle → auto-reconnects (~25-40 s, headset-initiated) BUT HFP-first, so PA leaves the
   card on silent handsfree_head_unit (module-bluetooth-policy.c:360 "Do not automatically switch profiles for
   headsets"); after a PA restart the card even comes up "off". FIX = packages/gt510-tweaks/gt510-bt-a2dp (+ .service,
   user unit): pactl subscribe → any bluez card on HFP/HSP (or "off" when new) with a2dp_sink available → a2dp_sink.
   Live: forced HFP → A2DP in <3 s; manual off kept; helper restart with card off → A2DP; Yaron power cycle → card HFP
   10:00:02 → helper → a2dp_sink 10:00:03.6. Packaging asked of 392683 (r38).
   TRAP: `pactl unload-module module-bluetooth-discover` + reload with headset=ofono at runtime → PA 17 SIGABRT in
   pa_bluetooth_discovery_get (core 09:56:43); never reload BT discovery with new args (so no default.pa.d trick).
   INSTALLED with gt510-tweaks 1-r39 (kernel r39 boot 10:32): PA up with one module-bluetooth-policy auto_switch=0
   (startup reload of the POLICY module is safe; only discovery reloads crash), gt510-bt-a2dp.service enabled+active.
   AUTO-CONNECT AFTER BOOT: NO — Jabra on and trusted, still disconnected 2.5 min after boot (BlueZ ReconnectAttempts
   only covers link loss; the headset gave up while the tablet rebooted). Tablet-side `bluetoothctl connect` at
   10:35:27 → A2DP + default sink in ~10 s (first avdtp attempt timed out, retry OK). Android reconnects the last
   headset at boot. Yaron: add it → gt510-bt-a2dp autoconnect(): once per service start (login), after 3/15/45 s,
   `bluetoothctl connect` every Trusted+Paired device with an Audio Sink UUID that is not connected. Live test (installed
   helper stopped, Jabra disconnected 10:48:28): attempt 1 refused (headset blocks reconnects just after a host
   disconnect — test artefact), attempt 2 → connected 10:49:05 → a2dp_sink + default sink. gt510-tweaks 1-r40 (pkgrel
   only) built in colima t290 (BUILD_RC=0, 10:50) and INSTALLED 10:53 (plain apk add, 1/1 upgraded; triggers take ~3 min);
   helper restarted, Jabra on a2dp_sink. Boot-time auto-connect itself is verified at the next reboot.
26. ACTIVE (2026-10-06, hardware review #6, session 392683) — **Venus encoder ignores the target bitrate.** ROOT CAUSE:
   the HFI 1.x firmware budgets bits from the INPUT BUFFER TIMESTAMPS, and GStreamer's v4l2 encoders replace PTS with
   frame_number × 1 s (ETB timestamps 0, 1000000, 2000000 µs — kprobe trace video/traces/et-gst.txt) → the firmware
   gives each frame a whole second's budget (2 Mbit/s target: bars 7.4, noise 25 Mbit/s; old Snapshot ~10x).
   v4l2-ctl queues real monotonic timestamps faster than real time → undershoots instead. Ruled out (byte-identical
   output): PTS spacing (GStreamer overwrites it), S_PARM / CONFIG_FRAME_RATE (also sent for INPUT), H.264 level,
   VUI timing (time_scale 1e9). FIX **kernel/0131**: send HFI_PROPERTY_PARAM_VENC_DISABLE_RC_TIMESTAMP=1 on HFI 1.x
   (already in the 1.x packet builder, never sent) → RC from S_PARM as V4L2 intends. Module test (~/venus-enc-0131.ko
   LOADED, srcversion 6F859569…): bars 2.00 (2 VBR), noise 1.95 (2 CBR), 8.14 (8 VBR), 2.01 over 20 s (2 VBR;
   noise VBR overshoots at the start, then pays back), 1152x864 bars 4.00 (4); S_PARM 15 → budget follows. Notes:
   stream is tagged level 1.0 unless userspace sets a level (GStreamer sets H264_LEVEL 0) — cosmetic, ffmpeg warns;
   only one IDR per stream with GStreamer defaults (gop not applied?) — not checked. Tools: video/{encbench.sh,
   enctrace.sh,h264frames.py,snaprec.sh,uitap.py}. **Kernel r39 = r38 + 0131 INSTALLED 2026-10-06 10:32** (packaged
   venus_enc CED380CB…, taint 0): bars 2.00 Mbit/s (2 VBR). SNAPSHOT RECORDING with 0131
   (video/snaprec.sh: video mode, shutter tapped through a uinput touchscreen clone — Snapshot's win.take-picture is
   not on D-Bus and has no key; tap position from the wlr-randr transform): 1152x864 Baseline, VIDEO 0.78 Mbit/s
   + AAC 56 kbit/s, 23.7 fps, 20 s, no Venus errors (was ~16 Mbit/s). Cause: aperture (viewfinder.rs:909-957) gives
   x264enc/openh264enc/va*/vulkan/vp8enc DEFAULT_BITRATE 2048 kbit/s but has NO entry for v4l2h264enc → driver
   default video_bitrate 1 Mbit/s now really applies. Proposed: packages/snapshot 0103 adding v4l2h264enc with
   extra-controls "controls,video_bitrate=2097152" (= upstream's 2 Mbit/s; upstreamable) — Yaron: yes; snapshot
   51.0-r113 INSTALLED 11:21; first recording ~1.6-2.7 Mbit/s (file not finalised — clean re-check pending).
   UPSTREAM: 5-patch series 0107/0109/0110/0111/0131 prepared in upstream/venus/ (Yaron signs off and sends).
27. DONE (2026-10-06 10:08, session 57d516) — **Spec cross-check** (Yaron pasted a web spec sheet "for GT510"). That
   sheet is the SM-T510 (Tab A 10.1 2019, Exynos 7904, codename gta3xlwifi), NOT our SM-T550 (codename gt510, APQ8016)
   — the codename/model clash. Real SM-T550 rows (GSMArena) vs the tablet, read-only checks 09:54:
   1.2 GHz quad A53 (we run 1.21 GHz, CPR) · RAM 1.5 GB (MemTotal 1.36 GB) · eMMC 16 GB (30777344 sectors, HS200
   177.7 MHz 8-bit 1.8 V) · microSDXC (64 GB card OK) · 9.7" 768x1024 TFT · 5 MP AF + 2 MP (both work) · 3.5 mm jack
   (input device present; parked by Yaron) · Wi-Fi a/b/g/n dual band (2 bands, no VHT = correct) · BT 4.1 A2DP
   (ISSUES 25) · microUSB 2.0 (OTG, CDP/DCP/SDP) · accelerometer (+ cm3323 light + hall, no gyro/proximity) · battery
   6000 mAh (gauge design 5550, learned full 5424 mAh). Positioning: GSMArena says GPS/GLONASS on CELLULAR models only
   → hardware review #8 (GPS fix) may have no antenna on the Wi-Fi T550; check before any kernel work. CHECKED: stock
   T550 firmware declares android.hardware.location.gps → antenna very likely present (ISSUES 29 sub-note).
   OPEN: "dual speakers" vs ONE max98357a node in the DT (QUAT MI2S SD1, sdmode GPIO 55). audio/tools/spkchan.sh
   (1 kHz on L / R / both / L−R to the Speaker sink, Mic1 1 kHz band): quiet −77.8, left −51.0, right −37.3, both
   −31.6, anti(L−R) −37.6 dB → both channels reach the speaker(s); not a single (L+R)/2 mono amp (L−R would cancel)
   → looks like two amps/speakers = true stereo; but "both" exceeds the coherent L+R sum (−35.7) → first phase (left,
   sink resuming from SUSPENDED) suspect. Rerun in shuffled order (`~/spkchan.sh both right left anti left right
   both`) was refused by its own guard: Snapshot was recording (10:00). RERUN 10:03 (no streams): quiet −78.5,
   both −31.4/−30.4, right −37.2/−35.9, left −36.6/−36.5, anti −39.7 → the first run's left −51 was the resume
   warm-up. VERDICT: TRUE STEREO, nothing to fix — L = R, both = +5-6 dB (in-phase sum), L−R only −3 dB (one mono
   amp would cancel L−R electrically to the quiet floor; two transducers ~4 cm path difference at the mic give exactly
   −3 / +5.4 dB). So two amps on the one QUAT SD1 line (SD_MODE straps L and R, GPIO 55 enables both) behind one DT
   codec node. PLACEMENT (10:05-10:07, Yaron covered each grille during 10 s pink noise per channel, tablet right-up
   = transform 3): L → bottom-right grille, R → top-right grille, both on the edge you see on the right = the PORTRAIT
   BOTTOM edge. In portrait: L = bottom-left, R = bottom-right → channel order CORRECT. Landscape stacks them
   vertically (no stereo image possible); only 180° portrait would be reversed. NO CHANGE (no rotation swap).
   Cosmetic: Bluetooth advertises "Qualcomm msm8916-based device" (other devices see that name when pairing).
   FIXED (10:35, Yaron asked): source = /etc/machine-info from device-qcom-msm8916 (deviceinfo_name/manufacturer of
   the generic port: PRETTY_HOSTNAME + HARDWARE_VENDOR/MODEL); bluetoothd's hostname plugin advertises
   PRETTY_HOSTNAME, Settings > About shows vendor/model. gt510-rebrand now seds ONLY those exact defaults →
   PRETTY_HOSTNAME="Galaxy Tab A 9.7", HARDWARE_VENDOR=Samsung, HARDWARE_MODEL="Galaxy Tab A 9.7 (SM-T550)" (vendor
   matched quoted or unquoted: hostnamed rewrites the file without quotes); a user-set name is kept. Tested on the
   tablet's busybox sed (pristine + hostnamed-rewritten + user-name files). Ships in gt510-tweaks r39 (d5c224's bump;
   r38 was already built; file synced to the laptop, md5 7a85462c). LIVE on the tablet: machine-info fixed via
   hostnamectl --pretty + the same sed; hostnamectl shows the new values. bluetoothd (up since 09:17) still says the
   old name: BlueZ's hostname plugin (plugins/hostname.c property watch) did not get the change. Likely cause, not
   verified: hostnamed exits when idle, so the watch is stale. The new name applies at the next bluetoothd start
   (planned r39 reboot, or `systemctl restart bluetooth`, which drops the Jabra).
   r39 BUILT (d5c224), staged on the tablet in ~/tweaks-r39/; verified: the APK's /usr/libexec/gt510-rebrand md5 =
   7a85462c. 392683 installed it in the kernel r39 batch (one reboot 10:32). VERIFIED 10:56 (57d516, read-only):
   bluetoothd started 10:32:41 → `bluetoothctl show` Name + Alias = "Galaxy Tab A 9.7"; hostnamectl Pretty "Galaxy
   Tab A 9.7", Vendor Samsung, Model "Galaxy Tab A 9.7 (SM-T550)"; installed gt510-tweaks is already r40 with the same
   gt510-rebrand (md5 7a85462c; its re-run left the values unchanged); Jabra reconnected by itself. DONE.
28. ACTIVE (2026-10-06, hardware review #10, session d5c224; research only, nothing changed) — **CPR: per-chip CPU
   voltages.** Today (0113, r21+) CPR runs "qcom,force-ceiling-voltage": every corner at its ceiling, fuses ignored —
   200/400 MHz 1.05 V, 533-998.4 MHz 1.1625 V (gt510: 998.4 on NOM), 1.094-1.2096 GHz 1.35 V. The mainline
   msm8916_cpr_desc in 0113 has corner limits only (no fuse cells, refs, steps; "fuse-based scaling not supported
   yet"). Downstream (Samsung msm8916-regulator.dtsi → kernel/ref-dts/samsung-msm8916-regulator.dtsi): fuse row 27,
   open-loop init voltage = ref (1.05/1.15/1.375 V) + 6-bit sign-magnitude × 10 mV at bits 36/18/0, target quotients
   12 bits at 42/24/6, ro-sel bits 54, step quotient 26, floors 1.05/1.05/1.1625, ceilings 1.05/1.15/1.375; downstream
   ran 998.4 MHz and up on TURBO, closed loop on top. THIS chip (kernel/cpr-fuses.py, read from the corrected QFPROM
   mirror 0x5c000 via /dev/mem; raw 0x58000 left alone): row 27 = 0x988d920364911b29 → SVS 1.05 V, NOM 1.11 V,
   TURBO **1.285 V** (fields 0x20/0x24/0x29), quot 868/868/1132, ro-sel 2, CPR not fuse-disabled.
   → Open-loop from fuses would run 1.094-1.2096 GHz at 1.285 V instead of 1.35 V (-65 mV, ~-9 % dynamic CPU power
   at the top speeds, later throttling) and 533/800 MHz at 1.11 V if 998.4 moves to its own corner. Options: (a)
   complete msm8916_cpr_desc with the fuse cells/refs/steps → per-chip open loop (closed loop stays off); (b) hard-code
   this unit's 1.285 V ceiling (not portable to other SM-T550s). Needs a kernel build + stress test (0113 r20 style:
   4-core sha256, temperatures) + reboot → Yaron's go.
29. ACTIVE (2026-10-06, hardware review #8, session 4d591a) — **GPS fix.** Stack: gpsd 3.27.3-r101 `-N -b pds://any`
   (gpsd-pds.service, engine runs only while a client watches); QRTR name service lists LOC/PDS svc 16 v2 on the modem
   (node 0 port 14) → "QRTR open: Found PDS at 0 14". Indoors (10:05, gpsd -D 6, 73 s): NMEA at 1 Hz (GNGNS, GPGGA,
   GPRMC, GPGSA, GNGSA, GPVTG, GLGSV), all empty: no GPGSV at all, one blank GLGSV entry, RMC "V", engine clock unset
   (GNS 16:09:09 vs 07:05 UTC) → no satellites indoors, as expected. Earlier notes conflict: history "GPS (Yaron
   confirmed a fix)" vs public README "no outdoor fix tested"; GSMArena lists GPS only for cellular SKUs (ISSUES 27).
   OUTDOOR RESULT (10:10-10:24, Yaron outside, gps/gnsslog.py under systemd-inhibit): GPS WORKS. Cold start (engine
   clock unset, no XTRA/time injection): nothing for ~11 min, first satellites at 669 s, FIRST 3D FIX AT 714 s
   (11.9 min); 60 s later 12 seen (GPS gnssid 0 + GLONASS 6), 5 used, eph 74 → 28.5 m. e173ce re-read the log: first
   satellites at 628 s (8 at once — maybe when Yaron stepped outside; unknown), GPS periodically drops out of gpsd's
   sky view (GLONASS-only samples), real SNRs only 17-30 dB-Hz (open sky ~35-45) → antenna works but marginal. → The
   Wi-Fi T550 HAS a working GNSS antenna (GSMArena's "cellular only" is wrong; matches e173ce's stock-partition
   evidence). Oddity: gpsd reports SNR 237 and 64 for two satellites (impossible dB-Hz; likely a GSV signal-ID/field
   quirk in the PDS NMEA). Position stays only in /tmp/gnss-outdoor.log on the tablet (never copied here).
   XTRA (Yaron: add it). Modem LOC "predicted orbits source" = xtrapath{2,3,1}.izatcloud.net/xtra3grc.bin (~24-27 KB,
   refreshed several times a day); its stored XTRA was from 2026-09-24 (168 h validity → expired). qmicli 1.39 has
   --loc-inject-time but no XTRA-data injection → gps/gt510-xtra-inject (Python, QRTR → LOC 0x0035 Inject Predicted
   Orbits Data, 1024-byte parts, format 0 = XTRA; layout from libqmi qmi-service-loc.json): 23676 B in 24 parts, all
   accepted → validity 2026-10-06T07:00Z +168 h. Packaged in gt510-tweaks 1-r41 (built colima 10:58): /usr/libexec/
   gt510-xtra (wait for LOC, download if cache >20 h old into /var/cache/gt510-xtra, inject UTC time if NTP-synced,
   inject XTRA if <7 days old; 1.1 s) + gt510-xtra.{service,timer} (1 min after boot, then every 8 h), depends
   python3 qmi-utils. NEXT: fair TTFF test = qmicli --loc-delete-assistance-data, run gt510-xtra, then outdoors.
   Tools: gps/{gpswatch.py,gnsslog.py,qrtrlookup.py,gt510-xtra-inject}.
   ANTENNA DESK CHECK (session 57d516, 10:15, nothing on the tablet changed): VERY LIKELY PRESENT. Stock system
   mmcblk0p25 (NMF26X.T550XXU1CQL5, ro.product.model=SM-T550; mounted ro,noload, unmounted) declares
   android.hardware.location.gps (etc/permissions/android.hardware.location.gps.xml) and ships the full Qualcomm loc
   stack (gps.default.so, flp.default.so, libloc_api_v02/libloc_eng/libizat_core/liblbs_core, com.qualcomm.location).
   Samsung strips telephony from Wi-Fi builds; a declared .gps feature without a receiver would fail CTS → GSMArena's
   "cellular only" is probably wrong for the T550. No external LNA / antenna-switch GPIO: none in downstream gt510wifi
   r07 DT, gt510lte dtsi or msm8916.dtsi, none in gps/sap/izat.conf (RF front end = modem RFC; nothing for Linux).
   Stock assistance config: XTRA_SERVER_1..3 = http://xtrapath{1,2,3}.izatcloud.net/xtra2.bin, NTP_SERVER =
   time.izatcloud.net, SUPL_MODE=3, CAPABILITIES=0x37, NMEA_PROVIDER=1. Cold start without XTRA/time injection →
   allow ≥15 min open sky before calling it dead. Proof still = the outdoor run (satellites with SNR).
30. ACTIVE (2026-10-06, hardware review #11, session 4d591a) — **Off-mode charging** (charger plugged into a powered-off
   tablet). Desk research (tablet outdoors for ISSUES 29):
   - lk2nd forwards the Samsung bootloader's cmdline (lk2nd/device/device.c:215 concat_cmdline) and its own
     " androidboot.mode=charger" pause (app/aboot/aboot.c:610, gated by charger_screen_enabled=0 by default) ONLY for
     Android-style boots: GENERATE_CMDLINE_ONLY_FOR_ANDROID (aboot.c:1088) passes extlinux cmdlines verbatim. Our boot
     cmdline (power/dmesg-r33-lidsuspend.txt) has no androidboot.* at all → nothing tells Linux it was a charger boot.
   - Mainline qcom-pon (drivers/power/reset/qcom-pon.c) only does reboot-mode; no PON-reason report. Readable from
     userspace via regmap debugfs (pm8916 PON_REASON1 0x808, WARM_RESET_REASON1 0x80A, POFF_REASON1 0x80C; read-only).
   - pmOS: charging-sdl (initramfs charge screen on androidboot.mode=charger) is gone from current pmaports; no
     replacement → a charger-triggered power-on most likely boots straight into Phosh.
   TO MEASURE (needs the tablet + Yaron; combine with 392683's r39 reboot): (1) `poweroff` with the charger attached:
   stays off, or powers back on? (2) off + unplugged, plug charger: what boots, how long, PON_REASON1 bits;
   (3) if it stays off: does the MAX77849 still charge (gauge before/after). Fix options after that: a pmOS initramfs
   charge mode (PON reason USB_CHG/CBL and not KPDPWR → battery % on screen, power key continues boot, unplug →
   poweroff; needs charger + gauge modules in the initramfs) or accept "charger boots the OS".
   Tool: power/ponreason.sh (root; reads ONLY PMIC regmap 0-00 regs 0x808/0x80A/0x80C/0x80D by seeking 9-byte lines,
   decodes PON/POFF reasons, prints cmdline androidboot.* and power_supply state). Baseline 11:17 (boot = 10:32 `reboot`
   with USB attached): PON_REASON1 0x11 = HARD_RESET + USB_CHG, POFF_REASON1 0x02 = PS_HOLD, cmdline has no androidboot.*,
   battery 81 % discharging −597 mA (charger offline). Expect a charger-only power-on to read USB_CHG without HARD_RESET
   and KPDPWR_N (= lk2nd's target_pause_for_battery_charge condition).
   TEST PLAN (~10 min, tablet unavailable to other sessions; Yaron watches): charger plugged, run ponreason → (A)
   `systemctl poweroff` → 60 s: stays dark or powers back on (what shows: Samsung logo / lk2nd / pmOS splash)? If it
   boots: ponreason. (B) if dark: 5 min on the charger, unplug 10 s, plug in → boots? what shows, how long; ponreason +
   battery vs before. (C) if nothing boots: power key → ponreason (KPDPWR) + battery: did it charge while off?
31. OPEN (2026-10-06, session 4d591a) — **gt510-tweaks upgrade burns ~3 min of CPU** (r40 install 10:50-10:53: apk.log
   spends it in post-upgrade/triggers; overlapped Yaron's YouTube test → likely the early stutter d5c224 saw).
   Suspects (post-upgrade): unconditional `systemd-hwdb update` (full hwdb.bin recompile, for one 61-gt510 hwdb file),
   `udevadm trigger --subsystem-match=input`, a dozen `systemctl --global` calls, + postmarketos-base-systemd trigger.
   r40 transaction (apk.log): post-upgrade `systemd-hwdb update` → systemd-262-r3.trigger (watches
   /usr/lib/udev/hwdb.d, rules.d, systemd/{system,user}, …) runs `systemd-hwdb update` AGAIN + daemon-reload + reloads
   marked system/user services → gtk icon cache → postmarketos-mkinitfs trigger (watches /usr/lib/udev,
   /usr/share/plymouth, …) regenerates the initramfs (10:52:34-10:52:51 = 17 s + boot-deploy). So most of the time sits in
   the two hwdb compiles + reloads before mkinitfs (to confirm by timing one `systemd-hwdb update` on an idle tablet).
   FIX PREPARED (Yaron asked; in r41 sources, not yet built): hwdb file → /etc/udev/hwdb.d (read by systemd-hwdb,
   watched by no trigger); post-upgrade recompiles + re-applies the keymap only when its sha256 differs from
   /var/lib/gt510/hwdb.sha256 (post-install writes the stamp). Remaining per-upgrade cost: mkinitfs (61-gt510-accel.rules
   in /usr/lib/udev + plymouth theme) and systemd reloads; next candidates: rules → /etc/udev/rules.d, splash theme →
   own package. Build note: d5c224 keeps colima's mesa r100 seed in dist/colima/seed/ (removed from the repo because it
   breaks ffmpeg builds); tweaks builds need re-seed → build → un-seed. Until fixed: never install tweaks while Yaron
   uses the tablet.
32. OPEN (2026-10-06 11:30, added by e173ce at Yaron's request; unassigned) — **Rear camera slow on battery.**
   Found by d5c224 during ISSUES 24: on battery (tuned profile balanced-battery) the rear camera at 1296x972
   delivers 8.5 fps vs 25-28 fps on USB power, same scene. Same on libcamera r111 (A/B), so not 0110's AWB change.
   The sensor runs at full rate (VBLANK 48, exposure at max), so the loss is on the soft-ISP side (GPU debayer +
   CPU stats). Leads, NOT checked yet: what the battery tuned profile changes (cpufreq governor/max, GPU devfreq
   min/governor, a3xx runtime PM); compare scaling_cur_freq + GPU devfreq cur_freq and per-frame ISP time on battery
   vs USB with the same scene. Also check Snapshot's preview fps on battery (users see this, not only `cam`).
