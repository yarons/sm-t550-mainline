#!/bin/sh
# Laptop builder: run one pmos-gt510.sh target detached in container gt510-<name>, log ~/gt510-pmos/logs/<name>.log
#   gt510-build.sh <name> <target> [args...]
name=$1; shift
mkdir -p ~/gt510-pmos/logs ~/gt510-pmos/dist
log=~/gt510-pmos/logs/$name.log
sudo -n docker rm -f "gt510-$name" >/dev/null 2>&1
nohup systemd-inhibit --what=sleep:idle --who=gt510 --why="gt510 build $name" sh -c "
	sudo -n docker run --rm --name gt510-$name --privileged -v /dev:/dev \
		-v \$HOME/gt510-pmos:/src:ro -v gt510-pmos-vol:/work -v \$HOME/gt510-pmos/dist:/dist \
		-e PMOS_PASSWORD=\"\$(cat \$HOME/gt510-pmos/.password)\" gt510-pmos /src/pmos-gt510.sh $* > $log 2>&1
	echo BUILD_RC=\$? >> $log" >/dev/null 2>&1 &
echo "started gt510-$name -> $log"
