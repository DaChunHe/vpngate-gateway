# vpngate-gateway

Docker gateway that dials volunteer [VPN Gate](http://www.vpngate.net/) nodes
and exposes an authenticated SOCKS5 proxy on port 1080. All proxied traffic
exits through the VPN tunnel (residential IP of the chosen country).

- Country filter via `COUNTRY` (default `US`), top servers by VPN Gate score.
- Kill-switch: while a tunnel is expected, the container can only egress via
  `tun0` (or to the VPN server itself) — no clearnet leaks on drop.
- Health check every 60s: verifies tunnel exit country, rotates to the next
  server after 2 consecutive failures, refetches the server list when exhausted.

## Run

```bash
cp .env.example .env   # then edit PROXY_PASS
docker compose up -d --build
docker logs -f vg-gateway
```

Needs `/dev/net/tun` and `NET_ADMIN` (see compose file). Open TCP 1080 on the
host firewall / cloud security group for whoever should reach the proxy.

## Test

```bash
curl -x socks5://USER:PASS@127.0.0.1:1080 http://ip-api.com/json/?fields=query,country,countryCode
```
