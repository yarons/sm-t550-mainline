# SM-T550 (Adreno 306): GTK4 apps render on the GPU.
# Overrides GSK_RENDERER=cairo from soc-qcom-msm8916-gpu's adreno-a306-quirks.sh
# (sorted after it; it must stay in the login environment, since gnome-session
# re-imports it into the user service manager). On cairo every frame is
# composited on the CPU (Snapshot's viewfinder alone took a whole core).
# GTK's GL renderer used to need two freedreno workarounds (nouboopt, inorder);
# the local mesa (packages/mesa 0100) fixes both bugs.
# Delete this file (and log in again) to go back to cairo.
export GSK_RENDERER=gl
