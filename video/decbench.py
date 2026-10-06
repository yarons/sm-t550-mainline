#!/usr/bin/env python3
# decbench.py — decode-only throughput of the test clips: hardware (v4l2h264dec) vs software (avdec_h264, 4 threads);
# wall time, frames/s and whole-system CPU busy % from /proc/stat.
import subprocess, time
def busy():
    f = open("/proc/stat").readline().split()[1:]; v = list(map(int, f)); return v[0] + v[1] + v[2] + v[5] + v[6], sum(v[:7])
for clip in ("t1280x720.mp4", "t1920x1080.mp4"):
    for dec in ("v4l2h264dec", "avdec_h264 max-threads=4"):
        p = "gst-launch-1.0 -q filesrc location=%s ! qtdemux ! h264parse ! %s ! fakesink sync=false" % (clip, dec)
        b0, t0 = busy(); w0 = time.time()
        rc = subprocess.run(p, shell=True, cwd="/home/user/vtest", capture_output=True, text=True)
        w = time.time() - w0; b1, t1 = busy()
        print("%-15s %-26s %5.1f s  %5.1f fps  CPU %3d %%  rc=%d %s" % (clip, dec, w, 600 / w, 100 * (b1 - b0) // (t1 - t0), rc.returncode, (rc.stderr.strip().splitlines() or [""])[-1][:60]))
