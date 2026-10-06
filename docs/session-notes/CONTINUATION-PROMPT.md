# Continuation prompt: Samsung Galaxy Tab A 9.7 (SM-T550, gt510wifi) on postmarketOS

Paste this into a new session to continue. Everything lives in `~/workspace/gt510-pmos/`.
- `ISSUES.md` — the ordered issue list. Yaron (2026-10-01): "collect all the issues in a side note and work on them
  sequentially". Add new issues there, work top to bottom, update it after every step.
- `CONTINUATION-PROMPT.2026-09-27-history.md` — how every fix was found (camera bring-up, venus, SD card, OTG, GL
  renderer, CPR, camera texture path, co-sited Bayer, Mesa a3xx bugs, autofocus…), including every earlier version of
  this file verbatim (the last one = "as of 2026-10-01 18:10"). Read the relevant part before re-investigating.
- Memory: `samsung-t550-gt510.md`, `upstream-ai-policies.md`, `check-ai-policy-before-upstreaming.md`.

## IN FLIGHT (2026-10-06 08:30) — hardware review #4: hardware video decoding (ISSUES 21, not yet written there)
Findings so far (tools in video/ + on the tablet in ~/vtest: t1280x720.mp4 / t1920x1080.mp4 = 20 s testsrc2 H.264
High 4 Mbit/s made with ffmpeg libx264, decbench.py, showbench.sh, planefps.py):
- Venus decoder = /dev/video5 (v4l2-ctl: H264, VP8, VC1, MPEG-4/XviD, MPEG-2, H.263 → NV12). GStreamer 1.28.7
  v4l2h264dec has rank primary+1 (auto-picked). Decode-only (decbench.py, sync=false): 1080p HW 60 fps at 8 % system
  CPU vs avdec_h264 66 fps at 80 %; 720p HW 85 fps / 28 % vs SW 128 / 84 %. Real time (fakesink sync=true): 593
  rendered, 0 dropped, 30 fps. Decoder caps: DMABuf DMA_DRM drm-format=NV12 (no modifier) 1920x1088 (coded height).
- GNOME Showtime 50 (the only player) builds GstPlay with glsinkbin(sink=gtk4paintablesink) whenever the paintable
  has a GL context (always here: GSK_RENDERER=gl) — /usr/lib/python3.14/site-packages/showtime/play.py:24-38.
  With Venus it shows the first frame and stays "Stopped" (MPRIS); with SW decode it plays at ~8 fps shown, 116 % CPU.
- gst-launch, 14 s each, fpsdisplaysink: v4l2h264dec → gtk4paintablesink DIRECT = 338 rendered / 0 dropped / 30 fps
  (GTK imports the NV12 dmabufs itself); v4l2h264dec → glsinkbin → gtk4paintablesink = 175 / 55 dropped (slow start);
  avdec → glsinkbin = 1.7 fps. glimagesink with Venus: ~4 s start + 33 drops, then 24-26 fps. waylandsink: phoc's
  dmabuf format list arrives EMPTY in GStreamer (drm-format={}) → only RGB wl_shm → playbin inserts videoconvert →
  CPU reads uncached dmabufs → "A lot of buffers are being dropped".
- Not the cause (checked): timestamps (identical HW/SW), CMA (16 MB, only 2.5 MB free, but Venus is behind the IOMMU;
  no allocation errors), GTK patch 0102 (GTK imports the buffers fine).
- Showtime patch (Yaron: "go ahead with the Showtime patch"), TEST stage — not packaged yet:
  video/patch-showtime-play.py patches play.py to use gtk4paintablesink directly unless SHOWTIME_GLSINKBIN=1.
  Patched copy on the tablet: ~/vtest/st/showtime, run with PYTHONPATH=/home/user/vtest/st (showbench.sh takes env).
  SW decode with it: 27 fps shown at 61 % CPU (stock glsinkbin: ~8 fps, 116 %).
- Venus in Showtime stalled on GstPlay's initial flushing seek to 0 → **kernel/0129** (NEW, in no kernel build yet;
  applied to the colima kdev tree): vdec_start_output SEEK branch — if capture was re-STREAMON'd while output was
  off (STREAMOFF both, STREAMON cap, STREAMON out) streamon_cap is 0, so no capture buffers were ever given to the
  firmware → queue_dpb_bufs + process_initial_cap_bufs + streamon_cap=1. Test module kernel/out/venus-dec.ko =
  tablet ~/venus-dec-0129.ko (`sudo modprobe -r venus_dec && sudo insmod ~/venus-dec-0129.ko`; taints 12288;
  reboot or modprobe -r + modprobe restores the packaged one). video/seektest.py: seek to 0 now done in 0.11 s and
  plays (position 5.01 s after 5 s). **Mid-stream seek still stalls**: seek to 10 s → ASYNC_DONE, capture DQBUFs
  continue (strace), GStreamer logs "dropping frame 0:00:09.033…" then nothing; position frozen at 8.43 s
  (config-interval=-1 no help). Unsolved — track separately.
