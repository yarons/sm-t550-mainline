// SM-T550 (gt510-tweaks): hardware video decoding in Firefox ESR on the Venus decoder (ISSUES 23).
// Firefox's V4L2-M2M path (FFmpeg h264_v4l2m2m) needs DRM PRIME frames, which only the local FFmpeg
// (packages/ffmpeg 0100, LibreELEC v4l2-drmprime) returns; gt510-tweaks pins that build. Without it the forced
// path stalls on "Got non-DRM-PRIME frame from FFmpeg V4L2".
pref("media.hardware-video-decoding.force-enabled", true);
// Venus on msm8916 decodes H.264 and VP8, not VP9 or AV1. With VP9 and AV1 off for MSE, YouTube serves H.264
// (avc1, up to 1080p), which then decodes on Venus instead of all four CPU cores.
pref("media.mediasource.vp9.enabled", false);
pref("media.av1.enabled", false);
