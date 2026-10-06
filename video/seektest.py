#!/usr/bin/env python3
# seektest.py <clip> <decoder|auto> [seek_s] [manual pipeline with {clip}] — preroll a playbin3 (fakesink sync=true), issue a flushing seek like
# GstPlay/Showtime does, then PLAY and report whether the seek completes (ASYNC_DONE) and how far playback gets in 5 s.
import sys
import time

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst  # noqa: E402

Gst.init(None)
clip, dec = sys.argv[1], sys.argv[2]
seek_to = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
if dec != "auto":
    for other in ("v4l2h264dec", "avdec_h264"):
        f = Gst.ElementFactory.find(other)
        if f:
            f.set_rank(Gst.Rank.PRIMARY + 10 if other == dec else Gst.Rank.NONE)
pipe = sys.argv[4] if len(sys.argv) > 4 else None  # optional manual pipeline: {clip} is replaced by the path
p = Gst.parse_launch(pipe.replace("{clip}", clip) if pipe else
                     "playbin3 uri=file://%s audio-sink=fakesink video-sink=\"fakesink sync=true\"" % clip)
bus = p.get_bus()


def wait(types, timeout):
    msg = bus.timed_pop_filtered(int(timeout * Gst.SECOND), types | Gst.MessageType.ERROR)
    if msg and msg.type == Gst.MessageType.ERROR:
        print("ERROR", msg.parse_error()[0].message)
        sys.exit(1)
    return msg


p.set_state(Gst.State.PAUSED)
t = time.time()
print("preroll:", "ok %.2fs" % (time.time() - t) if wait(Gst.MessageType.ASYNC_DONE, 10) else "TIMEOUT")
t = time.time()
ok = p.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, int(seek_to * Gst.SECOND))
print("seek(%.1fs) sent=%s:" % (seek_to, ok), "done %.2fs" % (time.time() - t) if wait(Gst.MessageType.ASYNC_DONE, 10) else "TIMEOUT (no ASYNC_DONE in 10 s)")
p.set_state(Gst.State.PLAYING)
time.sleep(5)
pos = p.query_position(Gst.Format.TIME)
print("position after 5 s PLAYING: %s" % ("%.2f s" % (pos[1] / Gst.SECOND) if pos[0] else "unknown"))
p.set_state(Gst.State.NULL)
