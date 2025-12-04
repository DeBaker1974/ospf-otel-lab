#!/bin/bash

set -e

echo "========================================="
echo "Configure NetFlow on CSR23 Only (Test)"
echo "========================================="
echo ""

AGENT_IP="192.168.20.50"
AGENT_PORT="2055"
LAB_DIR="$HOME/ospf-otel-lab"
ROUTER="csr23"

# Check if agent is running
AGENT_RUNNING=$(docker ps --format '{{.Names}}' | grep "elastic-agent-sw2" || echo "")

if [ -z "$AGENT_RUNNING" ]; then
    echo "✗ Elastic Agent not running"
    echo "  Deploy first: Phase 9.5 of complete-setup-v22.sh"
    exit 1
fi

echo "✓ Elastic Agent container running"
echo ""

# Step 1: Verify agent IP is configured
echo "Step 1: Verifying agent network configuration..."
echo ""

# Test if we can exec into the agent
if ! docker exec elastic-agent-sw2 echo "test" >/dev/null 2>&1; then
    echo "  ✗ Cannot execute commands in agent container"
    echo "  Container may be starting or unhealthy"
    echo ""
    docker ps --filter "name=elastic-agent-sw2" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"
    exit 1
fi

# Get all IPs from agent
echo "  Fetching agent network interfaces..."
AGENT_IPS=$(docker exec elastic-agent-sw2 ip addr show 2>&1)

if [ $? -ne 0 ]; then
    echo "  ✗ Failed to get agent network info"
    echo "  Error: $AGENT_IPS"
    exit 1
fi

echo "  Current agent network interfaces:"
echo "$AGENT_IPS" | grep -E "^[0-9]+:|inet " | sed 's/^/    /' || echo "    (none found)"
echo ""

# Check for the specific IP
if echo "$AGENT_IPS" | grep -q "192.168.20.50"; then
    echo "  ✓ Agent has IP 192.168.20.50 configured"
    AGENT_CONFIGURED=true
else
    echo "  ✗ Agent does not have IP 192.168.20.50"
    echo ""
    AGENT_CONFIGURED=false
fi

# If agent not configured, try to configure it
if [ "$AGENT_CONFIGURED" = false ]; then
    echo "  Attempting to configure agent network..."
    echo ""
    
    # Find sw2 and agent containers
    SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}" 2>/dev/null || echo "")
    AGENT_CONTAINER=$(docker ps --filter "name=elastic-agent-sw2" --format "{{.ID}}" 2>/dev/null || echo "")
    
    if [ -z "$SW2_CONTAINER" ]; then
        echo "  ✗ Cannot find sw2 container"
        echo ""
        echo "  Available containers:"
        docker ps --format "{{.Names}}" | grep -E "clab-ospf|sw" | sed 's/^/    /'
        exit 1
    fi
    
    if [ -z "$AGENT_CONTAINER" ]; then
        echo "  ✗ Cannot find agent container"
        exit 1
    fi
    
    echo "  Found containers:"
    echo "    sw2:   $SW2_CONTAINER"
    echo "    agent: $AGENT_CONTAINER"
    echo ""
    
    # Get PIDs
    SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER" 2>/dev/null || echo "")
    AGENT_PID=$(docker inspect -f '{{.State.Pid}}' "$AGENT_CONTAINER" 2>/dev/null || echo "")
    
    if [ -z "$SW2_PID" ] || [ -z "$AGENT_PID" ]; then
        echo "  ✗ Cannot get container PIDs"
        echo "    SW2 PID: $SW2_PID"
        echo "    Agent PID: $AGENT_PID"
        exit 1
    fi
    
    echo "  Container PIDs:"
    echo "    sw2:   $SW2_PID"
    echo "    agent: $AGENT_PID"
    echo ""
    
    echo "  Creating veth pair between agent and sw2..."
    
    # Clean up old veth pair if exists
    sudo ip link del veth-agent-sw2 2>/dev/null && echo "    Removed old veth-agent-sw2" || true
    sudo nsenter -t "$SW2_PID" -n ip link del veth-sw2-agent 2>/dev/null && echo "    Removed old veth-sw2-agent" || true
    sudo nsenter -t "$AGENT_PID" -n ip link del veth-agent-sw2 2>/dev/null && echo "    Removed old veth in agent" || true
    
    sleep 2
    
    # Create veth pair
    echo "    Creating new veth pair..."
    if ! sudo ip link add "veth-agent-sw2" type veth peer name "veth-sw2-agent"; then
        echo "  ✗ Failed to create veth pair"
        exit 1
    fi
    
    echo "    Moving veth endpoints to namespaces..."
    # Move to namespaces
    sudo ip link set "veth-sw2-agent" netns "$SW2_PID" || { echo "  ✗ Failed to move veth to sw2"; exit 1; }
    sudo ip link set "veth-agent-sw2" netns "$AGENT_PID" || { echo "  ✗ Failed to move veth to agent"; exit 1; }
    
    echo "    Configuring sw2 side..."
    # Configure sw2 side
    sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" master br0 || { echo "  ✗ Failed to add to bridge"; exit 1; }
    sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" up || { echo "  ✗ Failed to bring up sw2 veth"; exit 1; }
    
    echo "    Configuring agent side..."
    # Configure agent side
    sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev "veth-agent-sw2" || { echo "  ✗ Failed to add IP"; exit 1; }
    sudo nsenter -t "$AGENT_PID" -n ip link set "veth-agent-sw2" up || { echo "  ✗ Failed to bring up agent veth"; exit 1; }
    sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 2>/dev/null || echo "    (default route already exists)"
    
    echo "  ✓ Agent network configured"
    echo ""
    
    # Verify again
    sleep 2
    if docker exec elastic-agent-sw2 ip addr show 2>/dev/null | grep -q "192.168.20.50"; then
        echo "  ✓ Verified: Agent now has IP 192.168.20.50"
    else
        echo "  ✗ Configuration failed - still no IP"
        exit 1
    fi
