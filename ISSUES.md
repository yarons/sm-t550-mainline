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
   (Yaron didn't ask to remove it; 5 GHz is faster). Open: NV packaging (first-boot copy from the stock system partition?).
   STOCK NV: found on the stock system partition (mmcblk0p25, T550XXU1CQL5, mounted ro,noload then unmounted) →
   wifi/stock-T550XXU1CQL5/ (local only: proprietary, never in the public repo). wifi/nvtest.sh: it loads (atime) and
   5 GHz works with 0 hal_join and 0 BMPS errors (db410c NV: BMPS failed at every connect = power save never on);
   2.4 GHz still failed with it. HAND-INSTALLED on the tablet: /lib/firmware/updates/wlan/prima/WCNSS_qcom_wlan_nv.bin
   (stock NV; remove to go back). Power save on with it: 24/24 pings, ~45 ms RTT. WATCH: 08:15-09:57 the tablet was
   unreachable over Wi-Fi while NM stayed connected (DHCP renew 09:12 worked) — cause unknown (BMPS? scan?).
   Archived pmaports firmware-samsung-gt510-wcnss-nv (pastebin base64) sha512 matches none of the stock file's base64
   encodings (format unknown).
