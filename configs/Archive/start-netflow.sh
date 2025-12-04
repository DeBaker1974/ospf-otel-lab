#!/bin/bash
# NetFlow startup script for FRR routers

LOGSTASH_IP=${LOGSTASH_IP:-172.20.20.3}

# Install softflowd if not present
if ! command -v softflowd >/dev/null 2>&1; then
  apk add --no-cache softflowd >/dev/null 2>&1
fi

# Kill any existing instances
pkill softflowd 2>/dev/null || true
sleep 1

# Start softflowd on all data interfaces
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1; then
    softflowd -i $iface -n ${LOGSTASH_IP}:2055 -v 9 \
              -t maxlife=30 -d -p /tmp/softflowd-${iface}.pid 2>/dev/null
  fi
done

echo "NetFlow export started to ${LOGSTASH_IP}:2055"
