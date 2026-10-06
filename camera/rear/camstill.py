#!/usr/bin/env python3
# camstill.py [shots] — prototype of 5 MP stills by "reconfigure on shutter" (ISSUES 24, option 1) with the same
# GStreamer camerabin that Snapshot/aperture uses: viewfinder at 1296x972, image-capture-caps 2584x1944, so
# wrappercamerabinsrc renegotiates the source for each shot and returns to the viewfinder caps. Source = libcamerasrc
# in THIS process (run with XDG_CONFIG_HOME pointing at a libcamera config without max_output_*, e.g.
# /tmp/stills5m-conf from stills5m.sh), so PipeWire and Snapshot are not touched. Prints shutter→file time, the
# file's size and the frame's mean luma (exposure carried over or not). Needs libcamera-gstreamer.
import subprocess
import sys
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402

Gst.init(None)
shots = int(sys.argv[1]) if len(sys.argv) > 1 else 2
cb = Gst.ElementFactory.make("camerabin")
src = Gst.ElementFactory.make("wrappercamerabinsrc")
lsrc = Gst.ElementFactory.make("libcamerasrc")
if not (cb and src and lsrc):
    sys.exit("missing camerabin / wrappercamerabinsrc / libcamerasrc")
lsrc.set_property("camera-name", "/base/soc@0/cci@1b0c000/i2c-bus@0/camera@28")
src.set_property("video-source", lsrc)
cb.set_property("camera-source", src)
cb.set_property("viewfinder-sink", Gst.ElementFactory.make("fakesink"))
cb.set_property("viewfinder-caps", Gst.Caps.from_string("video/x-raw,width=1296,height=972"))
cb.set_property("image-capture-caps", Gst.Caps.from_string("video/x-raw,width=2584,height=1944"))
cb.set_property("mode", 1)  # mode-image
bus = cb.get_bus()


def wait_for(name, timeout):
    end = time.time() + timeout
    while time.time() < end:
        msg = bus.timed_pop(int(0.2 * Gst.SECOND))
        if not msg:
            continue
        if msg.type == Gst.MessageType.ERROR:
            err, dbg = msg.parse_error()
            sys.exit("ERROR %s (%s)" % (err.message, dbg))
        if msg.type == Gst.MessageType.ELEMENT and msg.get_structure() and msg.get_structure().get_name() == name:
            return msg
    return None


cb.set_state(Gst.State.PLAYING)
time.sleep(6)  # viewfinder running: AE/AWB/AF settle at 1296x972
for i in range(shots):
    path = "/tmp/camstill-%d.jpg" % i
    cb.set_property("location", path)
    t = time.time()
    cb.emit("start-capture")
    ok = wait_for("image-done", 20)
    dt = time.time() - t
    if not ok:
        print("shot %d: no image-done within 20 s" % i)
        continue
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", "-i", path, "-vf",
                            "signalstats,metadata=print:key=lavfi.signalstats.YAVG", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    size = [l for l in probe.splitlines() if "Stream #0:0" in l]
    yavg = [l.split("=")[-1] for l in probe.splitlines() if "YAVG=" in l]
    print("shot %d: %.2f s shutter→file, %s, YAVG %s" % (i, dt, size[0].split(",")[2].strip() if size else "?",
                                                           yavg[0] if yavg else "?"))
    time.sleep(3)
cb.set_state(Gst.State.NULL)