fi

# Test agent connectivity
echo ""
echo "  Testing agent connectivity..."
if timeout 3 docker exec elastic-agent-sw2 ping -c 2 192.168.20.1 >/dev/null 2>&1; then
    echo "  ✓ Agent can reach gateway (csr28 @ 192.168.20.1)"
else
    echo "  ⚠ Agent cannot reach gateway"
fi

# Step 2: Ensure CSR28 advertises sw2 network via OSPF
echo ""
echo "Step 2: Configuring CSR28 to advertise sw2 network..."
echo ""

CSR28_CONFIG="$LAB_DIR/configs/routers/csr28/frr.conf"

if [ ! -f "$CSR28_CONFIG" ]; then
    echo "  ✗ CSR28 config not found: $CSR28_CONFIG"
    exit 1
fi

if grep -q "network 192.168.20.0/24 area 0" "$CSR28_CONFIG"; then
    echo "  ✓ CSR28 already advertising 192.168.20.0/24"
else
    echo "  Adding 192.168.20.0/24 to CSR28 OSPF..."
    
    # Backup
    cp "$CSR28_CONFIG" "${CSR28_CONFIG}.backup-$(date +%s)"
    
    # Add network line in router ospf section
    sed -i '/^router ospf$/,/^!$/ {
        /network.*area 0$/a\
 network 192.168.20.0/24 area 0
        t
        /^!$/i\
 network 192.168.20.0/24 area 0
    }' "$CSR28_CONFIG"
    
    # Apply config via vtysh
    echo "  Applying OSPF config to CSR28..."
    docker exec clab-ospf-network-csr28 vtysh -c "configure terminal" \
        -c "router ospf" \
        -c "network 192.168.20.0/24 area 0" \
        -c "end" \
        -c "write memory" 2>/dev/null
    
    echo "  ✓ CSR28 now advertising 192.168.20.0/24 via OSPF"
fi

# Wait for OSPF to propagate
echo ""
echo "  Waiting 20s for OSPF to propagate routes..."
sleep 20

# Step 3: Verify routing from CSR23
echo ""
echo "Step 3: Verifying routing from CSR23 to agent..."
echo ""

# Check kernel routing table
echo "  Testing route from CSR23 to ${AGENT_IP}..."
ROUTE_CHECK=$(docker exec clab-ospf-network-csr23 ip route get ${AGENT_IP} 2>/dev/null || echo "No route")

echo "  Route lookup result:"
echo "$ROUTE_CHECK" | sed 's/^/    /'

