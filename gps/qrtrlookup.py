#!/usr/bin/env python3
# Minimal qrtr-lookup: ask the QRTR name service for all servers (QRTR_TYPE_NEW_LOOKUP) and print them.
import socket, struct
NAMES = {1: "WDS", 2: "DMS", 3: "NAS", 5: "WMS", 9: "VOICE", 10: "CAT", 11: "UIM", 12: "PBM", 16: "LOC/PDS",
         17: "SAR", 24: "TS", 25: "TMD", 26: "WDA", 34: "COEX", 41: "RFRPE", 42: "DSD", 43: "SSCTL", 47: "PDC",
         48: "SPIC?", 49: "IMSA", 52: "TEST", 64: "SLIMBUS?", 66: "SERVREG_NOTIF", 0x10: "LOC/PDS", 5376: "?"}
s = socket.socket(socket.AF_QIPCRTR, socket.SOCK_DGRAM)
s.settimeout(1.5)
node = socket.if_nametoindex if False else None
s.sendto(struct.pack("<5I", 10, 0, 0, 0, 0), (1, 0xfffffffe))  # type NEW_LOOKUP to local ns (node 1)
seen = []
try:
    while True:
        d = s.recv(64)
        t, svc, inst, nd, port = struct.unpack("<5I", d[:20])
        if t == 4 and svc:
            seen.append((svc, inst & 0xff, inst >> 8, nd, port))
except socket.timeout:
    pass
for svc, ver, inst, nd, port in sorted(seen):
    print(f"svc {svc:5d} {NAMES.get(svc, ''):14s} ver {ver:3d} inst {inst:3d} node {nd:3d} port {port}")
print(f"{len(seen)} services")
