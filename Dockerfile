FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      openvpn curl python3 iptables iproute2 ca-certificates \
      build-essential git \
    && rm -rf /var/lib/apt/lists \
    && git clone --depth 1 https://github.com/rofl0r/microsocks /tmp/microsocks \
    && make -C /tmp/microsocks \
    && cp /tmp/microsocks/microsocks /usr/local/bin/ \
    && rm -rf /tmp/microsocks
COPY entrypoint.sh pick.py /app/
RUN chmod +x /app/entrypoint.sh
ENTRYPOINT ["/app/entrypoint.sh"]
