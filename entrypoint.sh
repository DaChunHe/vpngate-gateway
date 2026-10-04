#!/bin/bash
# VPN Gate residential gateway.
# Dials volunteer VPN Gate nodes (country filter via $COUNTRY) and exposes an
# authenticated SOCKS5 proxy on :1080. All proxy traffic exits through the VPN
# tunnel; a kill-switch blocks any direct egress while a tunnel is expected.
# Health-checked every 60s, rotates to the next server on failure.
set -u

COUNTRY="${COUNTRY:-US}"
: "${PROXY_USER:?env PROXY_USER required}"
: "${PROXY_PASS:?env PROXY_PASS required}"
VG=/tmp/vg
mkdir -p "$VG"
printf 'vpn\nvpn\n' > "$VG/auth.txt"
chmod 600 "$VG/auth.txt"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

kill_switch_on() { # $1 = vpn server ip: only tun0 + that ip may egress
  iptables -F OUTPUT 2>/dev/null || true
  iptables -A OUTPUT -o lo -j ACCEPT
  iptables -A OUTPUT -o tun0 -j ACCEPT
  iptables -A OUTPUT -d "$1" -j ACCEPT
  iptables -P OUTPUT DROP
}
kill_switch_off() {
  iptables -P OUTPUT ACCEPT 2>/dev/null || true
  iptables -F OUTPUT 2>/dev/null || true
}
stop_all() {
  pkill -f "openvpn --config $VG/srv-" 2>/dev/null || true
  pkill -x microsocks 2>/dev/null || true
  sleep 1
}
check_tun() { ip link show tun0 >/dev/null 2>&1; }

exit_country() { # country code of current tunnel exit, empty on failure
  curl -s --max-time 15 --interface tun0 \
    "http://ip-api.com/json/?fields=countryCode" 2>/dev/null \
    | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('countryCode',''))
except Exception:
    print('')" 2>/dev/null
}

trap 'log "shutting down"; stop_all; kill_switch_off' EXIT INT TERM

while true; do
  stop_all
  kill_switch_off
  log "fetching VPN Gate $COUNTRY servers..."
  if ! python3 /app/pick.py "$COUNTRY" "$VG" > "$VG/ips.txt" 2>"$VG/pick.err"; then
    log "fetch failed: $(cat "$VG/pick.err" 2>/dev/null)"
    sleep 60
    continue
  fi
  mapfile -t IPS < <(grep -v '^WROTE=' "$VG/ips.txt" 2>/dev/null)
  log "got ${#IPS[@]} $COUNTRY server(s)"
  if [ "${#IPS[@]}" -eq 0 ]; then
    sleep 120
    continue
  fi

  for ip in "${IPS[@]}"; do
    ovpn="$VG/srv-${ip}.ovpn"
    [ -f "$ovpn" ] || continue
    log "dialing $ip ..."
    stop_all
    kill_switch_on "$ip"
    openvpn --config "$ovpn" \
      --auth-user-pass "$VG/auth.txt" \
      --redirect-gateway def1 \
      --daemon --writepid "$VG/ovpn.pid" --log "$VG/ovpn.log" \
      || { log "openvpn failed to start"; continue; }

    ok=0
    for _ in $(seq 1 40); do
      if check_tun; then ok=1; break; fi
      sleep 1
    done
    if [ "$ok" -ne 1 ]; then
      log "tun0 never came up for $ip"
      continue
    fi

    log "tunnel up via $ip, starting SOCKS5 :1080"
    microsocks -u "$PROXY_USER" -P "$PROXY_PASS" -p 1080 &
    sleep 2

    fails=0
    while true; do
      sleep 60
      if ! check_tun; then log "tun0 gone"; break; fi
      cc="$(exit_country)"
      if [ "$cc" = "$COUNTRY" ]; then
        fails=0
      else
        fails=$((fails + 1))
        log "healthcheck abnormal (country='$cc') fail#$fails"
        [ "$fails" -ge 2 ] && break
      fi
    done
    log "rotating to next server..."
  done
  log "server list exhausted, refetching..."
  sleep 10
done
