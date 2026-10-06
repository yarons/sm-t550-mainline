#!/usr/bin/env python3
# Hardware review #8 outdoor GNSS log: watch gpsd for up to MAX s, write a line every 10 s (mode, satellites with
# signal, used, top SNRs, eph) to /tmp/gnss-outdoor.log; note time to first 2D/3D fix; stop 120 s after a 3D fix.
# Position is rounded to 3 decimals (~100 m) and stays on the tablet. Run under systemd-inhibit (no suspend).
import json, socket, sys, time
MAX = int(sys.argv[1]) if len(sys.argv) > 1 else 1500
log = open("/tmp/gnss-outdoor.log", "a", buffering=1)
def w(msg): log.write(time.strftime("%T ") + msg + "\n")
s = socket.create_connection(("127.0.0.1", 2947), timeout=5)
s.sendall(b'?WATCH={"enable":true,"json":true}\n')
f = s.makefile("r")
t0 = time.time(); last = -10; mode = 0; sats = []; tpv = {}; fix2 = fix3 = None; done_at = None
w(f"start max={MAX}s")
while time.time() - t0 < MAX and (done_at is None or time.time() < done_at):
    try:
        line = f.readline()
    except socket.timeout:
        continue
    if not line:
        w("gpsd closed"); break
    m = json.loads(line); c = m.get("class"); dt = time.time() - t0
    if c == "TPV":
        tpv = m; mode = m.get("mode", 0)
        if mode >= 2 and fix2 is None: fix2 = dt; w(f"FIRST 2D FIX after {dt:.0f}s")
        if mode >= 3 and fix3 is None:
            fix3 = dt; done_at = time.time() + 120
            w(f"FIRST 3D FIX after {dt:.0f}s lat={round(m.get('lat', 0), 3)} lon={round(m.get('lon', 0), 3)} "
              f"alt={m.get('altHAE', m.get('alt'))} eph={m.get('eph')}")
    elif c == "SKY":
        sats = m.get("satellites") or sats
    if dt - last >= 10:
        last = dt
        sig = sorted([round(x.get("ss") or 0) for x in sats if (x.get("ss") or 0) > 0], reverse=True)
        w(f"t={dt:4.0f}s mode={mode} seen={len(sig)} used={sum(1 for x in sats if x.get('used'))} "
          f"snr={sig[:8]} eph={tpv.get('eph')} gnss={sorted(set(x.get('gnssid') for x in sats if (x.get('ss') or 0) > 0))}")
w(f"END after {time.time() - t0:.0f}s first2D={fix2} first3D={fix3}")
