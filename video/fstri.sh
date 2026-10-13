#!/bin/sh
# fstri.sh <tag> ['VAR=value …'] — ISSUES 23 black triangle: PAGE= (default fstest.html: 1080p clip; fsyt.html: YouTube
# embed; needs an http origin, URL=http://127.0.0.1:8765/fsyt.html with `python3 -m http.server -b 127.0.0.1 8765` in
# ~/vtest) in DOM fullscreen requested by the page,
# through fxshot.sh in the bench profile with hardware decoding, full-resolution scanout shots (/tmp/fxshot-<tag>-N.png).
# The optional second argument becomes Firefox's extra environment (e.g. FD_MESA_DEBUG=nobin).
T=$1; export FXENV="$2"
export EXTRA='user_pref("full-screen-api.allow-trusted-requests-only", false);
user_pref("full-screen-api.warning.timeout", 0);
user_pref("full-screen-api.transition-duration.enter", "0 0");
user_pref("full-screen-api.transition-duration.leave", "0 0");
user_pref("media.autoplay.default", 0);'
SCALE=768 WAIT=${WAIT:-25} sh /home/user/vtest/fxshot.sh ${URL:-file:///home/user/vtest/${PAGE:-fstest.html}} "$T" 1 3
