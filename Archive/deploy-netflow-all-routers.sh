#!/bin/bash

AGENT_IP="192.168.20.50"
AGENT_PORT="2055"

echo "========================================="
echo "NetFlow Deployment - All Routers"
echo "========================================="
echo ""
echo "Target: 7 routers (CSR23-CSR29)"
echo "Collector: ${AGENT_IP}:${AGENT_PORT}"
echo ""

# Create the deployment script
cat > /tmp/netflow-install.sh << 'SCRIPT'
#!/bin/bash
AGENT_IP="192.168.20.50"
AGENT_PORT="2055"
ROUTER_NAME=$(hostname)

echo "[$ROUTER_NAME] Installing softflowd..."
apk add --no-cache softflowd >/dev/null 2>&1

echo "[$ROUTER_NAME] Stopping old exporters..."
pkill softflowd 2>/dev/null || true
sleep 1

echo "[$ROUTER_NAME] Starting NetFlow exporters..."
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1 && ip addr show $iface | grep -q "inet "; then
    softflowd -i $iface -n ${AGENT_IP}:${AGENT_PORT} -v 5 -t maxlife=60 -d &
    echo "  ✓ $iface"
  fi
done

sleep 2
RUNNING=$(ps aux | grep -c '[s]oftflowd')
echo "[$ROUTER_NAME] Total exporters: $RUNNING"
SCRIPT

# Deploy to all routers
ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

echo "Phase 1: Deploying NetFlow exporters..."
echo ""

for router in $ROUTERS; do
  CONTAINER="clab-ospf-network-${router}"
  docker cp /tmp/netflow-install.sh ${CONTAINER}:/tmp/
  docker exec $CONTAINER sh /tmp/netflow-install.sh
  echo ""
done

echo ""
echo "========================================="
echo "Phase 2: Deployment Summary"
echo "========================================="
echo ""

printf "%-10s %-15s %-10s %-30s\n" "Router" "Loopback IP" "Exporters" "Status"
printf "%-10s %-15s %-10s %-30s\n" "------" "-----------" "---------" "------"

TOTAL_EXPORTERS=0
for router in $ROUTERS; do
  CONTAINER="clab-ospf-network-${router}"
  
  # Get loopback IP
  LOOPBACK=$(docker exec $CONTAINER ip -4 addr show lo | grep inet | awk '{print $2}' | cut -d'/' -f1)
  
  # Count exporters
  EXPORTERS=$(docker exec $CONTAINER ps aux 2>/dev/null | grep -c '[s]oftflowd' || echo "0")
  TOTAL_EXPORTERS=$((TOTAL_EXPORTERS + EXPORTERS))
  
  # Status
  if [ "$EXPORTERS" -gt 0 ]; then
    STATUS="✓ Active"
  else
    STATUS="✗ Failed"
  fi
  
  printf "%-10s %-15s %-10s %-30s\n" "$router" "$LOOPBACK" "$EXPORTERS" "$STATUS"
done

echo ""
echo "Total exporters across all routers: $TOTAL_EXPORTERS"

echo ""
echo "========================================="
echo "Phase 3: Generating Test Traffic"
echo "========================================="
echo ""

echo "Starting inter-router traffic..."

# Generate mesh traffic between routers
docker exec -d clab-ospf-network-csr23 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.28 >/dev/null 2>&1; ping -c 1 10.255.0.24 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr24 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.29 >/dev/null 2>&1; ping -c 1 10.255.0.23 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr25 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.26 >/dev/null 2>&1; ping -c 1 10.255.0.27 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr26 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.23 >/dev/null 2>&1; ping -c 1 10.255.0.25 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr27 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.23 >/dev/null 2>&1; ping -c 1 10.255.0.28 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr28 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.23 >/dev/null 2>&1; ping -c 1 10.255.0.29 >/dev/null 2>&1; sleep 0.5; done' &
docker exec -d clab-ospf-network-csr29 sh -c 'for i in $(seq 1 60); do ping -c 1 10.255.0.24 >/dev/null 2>&1; ping -c 1 10.255.0.26 >/dev/null 2>&1; sleep 0.5; done' &

echo "  ✓ 7 traffic generators started"
echo "  ✓ Each router pinging 2 destinations"
echo "  ✓ Duration: ~30 seconds"

echo ""
echo "Waiting 35 seconds for flows to accumulate..."
sleep 35

echo ""
echo "========================================="
echo "Phase 4: Verification"
echo "========================================="
echo ""

echo "Recent agent logs (NetFlow related):"
docker logs --tail 100 elastic-agent-sw2 2>&1 | grep -i "netflow\|flow\|2055" | tail -20 || echo "  (No obvious NetFlow logs - check Kibana)"

echo ""
echo "========================================="
echo "✓ NetFlow Deployment Complete!"
echo "========================================="
echo ""
echo "Configuration Summary:"
echo "  • Routers exporting: 7 (CSR23-CSR29)"
echo "  • Total exporters: $TOTAL_EXPORTERS"
echo "  • Collector: ${AGENT_IP}:${AGENT_PORT}"
echo "  • NetFlow version: 5"
echo "  • Flow timeout: 60 seconds"
echo ""
echo "Expected Exporters per Router:"

for router in $ROUTERS; do
  LOOPBACK=$(docker exec clab-ospf-network-${router} ip -4 addr show lo 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1)
  echo "  • $router ($LOOPBACK)"
done

echo ""
echo "View in Kibana:"
echo "  1. Go to: Analytics → Discover"
echo "  2. Index pattern: netflow-*"
echo "  3. Time range: Last 15 minutes"
echo ""
echo "  Key fields to explore:"
echo "    • netflow.exporter.address (router loopback IPs)"
echo "    • source.ip / destination.ip"
echo "    • source.port / destination.port"
echo "    • network.bytes / network.packets"
echo "    • network.transport (tcp/udp/icmp)"
echo ""
echo "  Expected exporters in Kibana:"
for router in $ROUTERS; do
  LOOPBACK=$(docker exec clab-ospf-network-${router} ip -4 addr show lo 2>/dev/null | grep inet | awk '{print $2}' | cut -d'/' -f1)
  echo "    - netflow.exporter.address: $LOOPBACK"
done
echo ""
echo "Troubleshooting Commands:"
echo "  • Check exporter on router:"
echo "      docker exec clab-ospf-network-csr24 ps aux | grep softflowd"
echo ""
echo "  • Check agent listener:"
echo "      docker exec elastic-agent-sw2 netstat -ulnp | grep 2055"
echo ""
echo "  • Monitor agent logs:"
echo "      docker logs -f elastic-agent-sw2 | grep -i netflow"
echo ""
echo "  • Verify connectivity:"
echo "      docker exec clab-ospf-network-csr25 ping -c 3 192.168.20.50"
echo ""