- LATEST (08:28, fresh insmod of the 0129 module, patched Showtime, 1080p clip): Venus opened (4 fds), Showtime CPU
  30 %, but only 8.8 fb changes/s on plane-0 (XR24 768x1024 = composited, no overlay plane) and MPRIS not found
  within 5 s (mpris=none). GST log: 32× gtk4paintablesink "Have too many pending frames" (imp.rs:854 show_frame)
  → GTK/compositor not consuming frames fast enough (frame callbacks?) — NEXT to investigate (vs gst-launch
  v4l2h264dec ! gtk4paintablesink = 30 fps, 0 dropped). Kernel log also shows `qcom-venus … session error: event
  id:1004` = HFI_ERR_SESSION_INVALID_SESSION_ID (video/ref/hfi_helper.h:39), repeated ~1/s, 4× around that run
  (likely at teardown — pkill showtime — check whether stock venus_dec does the same before blaming 0129). An
  earlier run right after the mid-seek tests fell back to SW decode (venus fds=0).
- NEXT: (1) "too many pending frames" in Showtime vs gst-launch; (2) 1004 errors stock vs 0129; (3) mid-stream seek;
  (4) GtkGraphicsOffload (does phoc put the NV12 subsurface on an overlay plane? planefps shows only plane-0), CPU,
  battery; (5) package packages/showtime (Alpine showtime + patch, pkgrel ≥100) and decide 0129 → kernel r38 (ask
  Yaron before building/installing); (6) write ISSUES 21. Later: waylandsink empty dmabuf formats (phoc
  linux-dmabuf feedback), ~4 s Venus start in GL paths.
- Tablet: unlocked + on USB power for this (it auto-locks after suspend now — Phosh lock on resume, gt510-tweaks
  disables lock only on blank; to check). Wi-Fi LAN-IP (./gw). Laptop keep-awake expired (it sleeps).
  Test module 0129 is LOADED on the tablet right now.
