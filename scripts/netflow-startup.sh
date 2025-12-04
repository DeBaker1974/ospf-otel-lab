#!/bin/bash
# NetFlow Exporter Startup Script
AGENT_IP="172.20.20.50"
AGENT_PORT="2055"
ROUTER_NAME=$(hostname)
# Wait for network interfaces to be ready
sleep 15
# Install softflowd
apk add --no-cache softflowd >/dev/null 2>&1
# Start exporters on all data plane interfaces
STARTED=0
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1 && ip addr show $iface | grep -q "inet "; then
    softflowd -i $iface -n ${AGENT_IP}:${AGENT_PORT} -v 5 -t maxlife=60 -d
    STARTED=$((STARTED + 1))
  fi
done
logger -t netflow "[${ROUTER_NAME}] Started ${STARTED} NetFlow exporters"
echo "[${ROUTER_NAME}] Started ${STARTED} NetFlow exporters" >> /var/log/netflow.log
