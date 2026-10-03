# Upstream status

Bugs found during this bring-up that belong upstream, and where each one stands. Every project has its own rules
for AI-assisted contributions; the column "Rules" summarizes what applies (checked September/October 2026).

| Local patch | Problem | Upstream state | Rules |
|---|---|---|---|
| kernel 0120 | drm/msm/mdp5: video encoder enabled the INTF timing engine before flushing the CTL → first frame after every CRTC enable scanned the pre-disable pipe state (iommu faults at DPMS on, boot-time underrun). `Fixes: f9cb8d8d836e` | prepared: `upstream/0001-…patch` | kernel: `Assisted-by:`, human `Signed-off-by` |
| kernel 0122 | drm/msm/a3xx: VBIF halt waited for 6 XIN clients, A306 has 3 → runtime suspend never worked | Sam Day's patch (patchwork 756513, Reviewed-by Konrad Dybcio); Tested-by drafted | kernel |
| kernel 0123/0124 | drm/msm: handle close tore down BO mappings in the single global GPU VM of a2xx-a5xx (regression from 111fdd2198e6) → compositor read freed iovas, GPU fault storms | Dmitry Baryshkov's series 172617; Tested-by drafted | kernel |
| kernel 0114 | camss: MSM8916 VFE PIX line regression (line_num 3 → 4) | candidate | kernel |
| kernel 0116, 0118 | MAX77849 MUIC: CDP is USB data; per-group pending IRQ bits | candidates | kernel |
| kernel 0107-0111 | venus encoder on HFI 1.x | candidates | kernel |
| kernel 0113 | MSM8916 CPR + cpufreq to 1.2 GHz | coordinate with existing CPR work first | kernel |
| kernel 0121 | s6d7aa0: no backlight DCS write while the panel is disabled | candidate | kernel |
| Mesa 0100 | freedreno a3xx: FS-stage CP_LOAD_STATE SS_INDIRECT hang, staging-upload race without a hw blitter, UBO offset alignment | candidate | Mesa: the human writes all prose; `Assisted-by:` |
| GTK 0102 | import LINEAR dmabufs without an explicit modifier | candidate (narrow MR) | GTK: disclose in the MR text, no AI trailers |
| libcamera 0108 | debayer_egl: a new EGL context per stream start, never destroyed → ~8 MB GPU memory leaked per camera session | already fixed upstream (a00a4ca2 + 4501b8a1, Aug 2026); 0108 ports it to v0.7.2 | - |
| libcamera 0109 | simple pipeline: the lens stays powered at its last position after stop (VCM coil current; ~125 mA idle at the AF sweep end) → park it at the minimum in stopDevice() | candidate (libcamera-devel) | no project policy; disclose, DCO |
| libcamera 0103/0105/0106/0107 | YUV sensors via CAMSS PIX, co-sited Bayer cells, folded black level + AWB, faster contrast AF | candidates (libcamera-devel) | no project policy; disclose, DCO |
| Snapshot 0102 | QrScreenBin snapshots its child twice (breaks GtkGraphicsOffload) | open an issue first | GNOME: disclose; policy under discussion |
| phrog 0100 | no greetd session for an empty username ("password twice") | candidate (GitHub PR) | no ban; disclose |

Nothing from this work is submitted to postmarketOS/Nura: their policy does not accept contributions created
fully or partly with generative AI.
