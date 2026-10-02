#!/bin/sh
# fbstate.sh <tag> — dump DRM framebuffers/state/mdp5 kms debugfs to ~/fbstate-<tag>.txt (root via sudo)
T=$1; O=$HOME/fbstate-$T.txt
echo "${SUDO_PW:-147147}" | sudo -S -p '' sh -c 'D=/sys/kernel/debug/dri/0; for f in state framebuffer kms; do echo "### $f"; cat $D/$f; done; echo "### gem"; cat $D/gem | head -80' > "$O" 2>&1
echo wrote "$O"
