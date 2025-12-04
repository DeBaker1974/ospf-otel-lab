#!/bin/bash

set -e

echo "========================================="
echo "Setup NetFlow on CSR23"
echo "========================================="
echo ""

LAB_DIR="$HOME/ospf-otel-lab"
AGENT_IP="192.168.20.50"
AGENT_PORT="2055"

# First verify network is OK
echo "Verifying network configuration..."
if ! docker exec clab-ospf-network-csr23 ping -c 2 ${AGENT_IP} >/dev/null 2>&1; then
    echo "✗ CSR23 cannot reach agent at ${AGENT_IP}"
    echo ""
    echo "Run network verification first:"
    echo "  ./scripts/verify-and-fix-network.sh"
    exit 1
fi

echo "✓ CSR23 can reach agent"
echo ""

# Create NetFlow script
echo "Creating NetFlow startup script..."

mkdir -p "$LAB_DIR/configs/routers/csr23"

cat > "$LAB_DIR/configs/routers/csr23/start-netflow.sh" << 'EOF'
#!/bin/bash
AGENT_IP="192.168.20.50"
AGENT_PORT="2055"

echo "Starting NetFlow Export from CSR23"
echo "Target: ${AGENT_IP}:${AGENT_PORT}"

# Install softflowd
if ! command -v softflowd >/dev/null 2>&1; then
  apk add --no-cache softflowd >/dev/null 2>&1
fi

# Stop existing
pkill softflowd 2>/dev/null || true
sleep 2

# Start on all data interfaces
STARTED=0
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1; then
    softflowd -i $iface -n ${AGENT_IP}:${AGENT_PORT} -v 5 -t maxlife=60 -d &
    echo "✓ NetFlow: $iface -> ${AGENT_IP}:${AGENT_PORT}"
    STARTED=$((STARTED + 1))
  fi
done

echo ""
echo "Active exporters: $STARTED"
EOF

chmod +x "$LAB_DIR/configs/routers/csr23/start-netflow.sh"

# Deploy to CSR23
echo "Deploying to CSR23..."
docker cp "$LAB_DIR/configs/routers/csr23/start-netflow.sh" clab-ospf-network-csr23:/tmp/

echo "Starting NetFlow..."
docker exec clab-ospf-network-csr23 sh /tmp/start-netflow.sh

echo ""
sleep 3

# Verify
COUNT=$(docker exec clab-ospf-network-csr23 ps aux | grep -c '[s]oftflowd' || echo "0")

if [ "$COUNT" -gt 0 ]; then
    echo "✓ NetFlow running: $COUNT exporters"
    echo ""
    docker exec clab-ospf-network-csr23 ps aux | grep '[s]oftflowd' | sed 's/^/  /'
else
    echo "✗ No NetFlow exporters found"
    exit 1
fi

# Generate test traffic
echo ""
echo "Generating test traffic..."
docker exec clab-ospf-network-csr23 ping -c 50 -i 0.2 10.255.0.28 >/dev/null 2>&1 &
docker exec clab-ospf-network-csr23 ping -c 50 -i 0.2 10.255.0.24 >/dev/null 2>&1 &

echo "Waiting 20s for flows to accumulate..."
sleep 20

echo ""
echo "========================================="
echo "✓ NetFlow Setup Complete"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Router:      CSR23"
echo "  Destination: ${AGENT_IP}:${AGENT_PORT}"
echo "  Protocol:    NetFlow v5"
echo "  Exporters:   $COUNT interfaces"
echo ""
echo "Next Steps:"
echo "  1. Enable NetFlow integration in Fleet:"
echo "     Kibana → Fleet → Integrations → Add NetFlow"
echo "     Host: 0.0.0.0, Port: 2055, Internal: true"
echo ""
echo "  2. Monitor agent logs:"
echo "     docker logs -f elastic-agent-sw2 | grep -i netflow"
echo ""
echo "  3. Check for flows in Kibana:"
echo "     Analytics → Discover → netflow-*"
echo ""
