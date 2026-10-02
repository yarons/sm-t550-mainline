# Upstream hand-off (gt510 / SM-T550) — Yaron reviews, signs off, sends

Kernel policy (Documentation/process/coding-assistants.rst, read 2026-10-01): AI-assisted patches are allowed with an
`Assisted-by:` trailer; the AI must NOT add `Signed-off-by` and must never send anything itself. You review, add your
`Signed-off-by` (DCO), and send. Not security bugs (normal submitting-patches path).

## 1. a306 VBIF halt mask (our kernel/0122) — DUPLICATE, send a Tested-by instead
Sam Day already posted the identical fix (plus A306A) on 2026-09-26, Reviewed-by Konrad Dybcio, Under Review:
https://patchwork.freedesktop.org/patch/756513/ — Message-Id <20260926-a306-vbif-mask-v1-1-2bae5e81c05a@samcday.com>.
Our kernel now carries his exact patch (r31). Reply on-list with the `Tested-by` in `tested-by-756513.txt`
(reply-all to that message from your mail client, plain text, or `git send-email` — see the file header).

## 2. mdp5 enable order (our kernel/0120) — NEW, no duplicate found on freedreno patchwork
`0001-drm-msm-mdp5-Flush-the-CTL-before-enabling-the-video.patch` — format-patch against mainline master
(blob eaba3b2d = master's mdp5_encoder.c), author you, `Fixes: f9cb8d8d836e`, `Assisted-by: claude-opus-5-5`.
checkpatch --strict: only expected items (unknown commit id = tarball without git history, verified on GitHub; one
long dmesg line kept unwrapped by convention; missing Signed-off-by = yours). Recipients = get_maintainer.pl:

    # 1) after reviewing, add your DCO line under "Assisted-by:" in the patch file:
    #      Signed-off-by: Yaron Shahrabani <EMAIL>
    # 2) send (needs your sendemail SMTP config; or use b4 / your mail client with the same recipients):
    git send-email --to="Rob Clark <robin.clark@oss.qualcomm.com>" --to="Dmitry Baryshkov <lumag@kernel.org>" \
      --to="Abhinav Kumar <abhinav.kumar@linux.dev>" --to="Jessica Zhang <jesszhan0024@gmail.com>" \
      --to="Sean Paul <sean@poorly.run>" --to="Marijn Suijten <marijn.suijten@somainline.org>" \
      --to="David Airlie <airlied@gmail.com>" --to="Simona Vetter <simona@ffwll.ch>" \
      --cc=linux-arm-msm@vger.kernel.org --cc=dri-devel@lists.freedesktop.org \
      --cc=freedreno@lists.freedesktop.org --cc=linux-kernel@vger.kernel.org 0001-*.patch

The changelog states what was NOT tested (mainline itself — only the msm8916-mainline 7.3-rc2 tree, whose
`late_enable` encoder flag reorders encoder vs DSI bridge enable but not the code this patch touches; command mode;
writeback). Evidence: ../display/ab-2026-10-01/ (stock vs fixed protocol outputs).

## 3. Shared-VM dma-buf teardown (ISSUES 11) — EXISTING series, send a Tested-by
Dmitry Baryshkov, 2026-08-22, "drm/msm: fix dma-buf sharing on targets without per-process pgtables" (2 patches,
state New, no replies yet): https://patchwork.freedesktop.org/series/172617/ — Fixes 111fdd2198e6 (drm_gpuvm
conversion: msm_gem_close() tears down BO mappings in the GPU's single global VM on a2xx-a5xx, so phoc's composite of
a client's freed/closed window buffer reads a dead iova). Our kernel r32 carries both patches verbatim (0123/0124).
Reply-all to 2/2 with `tested-by-172617.txt` (fault storms: caught after 20 and 57 app launches without it, 0 in 180
with it; kprobe check that no BO is kept alive by the deferred teardown).