- PUSHED 7ffd5b4 (2026-10-06 ~10:15, session 392683; before: 06ed139): kernel 0129/0130/0131, gtk4.0 0103 (old
  0100-0102 dropped), snapshot 0103, libcamera 0110, ffmpeg r100 (d5c224), gt510-tweaks BT files (4d591a), gps/touchkey
  tools, video tools + traces, notes + ISSUES 21-28. review/scrub-map.tsv now also maps Yaron's headset BT MAC.
  Excluded as before: video/ref/, images/videos (*.png/*.mp4), attic/ (incl. 4d591a's PA source copies).
- HANDED OFF 2026-10-06 08:35 from session d5c224 to session 392683 (Yaron's call).
- 0129 v1 CRASHES THE FIRMWARE (session 392683, 08:40): dmesg since the v1 insmod = 7× `SFR … Err_Fatal
  vbuffer.c:623` + `no valid instance(session_id:dead)` + "system error (recovered)", 48× 1004; NONE before the insmod
  (stock module). The 08:32 Showtime run died on it ("poll error 1: Resource busy" → Stopped). Cause: capture buffers
  QBUF'd after capture STREAMON already go to the firmware (venus_helper_vb2_buf_queue: start_streaming_called), and v1's
  process_initial_cap_bufs at output STREAMON resubmits the whole m2m list → double FTB. v1 saved as
  video/venus-0129-v1-double-submit.patch. kernel/0129 is now **v2** (submit only the pre-STREAMON buffers, in
  vdec_start_capture when SEEK + output off; tablet ~/venus-dec-0129v2.ko LOADED, kdev tree has v2): no crash, but
  seektest seek 0 now STALLS (0.10 s after 5 s; v1 reached 5.01) and seek 10 stalls at 8.40, 1004 errors → Venus 1.8
  seems to reject FTBs sent after the flush before any ETB.
- **VENUS SEEK FIXED = kernel/0129 + kernel/0130** (08:55; tablet ~/venus-dec-0129v4.ko LOADED = both, srcversion
  8F7AEC6CC48817CCCDD241B; kdev tree has both; builds done without touching the tree: scratch diff via stdin, .ko via
  stdout). 0129 = v1's placement (output STREAMON in SEEK: queue_dpb + process_initial_cap_bufs after the ETBs,
  streamon_cap=1) + vdec_vb2_buf_queue keeps capture buffers in the m2m context while SEEK && !streamon_out. 0130 =
  vdec_stop_streaming(capture) unlinks inst->delayed_process: READONLY buffers parked there survived capture
  STREAMOFF, so after the seek the delayed work submitted a stale entry while userspace owned it; userspace queued it
  again → double FTB → firmware "session error 1004" ~150 ms after every seek (trace video/traces/vt-seek0-v3.txt,
  video/vtrace.sh = function tracer on venus_* + kprobes on STREAMON/OFF/QBUF/submit/done/flush/events; kprobe types
  9 = CAPTURE, 10 = OUTPUT). 0129-alone "worked" only under CPU contention (Yaron's Firefox thrash) — timing. Idle
  tablet with both: preroll 0.44 s, seek 0 → 5.01 s after 5 s (×3), seek 10 → 13.34 s (×2), no kernel errors.
  The v2 "FTB before ETB is rejected" idea is unproven (same 1004 signature as the 0130 bug). Thrash root cause per
  d5c224: Firefox SW decode, zram 1.77/2.0 GB, MemAvailable 0 — the Firefox 1080p issue is d5c224's.
- **Kernel r38 INSTALLED 09:17** (verified: uname #39 Oct 6 06:04 UTC, taint 0, venus_dec CEEE21FD…, seek 0 → 5.23 s,
  seek 10 → 13.27 s, 0 session errors, 0 GPU faults; one reboot also covered 4d591a's PM8916 GPIO reset; NOTE a
  backgrounded `(sleep 1; systemctl reboot) &` over ssh dies with the ssh scope — use `sudo systemctl reboot --no-block`).
  Built 2026-10-06 09:05 ( laptop incremental 3 min, queue job kernel-r38): r37 + 0129 +
  0130. dist/kernel/linux-postmarketos-qcom-msm8916-7.3_rc2-r38.apk sha256 0fb98a93…b5de85 (also on the laptop). Check:
  venus-dec.ko srcversion r37 2D90E754… → r38 CEEE21FD… (only 0129/0130 touch venus; kdev builds differ by config).
  Install = reboot: ask Yaron + tell d5c224 first; plain `apk add <file>` (never -u), then mkinitfs check, reboot,
  verify /sys/module/venus_dec/srcversion = CEEE21FDFF276B3D601E78E and taint 0.
- Showtime (patched copy) on Venus with 0129+0130 PLAYS (MPRIS Playing, 4 Venus fds, no kernel errors) but shows
  10 fb changes/s (plane-0 XR24 composited), 71× "too many pending frames"; showdiag (video/traces/showdiag-venus-v4.txt):
  Showtime main thread 14 % CPU, blocked 62 % in dma_fence_default_wait ← msm_ioctl_wait_fence (40-60 ms each) → GTK
  renders the 1080p NV12 frames itself on the GPU and waits for it, i.e. NO OFFLOAD (gst-launch → gtk4paintablesink
  direct: 30 fps). The sink's channel holds 3 FrameChanged; a busy main thread drops the rest (imp.rs:1026/854).
- Shared tablet (since 08:47): session d5c224 works on hardware review #9 (touch-key LEDs) in parallel; message it
  before any reboot/suspend/kernel install/perf or CPU-heavy run, and never run tests while Yaron uses the tablet.
  video/{showdiag.sh,threadsample.py} = per-thread CPU, main-thread kernel stack, strace, perf of a playing Showtime
  (needs ~/vtest/t1920x1080-100s.mp4 = 5× loop of the 20 s clip) — HEAVY, announce first.
- WHY NO OFFLOAD = GTK colorstate rule (09:15, GDK_DEBUG=offload): every frame "🗙 Texture colorstate cicp-1/1/1/0
  (NV12, straight): No color-management, non-default color state" (gdk/wayland/gdkwaylandcolor.c:1298-1304 in 4.24.1:
  without a wp_color_management surface only GDK_COLOR_STATE_YUV = cicp 1/13/5/0 (BT.601 matrix, sRGB TF, narrow) is
  offloaded; Venus/H.264 HD = BT.709 → GTK draws every frame on the a306 → ~10 fps on screen). CORRECTION: the old
  "gst-launch → gtk4paintablesink 30 fps / 0 dropped" was fpsdisplaysink's count of frames handed to the sink — the
  SCREEN showed 10 fps there too (planefps). PROOF: gst-launch … v4l2h264dec ! capssetter join=true replace=false
  caps="video/x-raw(memory:DMABuf),colorimetry=(string)2:4:7:1" ! fpsdisplaysink video-sink=gtk4paintablesink →
  0 refusals, plane-0 28.2 fb changes/s (planefps ceiling ~30), sink 29.99 fps / 0 dropped. Cost: phoc/Mesa convert
  NV12 with their default (BT.601) matrix → slight colour shift on BT.709 video. Fix options: (1) local GTK patch:
  without colour management, also offload narrow-range BT.709/BT.601 YUV (all apps, small); (2) relabel in the
  Showtime patch (Showtime only, mislabels); (3) colour management in phoc (large). Yaron decides.
  The 1004 lines are now explained by 0130 (none in d5c224's whole ffmpeg/Firefox window with v4 loaded). d5c224:
  ffmpeg h264_v4l2m2m on Venus 1080p25 = 65.9 fps at 6 % of one core; Firefox could use Venus only via ffmpeg
  v4l2m2m + LibreELEC drmprime patch (packages/ffmpeg r100, d5c224's) whose flush does capture STREAMOFF/ON → 0129/0130
  matter for Firefox seeks too.
- GTK OFFLOAD FIX (Yaron chose option 1, 09:25): packages/gtk4.0 REBASED on Alpine 4.24.1 (APKBUILD from aports
  master, pkgrel 100) + ONE patch 0103-gdk-wayland-offload-sdr-video-without-color-management.patch
  (gdkwaylandcolor.c: without colour management/representation, narrow-range YUV with BT.709/BT.601 primaries/TF/
  matrix counts as the default colorstate → offloaded; compositor converts with BT.601 → slight shift on BT.709).
  Old 4.24.0 r103 package (0100-0102) moved to attic/gtk4.0-4.24.0-r103/ (dropped earlier: not needed for Snapshot).
  Dry-run applied on the real gtk-4.24.1 tarball. Laptop queue job gtk4-r100 (localpkgs-only gtk4.0, ~19 min) queued
  09:25 behind d5c224's ffmpeg100b. gt510-tweaks r38 (Yaron) = exact pin `gtk4.0=4.24.1-r100` (a >= would let Alpine's
  next release replace it; move it on every local gtk4.0 rebuild); job tweaks-r38 waits for gtk4-r100. Install BOTH
  in one `apk add` (tweaks requires the r100 gtk). d5c224's Firefox prefs/ffmpeg pin go into tweaks r39. NEXT: install on the tablet (plain apk add of gtk4.0 + its subpackages, NO reboot;
  restart GTK apps; announce to d5c224/4d591a), verify GDK_DEBUG=offload shows no colorstate refusals + planefps
  ~28 fps in patched Showtime, check colours by eye with Yaron; then packages/showtime, CPU/battery, ISSUES 21.
- **#6 VENUS ENCODER BITRATE = ISSUES 26 (09:45)**: HFI 1.x firmware budgets from buffer timestamps; GStreamer's v4l2
  encoders send frame_number × 1 s → 4-14x overshoot. kernel/0131 (DISABLE_RC_TIMESTAMP=1 on IS_V1) → targets hit.
  Tablet: ~/venus-enc-0131.ko insmod'ed (taint; venus_dec = packaged r38). kdev tree = 0100-0131, test hunks
  reverted. **r39 = r38 + 0131 QUEUED** (Yaron, ~09:50; pkgrel 39 in kernel/apply-7.3.sh + pmos-gt510.sh, laptop job
  kernel-r39 chained after tweaks-r38 → gtk4-r100 → d5c224's ffmpeg100b, so pmbootstrap jobs never overlap). Install =
  reboot: ask Yaron, announce to d5c224/4d591a, `sudo systemctl reboot --no-block`.
- UPSTREAM VENUS (11:35): upstream/venus/README.md — A) reply to David Heidelberg's 2026-09-28 seek patch (= our 0129
  minus the buf_queue gate → double submit) with fixup + Tested-by offer; B) 0130 as a new patch; C) encoder series
  0107/0109/0110/0111/0131 + cover letter. Formatted vs mainline 2c3418fffa9d, checkpatch/get_maintainer done.
  Yaron reviews, adds Signed-off-by, sends. ref/ (mainline copies, mboxes) excluded from the public repo.
- LAPTOP BUSY from 2026-10-06 11:15 for ~6-10 h: lineage-build-first-j8 (session 153de1; matches the queue's busy check, so
  queued gt510 jobs wait). Build gt510 packages in colima t290 meanwhile (d5c224/4d591a seeded its repo; same key).
- (11:08: 4d591a accidentally truncated ISSUES.md and restored it from file history + 7ffd5b4 — re-check ISSUES 21 e/f.)
- **r39 BATCH INSTALLED 10:32** (one apk add + one reboot): kernel r39 (#40, 0131; venus_enc CED380CB, venus_dec CEEE21FD,
  taint 0) + gtk4.0/-lang 4.24.1-r100 + gt510-tweaks **1-r39** (d5c224's superset of my r38: + Firefox video prefs, +
  ffmpeg-libavcodec=8.1.2-r101 pin, + e173ce's /etc/machine-info rebrand). VERIFIED: encbench bars 2.00 Mbit/s (2 VBR),
  seek 10 → 13.35 s, gt510-bt-a2dp active, **Showtime on Venus + GTK offload: 29.2 fps shown (was 10), 0 offload
  refusals, Showtime 27 % of one core**; "too many pending frames" only in the first 4 s (startup), none after; colours
  right (testsrc2 bars). POWER 11:05 (ISSUES 21 f): Venus+offload 658 mA / 24.5 fps vs software 993 mA, idle 468 mA.
  NEXT: packages/showtime (TEST copy only so far); snapshot r113 +
  libcamera r112 still building on the laptop (~11:01 / ~11:07), then install them (no reboot) + snaprec re-check.
- SNAPSHOT RECORDING with 0131 (10:00): video 0.78 Mbit/s (driver default 1 Mbit/s; aperture has no v4l2h264enc
  entry in its DEFAULT_BITRATE map). packages/snapshot r113 = + 0103-aperture-v4l2h264enc-bitrate.patch (extra-controls
  video_bitrate = 2048*1024), Yaron 10:05. Laptop chain: ffmpeg100b (d5c224) → gtk4-r100 → tweaks-r38 (+ 4d591a's
  gt510-bt-policy.pa and gt510-bt-a2dp helper, ISSUES 25) → kernel-r39 → snapshot-r113 → libcamera-r112 (d5c224's 0110 AWB skip-saturated,
  Yaron 10:08; d5c224 installs it). gtk4-r100 started 10:07. INSTALL PLAN (Yaron): one apk
  add of kernel r39 + gtk4.0(-lang) r100 + gt510-tweaks r38, ONE reboot (announce d5c224 + 4d591a); snapshot r113
  later, no reboot. Then "laptop free" to session 153de1 (Lineage 6-10 h build waits for it) and d5c224.
  Snapshot test tools: video/snaprec.sh (uinput tap via video/uitap.py; saves in ~/Videos/Camera).
- WAYLANDSINK EMPTY drm-format = SOLVED (research, no change made): phoc's bundled wlroots 0.20.2
  (types/wlr_linux_dmabuf_v1.c linux_dmabuf_send_modifiers) sends v3 clients ONLY DRM_FORMAT_MOD_INVALID when a format's
  set is exactly {INVALID, LINEAR} (XWayland workaround, xserver#1166, still open). a3xx Mesa/EGL reports only LINEAR
  (checked: eglQueryDmaBufModifiersEXT NV12/XR24/AR24/YUYV → 0x0), so all 67 formats go out INVALID-only (WAYLAND_DEBUG:
  67/67 modifier events = 0x00ffffffffffffff). GStreamer 1.28.7 (and main) binds zwp_linux_dmabuf_v1 v3 and drops
  INVALID on purpose (gstwldisplay.c:257) → {}. The v4 feedback has both (GDK_DEBUG=dmabuf: 134 entries, NV12:0 +
  NV12:INVALID) — that is why GTK offload works. Fix options: phoc local package with a wlroots patch dropping that
  workaround (small; Xwayland risk low here: GBM supports LINEAR) or GStreamer v4 feedback (upstream draft MR !5040).
  Value low: Showtime uses gtk4paintablesink; waylandsink is only picked by explicit pipelines. Sources: video/ref/.

## Hardware review results so far (ISSUES 18-23)
#1 wake from Home/cover DONE (r36/0127; cover untested, no magnetic cover) · #2 mic DONE (r37/0128 16 kHz tone) ·
#3 vibration CLOSED = hardware (every drive reaches the pins; motor does not move; mic confirms) · #4 IN FLIGHT
(session 392683) · #9 touch-key LEDs CLOSED (ISSUES 22: stock never drives them, no LED supply/GPIO in the DT) ·
then #5 A2DP, #6 venus encoder bitrate, #7 5 MP stills, #8 GPS fix, #10 CPR voltages, #11 off-mode charging.
Headphone jack parked by Yaron.
- PARALLEL SESSIONS (2026-10-06, Yaron): 392683 owns #4 video/Venus (0129, Showtime); d5c224 owns #9 (done) and the
  **Firefox 1080p stutter** (ISSUES 23, Yaron's report 08:45: "stuttering as hell, non responsive"). Shared tablet:
  message the other session before any reboot / suspend / kernel install / heavy CPU or RAM run.
- LAPTOP HOLD (2026-10-06 10:00): session "Build laptop optimization" waits to start a 6-10 h LineageOS build
  (container lineage-build-first-j8) until d5c224 sends it "laptop free from gt510" — only after ffmpeg100b, 392683's
  gtk4-r100 + tweaks-r38, and d5c224's tweaks r39 (Firefox prefs + ffmpeg pin) are built.
- CPR (#10) = ISSUES 28: research done (fuse TURBO 1.285 V vs forced 1.35 V); waiting for Yaron's go on option (a).
- 5 MP STILLS (d5c224, #7, IN FLIGHT) = ISSUES 24: 5 MP soft ISP now 9.5 fps (was 0.7); 1296x972 25.7. Next: quality
  check with Yaron aiming the camera (camera/rear/lastframe.sh), then decide reconfigure-on-shutter in aperture vs a
  5 MP viewfinder. Laptop builder went offline ~09:35 (asleep?) with ffmpeg100b mid-build.
- FIREFOX 1080p (d5c224) = ISSUES 23: HW decode in Firefox WORKS (ffmpeg r101 = Alpine 8.1.2 + 0100 LibreELEC
  drmprime + 0101 timebase fallback, installed): 57 % CPU vs 410 %, ~28 fps shown, seeks OK. tweaks r39 (prefs +
  exact ffmpeg pin + e173ce rebrand) goes in with 392683's kernel r39 batch. Next: YouTube test with Yaron.
  colima t290 builds gt510 packages natively (gt510-pmos image + gt510-pmos-vol; seeded with laptop APKs).
- Kernel **r37** (#38) INSTALLED = r35 + 0127 (Home key + hall sensor wake from suspend, ISSUES 18) + 0128
  (msm8916-wcd-analog: PM8916 sequence clears MICB_1_INT_RBIAS → mic 16 kHz tone gone, ISSUES 19). The 20261005
  release still has r35 (no Home wake, mic tone) — a newer release would carry both.
- Hardware review order (Yaron): #1 wake DONE, #2 mic DONE, #3 vibration NEXT, then #4 HW video decode, #5 A2DP,
  #6 venus bitrate, #7 5 MP stills, #8 GPS fix, #9 touch-key LEDs, #10 CPR voltages, #11 off-mode charging;
  headphone jack parked by Yaron. ISSUES 17: kpti=0/no-serial A/B → reverted (no real gain).
- Laptop keep-awake `gt510-session` runs until ~20:03 (then the laptop sleeps again).

## STATE (2026-10-05 12:10) — nothing in flight
- RELEASE 20261005 READY TO UPLOAD (Yaron does it): `dist/release-20261005/` — tag `edge-20261005-prerelease`,
  notes RELEASE-NOTES.md, files gt510-unofficial-pmos-20261005-userdata.simg.xz (sha256 dff8c2ea…, unpacked simg
  4d5a0b3d…), lk2nd-msm8916.img, MANIFEST.txt, SHA256SUMS. Built from repo 5248021 (Mesa 26.2.4-r100 + tweaks r37,
  kernel r35), pmaports a8dc5d9b. Boot-tested: flash 354 s, first boot 30.7 s, NV copied at 12.1 s (WCNSS 20.3 s),
  0 faults, rear 28/s sensor 24.4 shown, front 22/19.4, lens parks, mesasoak 10/10 apps + calc90 OK (kgx skipped:
  Yaron's console was open → single-instance EXITED@1s), 0 black, glmark2 137. Release 20261004 (Mesa 26.2.3) is
  SUPERSEDED, never published (dist/release-20261004 kept). gtk4.0 = Alpine 4.24.1 (local r103 loses; not needed).
- First boot clock: the PM8916 RTC reads 1970 and can't be set → a fresh image starts at a stored timestamp
  (one day behind here) until timesyncd syncs; it did not retry by itself within minutes of Wi-Fi coming up
  (restart synced at once). WATCH; harmless once synced.
- TABLET = that public image + restore: password <password>, UTC, SSH key, sshd (Yaron enabled), Wi-Fi profile
  (5 GHz lock), Pictures/Videos/scripts from backup-2026-10-05/ (dconf/RetroArch from the SD card). NEW Wi-Fi IP
  **LAN-IP** (`./gw` updated, now hostname-checked). USB: the Poco F1 also sits at 172.16.42.1 on another
  interface → `./gl` (GL_HOST=fe80::…%enN link-local, hostname-checked).
- Kernel **r35** (#36) + **gt510-tweaks r36**, public repo ea60f0b. r35 = CONFIG_SUSPEND + 0125 (mdp5 stale hwpipe
  after a screen-on suspend) + 0126 (wcn36xx HT20 only in 2.4 GHz). r36 = gt510-wcnss-nv first-boot NV copy.
- Wi-Fi profile "HOME-WIFI" locked to 5 GHz (both bands work; lock kept).
- Public assembly hardened (review/assemble-public.sh): excludes wifi/stock-*/ (Samsung files), wifi/ref/,
  kernel/ref-drm/, power/dmesg-*.txt, /gw /gu /lssh /gl; scrubs SSID/BSSIDs/WLAN MACs/work account/new IPs; scan
  patterns added. In release 20261004 (above).
- Open risk: one unexplained reset during a screen-on s2idle on r33 (ISSUES 14); none on r34/r35 in 26 cycles.
- Debug helpers: `./gw` Wi-Fi ssh, `./gu` USB ssh with hostname check; wifi/{nvtest,ht20test,modtest}.sh (self-
  reverting; NM_CON/BSSID_2G env); power/{suspendab,s2wake,stalepipe}.sh; kernel/kdev-wcn36xx.sh.

Why only s2idle helps a little: RPM stats `/sys/kernel/debug/qcom_stats/{vmin,xosd}` Count 0 since boot — the cpuidle
driver is `qcom_spm` (per-core WFI + standalone power collapse only); cluster/SoC states (DT has cluster-retention,
cluster-gdhs) need PSCI firmware (Samsung's signed TZ has none; tz-psci needs unsigned TZ). Idle floor ~75 mA.

## State (2026-10-03 evening) — INSTALLED on the tablet
The tablet was reflashed with the PUBLIC release image 20261003 (boot-tested: 29.8 s, 0 faults, camera 28/s, lens
parks, no camera-service leak), then restored by hand: password <password>, timezone UTC, SSH key, sshd
enabled + Wi-Fi connected (Yaron), Pictures/Videos + test scripts from `backup-2026-10-03/`. Since then: kernel r33.
| Package | Version | Local patches |
|---|---|---|
| linux-postmarketos-qcom-msm8916 | 7.3_rc2-**r38** (#39) | msm8916-mainline 7.3-rc2 @717e5e2 + `kernel/0100`–`0107`, `0109`–`0118`, `0120`–`0130` + `kernel/gt510.config` (r33: + CONFIG_SUSPEND; r34: + 0125; r35: + 0126; r36: + 0127; r37: + 0128; r38: + 0129/0130 venus seek) |
| gt510-tweaks | **r37** | see "gt510-tweaks" (r35: rebrand; r36: gt510-wcnss-nv; r37: Mesa 26.2.4 pins) |
| libcamera | 99990.7.2-**r111** | pmOS fork + 0100–0107 (see below) + **0108 EGL context leak (upstream backport)** + **0109 park the lens on stop** |
| mesa (+dri-gallium, egl, gbm, gl, gles) | 26.2.4-**r100** | LOCAL slim build (freedreno + llvmpipe; GL/GLES/EGL/GBM only) + **0100 freedreno a3xx fixes** |
| snapshot | 51.0-**r112** | 0100 aperture paintable orientation (+EXIF/mp4 tags) · 0101 viewfinder sink sync=false · **0102 QrScreenBin snapshots its child once** (enables offload); Exec env `GSK_RENDERER=gl` only |
| gtk4.0 | 4.24.0-**r103** | 0100 no powf sRGB round trip (YUV, cairo) · 0101 cairo quarter-turn textures · 0102 import LINEAR dmabufs without explicit modifier |
| phosh | 99990.57.0-**r100** | 0100 cellular tile hidden without a modem |
| gpsd | 3.27.3-**r101** | Qualcomm PDS (`pds://any`) |
| greetd-phrog | 0.53.0-**r100** | 0100 no greetd session for an empty username ("password twice") |
libcamera 0100–0107: YUV passthrough/SR544 helper · soft-ISP contrast AF · cap only scalable outputs · YUV sensors via
CAMSS PIX as NV12 · skip the neutral contrast curve · co-sited Bayer cells · black level+AWB as one multiply-add ·
faster AF. 0108 = upstream a00a4ca2/4501b8a1 substance (one EGL context per stream start was never destroyed:
+8.1 MB GPU memory per Snapshot session). 0109 = SimplePipelineHandler::stopDevice() parks the lens at the
V4L2_CID_FOCUS_ABSOLUTE minimum (the DW9804 sat at 1023 after AF sweeps: ~125 mA idle).
Also installed (from `apk add -u`, see traps): device-mapper-libs/-udev r8, util-linux libs r2, ffmpeg-libavutil r2.

Kernel patches: 0100 MAX77849 charger/MUIC · 0101 charger = USB supply of the gauge · 0102 front camera SR200PC20 +
DT + camss CSID1 fix · 0103 s6d7aa0 1-byte brightness · 0104 msm DSI no link-clock re-set per command · 0105 rear
SR544 + DT · 0106 DW9804 lens · 0107/0109/0110/0111 venus encoder on HFI 1.x · 0112 USB OTG host · 0113 CPR + cpufreq
to 1209.6 MHz · 0114 camss VFE PIX line · 0115 SR200PC20 640x480 · 0116 MUIC CDP is USB data · 0117 sensor probe
retries · 0118 extcon-max77693 per-group pending bits · 0120 mdp5 flush the CTL before the timing engine (DPMS-on
faults) · 0121 s6d7aa0 no backlight DCS write while disabled · 0122 Sam Day's a3xx VBIF mask for A306 (runtime PM) ·
0123/0124 Dmitry Baryshkov's shared-VM dma-buf teardown series (GTK4 app-start GPU fault storms) · 0125 mdp5 no stale
hwpipe after resume (ours; upstream candidate) · 0126 wcn36xx HT20 only in 2.4 GHz (ours) · 0127 Home/hall wakeup-source · 0128 msm8916-wcd-analog
TXn− pull-ups off on PM8916 (ours) · 0129 venus vdec: submit capture buffers restarted during a seek (ours) · 0130 venus vdec:
drop parked (READONLY) capture buffers on capture STREAMOFF (ours). REVERTED: 0119.

## Public repo + release (Yaron's, 2026-10-02/03)
- Repo **github.com/yarons/sm-t550-mainline** (public, personal account). Push from `~/workspace/gt510-public`
  (its git config: `core.sshCommand` = `ssh -i ~/.ssh/old_id_rsa` = the PERSONAL key; `~/.ssh/id_ed25519` and `gh`
  are the WORK account WORK-ACCOUNT and have no access). Never commit there by hand: rebuild the tree with
  `review/assemble-public.sh` (curated rsync + `review/scrub-map.tsv` + leftover scan that FAILS on IPs/serials/
  emails/coordinates/the tablet password), move `.git` out and back around it, commit (author Yaron Shahrabani
  <406826+yarons@users.noreply.github.com>, `Co-Authored-By` trailer), scan the diff, push. `review/` is never
  published (it holds the scrub map). Yaron's rules: no photos/raw camera dumps, name yes / email no, GPL-2.0.
  HEAD 7ffd5b4 (2026-10-06: Venus 0129-0131, gtk4.0/snapshot/libcamera/ffmpeg local patches, notes ISSUES 21-28; before: 06ed139). Known: ad6268f's diff contains the tablet password (Yaron chose to leave it).
- Release images: `pmos-gt510.sh install-public` (no SSH keys, sshd off, UTC, password 147147) + `release`
  (xz'd sparse userdata image, lk2nd, MANIFEST.txt, SHA256SUMS). gt510-tweaks r35 rebrands the OS on-device
  ("SM-T550 Mainline (unofficial, based on Nura)", ID=nura kept, text plymouth theme sm-t550, Adwaita wallpaper).
- READY TO UPLOAD (Yaron does it): `dist/release-20261003/` — tag `edge-20261003-prerelease` on main (built from
  e0550f7, pmaports bbcd4e5b), title "postmarketOS/Nura (Phosh) on a mainline kernel for the Galaxy Tab A 9.7 2015
  (SM-T550) — pre-release 2026-10-03", notes RELEASE-NOTES.md, files: gt510-unofficial-pmos-20261003-userdata.simg.xz
  (sha256 1f2eaeeb…), lk2nd-msm8916.img, MANIFEST.txt, SHA256SUMS. The 20261002 builds are superseded, never published.
- Upstream hand-off (Yaron signs off and sends; AI never sends): `upstream/README.md` — mdp5 0120 patch, Tested-by
  drafts for Sam Day's a306 patch and Dmitry Baryshkov's series; `docs/UPSTREAM.md` in the repo lists all candidates.

### gt510-tweaks r35 (what it ships; r35 adds the rebrand: gt510-rebrand + sm-t550 plymouth theme + 20_gt510-branding override)
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
  drop-in); depends `mesa>=26.2.4-r100` + `mesa-dri-gallium<26.2.5` (tweaks r37) — an unpatched Alpine Mesa would hang the GPU
  within seconds of a GTK app starting. When Alpine moves past 26.2.4: rebuild packages/mesa on the new version
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
4. ISSUES 13 idle power (IN FLIGHT, see top): lens drain fixed (libcamera 0109); suspend test running on kernel r33.
   Remaining levers after it: Wi-Fi ~16 mA (DTIM 1 router, BMPS works after association), modem DSP ~8 mA (audio).
5. CPR fuse-based open-loop voltages (downstream cpr-regulator fuse rows) to run TURBO below 1.35 V.
6. Venus rate control overshoot (~10x under GStreamer), 5 MP stills, hall/jack/A2DP untested.
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

## Tools (gl-hang/, usb-otg/, display/, gpu-pm/, gtk-fault/, power/)
- power/ (2026-10-03): `powertest.sh` (root; waits for Discharging; gauge current_now per phase: baseline, Wi-Fi off,
  modem DSP stopped, baseline, screen on; restores everything) · `suspendtest.sh <idle|suspend> <secs>` (root;
  coulomb-counter average; suspend mode re-suspends via RTC alarm and logs wakeup sources per cycle).
  `suspendab.sh [secs]` (root; waits for charger online=0, then suspend + idle runs under a logind block inhibitor) ·
  `s2wake.sh <blank|lit> <secs>` one s2idle cycle with RTC wake · `stalepipe.sh <n>` lit suspend → blank cycles with
  DRM plane/hwpipe state per step (kernel 0125 check).
  Gauge: /sys/class/power_supply/max170xx_battery {current_now (µA, negative = discharge), charge_counter (µAh)}.
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
- `./gw '<cmd>'` = Wi-Fi ONLY, **TABLET-WIFI-IP** (lease since the 2026-10-03 reflash; a new install gets a new one:
  find it with a port-22 sweep and check `cat /etc/hostname` = gt510 before acting). `./gssh` tries USB 172.16.42.1
  first — DANGER: the Poco F1 (also pmOS) answers there when it is on USB; the tablet in MTP mode (usb-moded) gives
  no USB network at all. Key `~/.ssh/ssh-key`; user `user` / **<password>**; sudo via
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
- Host `builder@BUILDER-HOST` via `./lssh` (pins `~/.ssh/id_ed25519` with IdentitiesOnly: the agent offers the tablet
  key first and the laptop rejects the login) (ThinkPad, Manjaro, x86_64, 12 threads, 16 GB RAM, key login, `sudo -n docker` ONLY — any
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
