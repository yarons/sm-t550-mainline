#!/bin/sh
# apktime.sh <apk args…> — run `sudo apk <args>` with every output line stamped with seconds since start, then print
# how long each "Executing …" step (scripts and triggers) took, longest first (ISSUES 31: where a gt510-tweaks upgrade
# spends its time). Example: apktime.sh add ~/r48/gt510-branding-1-r0.apk ~/r48/gt510-tweaks-1-r48.apk
#          apktime.sh fix -r gt510-tweaks        (reinstall = the same purge/trigger path as an upgrade)
# Log: /tmp/apktime.log. Run as the session user (sudo password <password>).
echo "${SUDO_PW:-147147}" | sudo -S -p "" apk -v "$@" 2>&1 | python3 -u -c '
import sys, time
t0 = time.monotonic()
for line in sys.stdin:
    print(f"{time.monotonic() - t0:7.2f} {line}", end="", flush=True)
' > /tmp/apktime.log
python3 - /tmp/apktime.log <<'EOF'
import re, sys
rows = []
for l in open(sys.argv[1]):
    m = re.match(r"^\s*([0-9.]+) (.*)", l.rstrip("\n"))  # stamps are right-aligned
    if m:
        rows.append((float(m.group(1)), m.group(2)))
steps, cur, start = [], "apk (fetch/extract/scripts before the first Executing)", 0.0
for t, text in rows:
    m = re.search(r"Executing (\S+)", text)
    if m:
        steps.append((t - start, cur)); cur, start = m.group(1), t
end = rows[-1][0] if rows else 0.0
steps.append((end - start, cur))
print(f"total {end:.1f} s")
for d, name in sorted(steps, reverse=True):
    print(f"{d:7.1f} s  {name}")
EOF
