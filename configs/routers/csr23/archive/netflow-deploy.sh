#!/bin/bash
AGENT_IP="192.168.20.50"
AGENT_PORT="2055"

echo "Installing softflowd..."
apk add --no-cache softflowd >/dev/null 2>&1

echo "Stopping any existing exporters..."
pkill softflowd 2>/dev/null || true
sleep 2

echo ""
echo "Starting NetFlow exporters..."
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1; then
    softflowd -i $iface -n ${AGENT_IP}:${AGENT_PORT} -v 5 -t maxlife=60 -d &
    echo "  ✓ $iface -> ${AGENT_IP}:${AGENT_PORT}"
  fi
done

sleep 2
echo ""
echo "Active exporters:"
ps aux | grep '[s]oftflowd' | awk '{print "  " $0}'
