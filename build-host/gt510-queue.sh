#!/bin/sh
# Laptop builder: run pmos-gt510.sh targets one after another. The laptop is shared with the T290 Lineage
# builds (16 GB RAM): before EVERY job wait until no gt510-* and no lineage-build* container runs.
#   gt510-queue.sh "<name>:<target> [args]" ...     logs ~/gt510-pmos/logs/<name>.log
busy() { sudo -n docker ps --format '{{.Names}}' | grep -qE '^(gt510-|lineage-build)'; }
for job in "$@"; do
	while busy; do sleep 30; done
	name=${job%%:*}; args=${job#*:}
	log=$HOME/gt510-pmos/logs/$name.log
	echo "start $name $(date)"
	# shellcheck disable=SC2086
	sudo -n docker run --rm --name "gt510-$name" --privileged -v /dev:/dev \
		-v "$HOME/gt510-pmos:/src:ro" -v gt510-pmos-vol:/work -v "$HOME/gt510-pmos/dist:/dist" \
		-e PMOS_PASSWORD="$(cat "$HOME/gt510-pmos/.password")" gt510-pmos /src/pmos-gt510.sh $args > "$log" 2>&1
	rc=$?
	echo "BUILD_RC=$rc" >> "$log"; echo "done $name rc=$rc $(date)"
done
