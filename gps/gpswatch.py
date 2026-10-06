#!/usr/bin/env python3
# Hardware review #8: connect to gpsd (pds://any), WATCH for N seconds, log TPV mode/position and SKY satellites
# (PRN, gnss, SNR, used). The PDS engine only runs while a client watches (gpsd without -n).
import json, socket, sys, time
T = int(sys.argv[1]) if len(sys.argv) > 1 else 120
s = socket.create_connection(("127.0.0.1", 2947), timeout=5)
s.sendall(b'?WATCH={"enable":true,"json":true}\n')
f = s.makefile("r")
t0 = time.time(); last_sky = 0; first_fix = None; best = 0
while time.time() - t0 < T:
    try:
        line = f.readline()
    except socket.timeout:
        continue
    if not line:
        break
    m = json.loads(line); c = m.get("class"); dt = time.time() - t0
    if c in ("VERSION", "DEVICES", "DEVICE"):
        print(f"{dt:5.1f}s {c} {json.dumps({k: m.get(k) for k in ('release', 'path', 'driver', 'activated', 'devices') if k in m})[:200]}")
    elif c == "TPV":
        mode = m.get("mode", 0)
        if mode >= 2 and first_fix is None:
            first_fix = dt
            print(f"{dt:5.1f}s FIRST FIX mode={mode} lat={m.get('lat')} lon={m.get('lon')} eph={m.get('eph')}")
    elif c == "SKY" and dt - last_sky >= 15:
        last_sky = dt
        sats = m.get("satellites") or []
        seen = [x for x in sats if (x.get("ss") or 0) > 0]
        best = max([best] + [x.get("ss") or 0 for x in sats])
        print(f"{dt:5.1f}s SKY listed={len(sats)} with_signal={len(seen)} used={sum(1 for x in sats if x.get('used'))} "
              f"top_ss={sorted([round(x.get('ss') or 0) for x in sats], reverse=True)[:6]}")
print(f"END {T}s first_fix={first_fix} best_ss={best}")
