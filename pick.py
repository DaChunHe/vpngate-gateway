#!/usr/bin/env python3
"""Fetch VPN Gate server list, keep top-N <country> servers as .ovpn files.

Usage: pick.py <COUNTRY> <outdir>
Writes <outdir>/srv-<ip>.ovpn for up to 12 servers sorted by score desc.
Prints one IP per line, then a final WROTE=<n> line.
"""
import base64
import csv
import os
import sys
import urllib.request

country, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
for f in os.listdir(outdir):
    if f.startswith("srv-") and f.endswith(".ovpn"):
        os.remove(os.path.join(outdir, f))

req = urllib.request.Request(
    "http://www.vpngate.net/api/iphone/",
    headers={"User-Agent": "curl/8"},
)
raw = urllib.request.urlopen(req, timeout=25).read().decode("utf-8", errors="replace")
rows = list(csv.reader(raw.splitlines()))
data = [r for r in rows if len(r) > 14 and not r[0].startswith(("#", "*"))]

cands = []
for r in data:
    if r[6] != country:
        continue
    try:
        cfg = base64.b64decode(r[14]).decode("utf-8", errors="replace")
    except Exception:
        continue
    try:
        score = int(r[2] or 0)
    except ValueError:
        score = 0
    cands.append((score, r[1], cfg))

cands.sort(reverse=True)
ips = []
for _score, ip, cfg in cands[:12]:
    with open(os.path.join(outdir, f"srv-{ip}.ovpn"), "w") as f:
        f.write(cfg)
    ips.append(ip)

print("\n".join(ips))
print(f"WROTE={len(ips)}", flush=True)