if echo "$ROUTE_CHECK" | grep -q "via"; then
    NEXT_HOP=$(echo "$ROUTE_CHECK" | grep -oP 'via \K[0-9.]+' | head -1)
    echo ""
    echo "  ✓ CSR23 can route to ${AGENT_IP} via ${NEXT_HOP}"
else
    echo ""
    echo "  ⚠ No route via gateway found"
    echo ""
    echo "  Checking OSPF routes..."
    docker exec clab-ospf-network-csr23 vtysh -c "show ip route" 2>/dev/null | grep "192.168" | sed 's/^/    /' || echo "    No 192.168.x.x routes"
fi

# Test ping from CSR23 to agent
echo ""
echo "  Testing ping from CSR23 to agent..."
if timeout 5 docker exec clab-ospf-network-csr23 ping -c 3 -W 2 ${AGENT_IP} >/dev/null 2>&1; then
    echo "  ✓ CSR23 can ping agent at ${AGENT_IP}"
else
    echo "  ✗ CSR23 cannot ping agent"
    echo ""
    echo "  This may cause NetFlow to fail. Continue anyway? (y/N): "
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 4: Create and deploy NetFlow script for CSR23
echo ""
echo "Step 4: Configuring NetFlow on CSR23..."
echo ""

mkdir -p "$LAB_DIR/configs/routers/$ROUTER"

cat > "$LAB_DIR/configs/routers/$ROUTER/start-netflow.sh" << 'EOFNETFLOW'
#!/bin/bash
AGENT_IP="192.168.20.50"
AGENT_PORT="2055"

echo "Starting NetFlow Export from CSR23"
echo "Target: ${AGENT_IP}:${AGENT_PORT}"
echo ""

# Install softflowd
if ! command -v softflowd >/dev/null 2>&1; then
  echo "Installing softflowd..."
  apk add --no-cache softflowd >/dev/null 2>&1
fi

# Wait for routing
sleep 5

# Stop existing
pkill softflowd 2>/dev/null || true
sleep 2

# Start on all interfaces
STARTED=0
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1; then
    softflowd -i $iface -n ${AGENT_IP}:${AGENT_PORT} -v 5 \
              -t maxlife=60 -d -p /tmp/softflowd-${iface}.pid 2>/dev/null &
    
    if [ $? -eq 0 ]; then
      echo "✓ $iface -> ${AGENT_IP}:${AGENT_PORT}"
      STARTED=$((STARTED + 1))
    fi
  fi
done

echo ""
echo "NetFlow exporters started: $STARTED"
EOFNETFLOW

chmod +x "$LAB_DIR/configs/routers/$ROUTER/start-netflow.sh"

# Deploy to CSR23
echo "  Copying script to CSR23..."
docker cp "$LAB_DIR/configs/routers/$ROUTER/start-netflow.sh" \
          "clab-ospf-network-$ROUTER:/tmp/start-netflow.sh"

echo "  Stopping existing NetFlow..."
docker exec "clab-ospf-network-$ROUTER" pkill softflowd 2>/dev/null || true
sleep 2

echo "  Starting NetFlow..."
echo ""
docker exec "clab-ospf-network-$ROUTER" sh /tmp/start-netflow.sh
echo ""

# Verify
sleep 3
COUNT=$(docker exec "clab-ospf-network-$ROUTER" ps aux 2>/dev/null | grep -c "[s]oftflowd" || echo "0")

if [ "$COUNT" -gt 0 ]; then
    echo "✓ CSR23: $COUNT NetFlow exporters running"
else
    echo "✗ No NetFlow exporters found"
    exit 1
fi

# Generate test traffic
echo ""
echo "Generating test traffic..."
docker exec clab-ospf-network-csr23 ping -c 20 -i 0.5 10.255.0.28 >/dev/null 2>&1 &
docker exec clab-ospf-network-csr23 ping -c 20 -i 0.5 10.255.0.24 >/dev/null 2>&1 &

echo "Waiting 15s for flows to export..."
sleep 15

echo ""
echo "========================================="
echo "✓ NetFlow Configuration Complete"
echo "========================================="
echo ""
echo "Verify with:"
echo "  docker exec clab-ospf-network-csr23 ps aux | grep softflowd"
echo "  docker exec clab-ospf-network-csr23 ping -c 3 ${AGENT_IP}"
echo ""
echo "Next: Enable NetFlow integration in Fleet"
echo ""
