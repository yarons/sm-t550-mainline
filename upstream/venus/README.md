# Venus upstream hand-off (gt510 / SM-T550) — Yaron reviews, signs off, sends

Kernel policy (Documentation/process/coding-assistants.rst, re-read 2026-10-06): AI-assisted patches are allowed
with `Assisted-by: claude-opus-5-5`; the AI must NOT add `Signed-off-by` and never sends anything. You review, add
your `Signed-off-by` (DCO) under the `Assisted-by:` line, and send. Recipients below are from
`scripts/get_maintainer.pl --no-git` (same for all three items).

Base: mainline master 2c3418fffa9d (v7.3-rc6+, 2026-10-06). Our tested kernel is msm8916-mainline 7.3-rc2; its
`vdec.c`, `venc.c`, `helpers.c`, `hfi_cmds.c` are byte-identical to mainline master apart from these patches
(checked: same blob ids). checkpatch `--strict`: only "Unknown commit id" (no git history in the tree; ids checked
on GitHub) and ENOTSUPP-vs-EOPNOTSUPP in 1/5 (kept on purpose: the driver's own convention, see the cover letter).
Classification (threat-model.rst): regular bugs (stalls, firmware session errors, wrong bitrate). One judgement
call for you, see B.

## A. Seek fix: REPLY to David Heidelberg's patch (it duplicates our kernel/0129), don't send our own
"[PATCH 2/2] media: venus: vdec: Start capture after a seek that streams CAPTURE first", posted 2026-09-28, under
review: https://patchwork.linuxtv.org/project/linux-media/patch/20260928-venus-vdec-eos-v1-2-6e9eb3ce9849@ixit.cz/
His change = our 0129 output-STREAMON hunk, but WITHOUT the `vdec_vb2_buf_queue()` gate, so on HFI 1.x it
double-submits capture buffers queued between the two STREAMONs → firmware `Err_Fatal vbuffer.c:623` (exactly our
v1; 7 firmware crashes that morning). `reply-heidelberg-2-2.txt` = review reply + the fixup diff
(`heidelberg-2-2-fixup.diff`) + an offered Tested-by for a v2 with the fixup. Send as a reply-all to his message:

    # from your mail client (plain text), or:
    git send-email --in-reply-to='<20260928-venus-vdec-eos-v1-2-6e9eb3ce9849@ixit.cz>' reply-heidelberg-2-2.txt
    # (headers To/Cc/Subject are in the file; git send-email reads them; check with --dry-run first)

## B. NEW patch: `vdec-0130/0001-media-venus-vdec-drop-parked-capture-buffers-on-capt.patch` (our kernel/0130)
No duplicate on linux-media patchwork (searched 2026-10-06). Fixes af2c3834c8ca. Independent of A (applies to
v7.3-rc6 alone); the notes below `---` say it was found while testing A. Send after A.
Judgement call: the notes mention that stale entries would also remain if userspace frees the buffers after
STREAMOFF (a possible use-after-free; NOT reproduced, the patch closes it). Keep that sentence (open handling,
regular bug) or remove it and ask security@kernel.org first — your call; I'd keep it, as it is unverified and the
fix is public anyway. Possible trivial conflict with Chenguang Feng's "Clear streamon flags on streaming errors"
(under review), noted in the patch.

## C. NEW series: `venc-series/` (5 patches + cover letter) — the HFI 1.x encoder (our 0107, 0109, 0110, 0111, 0131)
No duplicates found. 1/5 Fixes bfee75f73c37 (the 2021 change that made every H.264 session set a property HFI 1.x
does not know — the 8916 encoder has been unusable since); 2-5/5 Fixes aaaa93eda64b. Cover letter has the results
and what was not tested (other HFI versions; 2/5 and 3/5 change behaviour on all versions but only raise sizes to
what the firmware reports). Related but separate: Snapshot's missing v4l2h264enc bitrate (packages/snapshot 0103)
is a GNOME issue — Snapshot/Aperture has no AI policy, GNOME-wide debate: ask before filing (memory
upstream-ai-policies).

## Sending B and C

    # 1) add your DCO line under "Assisted-by:" in each patch file (and review the cover letter):
    #      Signed-off-by: Yaron Shahrabani <EMAIL>
    # 2) recipients (get_maintainer.pl):
    git send-email --to="Vikash Garodia <vikash.garodia@oss.qualcomm.com>" \
      --to="Dikshita Agarwal <dikshita.agarwal@oss.qualcomm.com>" --to="Bryan O'Donoghue <bod@kernel.org>" \
      --to="Mauro Carvalho Chehab <mchehab@kernel.org>" \
      --cc=linux-media@vger.kernel.org --cc=linux-arm-msm@vger.kernel.org --cc=linux-kernel@vger.kernel.org \
      vdec-0130/0001-*.patch            # then the same with: venc-series/*.patch

Upstream copies used (not published): ref/ (mainline files, blame, the two related patchwork mboxes).
Evidence: ISSUES.md 21 and 26; video/traces/{vt-seek0-v3.txt (0130), et-gst.txt + et-v4l2ctl.txt (0131)};
tools video/{vtrace.sh, enctrace.sh, encbench.sh, seektest.py}. Build tree used to make the patches: a throwaway git
repo with the mainline files (scratchpad), so the `index` lines carry mainline's real blob ids.
