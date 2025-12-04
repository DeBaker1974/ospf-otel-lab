#!/bin/bash

echo "========================================="
echo "Elastic Agent Deploy (Correct Volumes)"
echo "========================================="
echo ""

cd ~/ospf-otel-lab
source .env

# Verify variables
if [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
    echo "✗ Missing FLEET_URL or FLEET_ENROLLMENT_TOKEN in .env"
    exit 1
fi

echo "Fleet URL: $FLEET_URL"
echo "Token: ${FLEET_ENROLLMENT_TOKEN:0:30}..."
echo ""

# Clean up
echo "1. Cleaning up old containers..."
docker stop elastic-agent-sw2 2>/dev/null || true
docker rm elastic-agent-sw2 2>/dev/null || true

# Create fresh state directory (but NOT data directory - that breaks the symlink!)
echo ""
echo "2. Preparing directories..."
mkdir -p configs/elastic-agent-state
rm -rf configs/elastic-agent-state/* 2>/dev/null || true

CLAB_NETWORK=$(docker network ls --filter "name=clab" --format "{{.Name}}" | head -1)

if [ -z "$CLAB_NETWORK" ]; then
    echo "   ✗ Containerlab network not found!"
    exit 1
fi

echo "   ✓ Network: $CLAB_NETWORK"

# Deploy WITHOUT mounting /data (which breaks the symlink)
# Only mount /state for persistence
echo ""
echo "3. Deploying Elastic Agent..."
docker run -d \
  --name elastic-agent-sw2 \
  --hostname elastic-agent-sw2 \
  --network "$CLAB_NETWORK" \
  --restart unless-stopped \
  -e FLEET_URL="$FLEET_URL" \
  -e FLEET_ENROLLMENT_TOKEN="$FLEET_ENROLLMENT_TOKEN" \
  -e FLEET_ENROLL=1 \
  -e FLEET_INSECURE=1 \
  -v "$(pwd)/configs/elastic-agent-state:/usr/share/elastic-agent/state" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro \
  -v /proc:/hostfs/proc:ro \
  -v /:/hostfs:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_RAW \
  docker.elastic.co/beats/elastic-agent:8.17.0

if [ $? -ne 0 ]; then
    echo "   ✗ Failed to start!"
    exit 1
fi

echo "   ✓ Container started"

# Wait for initialization
echo ""
echo "4. Waiting 25 seconds for initialization..."
sleep 25

# Verify it's running
if ! docker ps | grep -q elastic-agent-sw2; then
    echo "   ✗ Container not running!"
    echo ""
    echo "Logs:"
    docker logs elastic-agent-sw2 2>&1 | tail -30
    exit 1
fi

echo "   ✓ Container is running"

# Check binary
echo ""
echo "5. Verifying agent binary..."
VERSION=$(docker exec elastic-agent-sw2 elastic-agent version 2>&1)
if echo "$VERSION" | grep -q "8.17.0"; then
    echo "   ✓ Agent binary working: $VERSION"
else
    echo "   ✗ Agent binary issue:"
    echo "   $VERSION"
fi

# Check enrollment
echo ""
echo "6. Checking enrollment status..."
LOGS=$(docker logs elastic-agent-sw2 2>&1)

if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "   ✓ Successfully enrolled!"
    
    AGENT_ID=$(echo "$LOGS" | grep -oP 'agent\.id[=:]\s*\K[a-f0-9-]+' | head -1)
    if [ -n "$AGENT_ID" ]; then
        echo "   Agent ID: $AGENT_ID"
    fi
    
    echo ""
    echo "   Agent Status:"
    docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | head -20 | sed 's/^/   /'
    
elif echo "$LOGS" | grep -qi "enrolling"; then
    echo "   ⚠ Still enrolling, waiting 20 more seconds..."
    sleep 20
    
    LOGS=$(docker logs elastic-agent-sw2 2>&1)
    if echo "$LOGS" | grep -qi "successfully enrolled"; then
        echo "   ✓ Successfully enrolled!"
        
        AGENT_ID=$(echo "$LOGS" | grep -oP 'agent\.id[=:]\s*\K[a-f0-9-]+' | head -1)
        if [ -n "$AGENT_ID" ]; then
            echo "   Agent ID: $AGENT_ID"
        fi
    else
        echo "   ⚠ Still enrolling..."
        echo ""
        echo "   Recent logs:"
        echo "$LOGS" | tail -10 | sed 's/^/     /'
    fi
    
elif echo "$LOGS" | grep -qi "error.*enroll\|authentication.*failed"; then
    echo "   ✗ Enrollment failed!"
    echo ""
    echo "   Errors:"
    echo "$LOGS" | grep -iE "error|failed|invalid" | tail -10 | sed 's/^/     /'
    echo ""
    echo "   Check:"
    echo "     1. Enrollment token in Kibana Fleet UI"
    echo "     2. Fleet Server URL is reachable"
    
else
    echo "   ⚠ Status unclear"
    echo ""
    echo "   Recent logs:"
    echo "$LOGS" | tail -15 | sed 's/^/     /'
fi

# Configure network
echo ""
echo "7. Configuring network..."
AGENT_PID=$(docker inspect -f '{{.State.Pid}}' elastic-agent-sw2)

if [ -n "$AGENT_PID" ] && [ "$AGENT_PID" != "0" ]; then
    sudo nsenter -t "$AGENT_PID" -n ip link set eth1 up 2>/dev/null || true
    sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev eth1 2>/dev/null || true
    sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 2>/dev/null || true
    echo "   ✓ IP configured: 192.168.20.50/24"
    
    # Test connectivity
    sleep 2
    if docker exec elastic-agent-sw2 ping -c 2 -W 2 192.168.20.1 >/dev/null 2>&1; then
        echo "   ✓ Can reach gateway"
    else
        echo "   ⚠ Cannot reach gateway (may need sw2 bridge connection)"
    fi
else
    echo "   ⚠ Could not get PID"
fi

# Connect to sw2 bridge
echo ""
echo "8. Connecting to sw2 bridge..."
SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}")

if [ -n "$SW2_CONTAINER" ] && [ -n "$AGENT_PID" ] && [ "$AGENT_PID" != "0" ]; then
    SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
    
    if [ -n "$SW2_PID" ] && [ "$SW2_PID" != "0" ]; then
        # Clean up old pairs
        sudo ip link del veth-agent-sw2 2>/dev/null || true
        sudo ip link del veth-sw2-agent 2>/dev/null || true
        
        # Create veth pair
        sudo ip link add veth-agent-sw2 type veth peer name veth-sw2-agent
        
        # Move to namespaces
        sudo ip link set veth-sw2-agent netns "$SW2_PID"
        sudo ip link set veth-agent-sw2 netns "$AGENT_PID"
        
        # Configure sw2 side (add to bridge)
        sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent master br0
        sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent up
        
        # Configure agent side
        sudo nsenter -t "$AGENT_PID" -n ip link set veth-agent-sw2 up
        sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev veth-agent-sw2 2>/dev/null || true
        
        echo "   ✓ Connected to sw2 bridge"
        
        # Test connectivity via bridge
        sleep 2
        if docker exec elastic-agent-sw2 ping -c 2 -W 2 192.168.20.1 >/dev/null 2>&1; then
            echo "   ✓ Connectivity verified via sw2"
        fi
    fi
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Agent Details:"
echo "  Container: elastic-agent-sw2"
echo "  Version: 8.17.0"
echo "  Network: 192.168.20.50/24 (sw2 bridge)"
echo "  Fleet: $FLEET_URL"
echo ""
echo "Volume Mounts:"
echo "  State: $(pwd)/configs/elastic-agent-state"
echo "  Data: (using internal - symlink preserved)"
echo ""
echo "Next Steps:"
echo "  1. Verify in Kibana: Fleet → Agents"
echo "  2. Look for agent: elastic-agent-sw2"
echo "  3. Add NetFlow integration:"
echo "     - Type: netflow"
echo "     - Host: 0.0.0.0:2055"
echo "     - Internal Networks: 192.168.0.0/16, 10.0.0.0/8"
echo ""
echo "Troubleshooting:"
echo "  docker logs -f elastic-agent-sw2"
echo "  docker exec elastic-agent-sw2 elastic-agent status"
echo "  docker exec elastic-agent-sw2 ip addr"
echo ""

