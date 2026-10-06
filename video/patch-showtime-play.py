#!/usr/bin/env python3
# patch-showtime-play.py <showtime package dir> — test version of the local Showtime patch: use gtk4paintablesink
# directly unless SHOWTIME_GLSINKBIN=1 (glsinkbin's GL upload stalls hardware-decoded dmabufs on this device).
import sys

p = sys.argv[1] + "/play.py"
s = open(p).read()
old = """    # OpenGL doesn't work on macOS properly
    if paintable.props.gl_context and system != "Darwin":"""
new = """    # glsinkbin puts a GL upload in front of the paintable sink. Where GTK can import the decoder's dmabufs
    # itself (and offload them to the compositor) that path stalls or drops frames (Venus on the SM-T550),
    # so it is only used when SHOWTIME_GLSINKBIN=1 is set. OpenGL doesn't work on macOS properly.
    if os.environ.get("SHOWTIME_GLSINKBIN") == "1" and paintable.props.gl_context and system != "Darwin":"""
assert s.count(old) == 1, "play.py changed upstream"
s = s.replace(old, new)
if "\nimport os\n" not in s:
    s = s.replace("\nfrom showtime import system, utils\n", "\nimport os\n\nfrom showtime import system, utils\n", 1)
open(p, "w").write(s)
print("patched", p)
