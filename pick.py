#!/usr/bin/env python3
"""Fetch VPN Gate list, keep top-N <country> servers as .ovpn files.

Usage: pick.py <COUNTRY> <outdir>
Writes <outdir>/srv-<ip>.ovpn (up to 12, by score desc).
stdout: one IP per line, then WROTE=<n>. stderr: diagnostics.
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


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
    resp = urllib.request.urlopen(req, timeout=25)
    body = resp.read().decode("utf-8", errors="replace")
    return resp.status, body


raw = None
for url in ("http://www.vpngate.net/api/iphone/",
            "https://www.vpngate.net/api/iphone/"):
    try:
        status, body = fetch(url)
    except Exception as e:
        print(f"fetch {url} -> error: {e}", file=sys.stderr)
        continue
    print(f"fetch {url} -> HTTP {status}, {len(body)} bytes", file=sys.stderr)
    if "#HostName" in body and len(body) > 1000:
        raw = body
        break
    print(f"fetch {url} -> bad content: {body[:120]!r}", file=sys.stderr)

if raw is None:
    print("FATAL: no usable server list", file=sys.stderr)
    sys.exit(1)

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
    cands.append((score, r[1].strip(), cfg))

cands.sort(reverse=True)
for _score, ip, cfg in cands[:12]:
    with open(os.path.join(outdir, f"srv-{ip}.ovpn"), "w") as f:
        f.write(cfg)
for _score, ip, _cfg in cands[:12]:
    print(ip)
print(f"WROTE={len(cands[:12])}", flush=True)
