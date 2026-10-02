#!/bin/sh
# Laptop builder is shared with the T290 Lineage builds (16 GB RAM): resume gt510 work only when no
# lineage-build* container runs. Unpauses gt510-localpkgs, then runs the queued targets.
#   gt510-after-lineage.sh "<name>:<target> [args]" ...
busy() { sudo -n docker ps --format '{{.Names}}' | grep -q '^lineage-build'; }
while busy; do sleep 60; done
sudo -n docker ps --filter status=paused --format '{{.Names}}' | grep '^gt510-' | xargs -r sudo -n docker unpause
echo "resumed $(date)"
exec "$HOME/gt510-pmos/build-host/gt510-queue.sh" "$@"
