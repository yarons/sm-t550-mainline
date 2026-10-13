#!/bin/bash
# colima-seeded-build.sh <tag> <pkg>… — build local packages in colima t290 with the local mesa r100 apks seeded into
# the edge repo for the build only (gt510-tweaks depends on mesa>=26.2.4-r100, which only the seeds provide; left in
# the repo they break ffmpeg builds: mesa-rusticl conflict). Steps, each in its own container, logs in dist/colima/:
#   seed-in-<tag>.log   copy /work/pmb/seed-removed/mesa-*26.2.4-r100.apk into the repo + re-index
#   <tag>.log           pmos-gt510.sh localpkgs-only <pkg>…   (ends with BUILD_RC=)
#   seed-out-<tag>.log  move them back to seed-removed + re-index (expect: repo 0, APKINDEX 0, seed-removed 6)
# Example: tools/colima-seeded-build.sh tweaks50 gt510-tweaks
# Start colima first if needed: `colima start t290` (that also recreates the colima-t290 docker context).
# One colima job at a time: announce it to the other sessions. Recipe from session e173ce, scripted by 36e367.
set -u
T=$1; shift
cd "$(dirname "$0")/.."
L=dist/colima
run() { docker --context colima-t290 run --rm -i --name "gt510-$1" --privileged -v /dev:/dev \
	-v "$PWD:/src:ro" -v gt510-pmos-vol:/work -v "$PWD/dist/colima:/dist" gt510-pmos "${@:2}"; }
[ -z "$(docker --context colima-t290 ps -q --filter name=gt510-)" ] || { echo "colima busy"; exit 1; }
run seedin /src/pmos-gt510.sh shell > $L/seed-in-$T.log 2>&1 <<'EOF'
R=/work/pmb/packages/edge/aarch64
n=$(ls /work/pmb/seed-removed/ | grep -c -E '^mesa-.*26\.2\.4-r100\.apk$'); echo "seed-removed count=$n"
if [ "$n" = 6 ]; then
  sudo cp /work/pmb/seed-removed/mesa-*26.2.4-r100.apk $R/ && echo copied
  pmbootstrap -y chroot -- true && pmbootstrap -y index && echo reindexed
fi
echo "in repo: $(ls $R | grep -c -E '^mesa-.*26\.2\.4-r100\.apk$')"
echo "in APKINDEX: $(tar -xzOf $R/APKINDEX.tar.gz APKINDEX 2>/dev/null | grep -c -E '^P:mesa')"
EOF
echo "RC=$?" >> $L/seed-in-$T.log
grep -E "count=|copied|reindexed|in repo|APKINDEX|RC=" $L/seed-in-$T.log
date > $L/$T.log
run "$T" /src/pmos-gt510.sh localpkgs-only "$@" </dev/null >> $L/$T.log 2>&1
echo "BUILD_RC=$?" >> $L/$T.log
tail -1 $L/$T.log
run seedout /src/pmos-gt510.sh shell > $L/seed-out-$T.log 2>&1 <<'EOF'
R=/work/pmb/packages/edge/aarch64
n=$(ls $R | grep -c -E '^mesa-.*26\.2\.4-r100\.apk$'); echo "seeds in repo=$n"
if [ "$n" = 6 ]; then
  sudo mkdir -p /work/pmb/seed-removed && sudo mv $R/mesa-*26.2.4-r100.apk /work/pmb/seed-removed/ && echo moved
  pmbootstrap -y chroot -- true && pmbootstrap -y index && echo reindexed
else
  echo "NOT 6 seeds: nothing moved"
fi
echo "in repo: $(ls $R | grep -c -E '^mesa-.*26\.2\.4-r100\.apk$')"
echo "in APKINDEX: $(tar -xzOf $R/APKINDEX.tar.gz APKINDEX 2>/dev/null | grep -c -E '^P:mesa')"
echo "seed-removed: $(ls /work/pmb/seed-removed/ | grep -c -E '^mesa-.*26\.2\.4-r100\.apk$')"
EOF
echo "RC=$?" >> $L/seed-out-$T.log
grep -E "seeds in repo|moved|reindexed|in repo|APKINDEX|seed-removed|NOT 6|RC=" $L/seed-out-$T.log
