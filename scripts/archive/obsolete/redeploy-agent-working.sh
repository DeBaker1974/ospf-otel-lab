#!/bin/bash

echo "========================================="
echo "Elastic Agent Redeploy (v8.17.0)"
echo "========================================="
echo ""

cd ~/ospf-otel-lab

# Source environment variables
if [ ! -f .env ]; then
    echo "✗ .env file not found!"
    exit 1
fi

source .env

# Verify required variables
echo "Checking environment variables..."
MISSING=0

if [ -z "$ES_ENDPOINT" ]; then
    echo "  ✗ ES_ENDPOINT not set"
    MISSING=1
else
    echo "  ✓ ES_ENDPOINT: $ES_ENDPOINT"
fi

if [ -z "$ES_API_KEY" ]; then
    echo "  ✗ ES_API_KEY not set"
    MISSING=1
else
    echo "  ✓ ES_API_KEY: ${ES_API_KEY:0:20}..."
fi

if [ -z "$FLEET_URL" ]; then
    echo "  ✗ FLEET_URL not set"
    MISSING=1
else
    echo "  ✓ FLEET_URL: $FLEET_URL"
fi

if [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
    echo "  ✗ FLEET_ENROLLMENT_TOKEN not set"
    MISSING=1
else
    echo "  ✓ FLEET_ENROLLMENT_TOKEN: ${FLEET_ENROLLMENT_TOKEN:0:20}..."
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "✗ Missing required environment variables!"
    exit 1
fi

echo ""

# Stop and remove old agent
echo "1. Removing old agent container..."
docker stop elastic-agent-sw2 2>/dev/null || true
docker rm elastic-agent-sw2 2>/dev/null || true
echo "   ✓ Old container removed"

# Clean enrollment data
echo ""
echo "2. Cleaning old enrollment data..."
rm -rf configs/elastic-agent/data/* 2>/dev/null || true
rm -rf configs/elastic-agent/state/* 2>/dev/null || true
mkdir -p configs/elastic-agent/data
mkdir -p configs/elastic-agent/state
echo "   ✓ Enrollment data cleaned"

# Get network
echo ""
echo "3. Finding containerlab network..."
CLAB_NETWORK=$(docker network ls --filter "name=clab" --format "{{.Name}}" | head -1)

if [ -z "$CLAB_NETWORK" ]; then
    echo "   ✗ Containerlab network not found!"
    echo "   Deploy lab first: sudo clab deploy -t ospf-network.clab.yml"
    exit 1
fi

echo "   ✓ Network: $CLAB_NETWORK"

# Pull the image first to ensure it's correct
echo ""
echo "4. Pulling Elastic Agent image..."
docker pull docker.elastic.co/beats/elastic-agent:8.17.0

# Deploy agent - simpler approach without custom config mount
echo ""
echo "5. Deploying Elastic Agent 8.17.0..."
docker run -d \
  --name elastic-agent-sw2 \
  --hostname elastic-agent-sw2 \
  --user root \
  --network "$CLAB_NETWORK" \
  --restart unless-stopped \
  -e FLEET_URL="$FLEET_URL" \
  -e FLEET_ENROLLMENT_TOKEN="$FLEET_ENROLLMENT_TOKEN" \
  -e FLEET_ENROLL=1 \
  -e FLEET_INSECURE=1 \
  -v "$(pwd)/configs/elastic-agent/data:/usr/share/elastic-agent/data" \
  -v "$(pwd)/configs/elastic-agent/state:/usr/share/elastic-agent/state" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro \
  -v /proc:/hostfs/proc:ro \
  -v /:/hostfs:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_RAW \
  docker.elastic.co/beats/elastic-agent:8.17.0

if [ $? -ne 0 ]; then
    echo "   ✗ Failed to start container!"
    exit 1
fi

CONTAINER_ID=$(docker ps -q -f name=elastic-agent-sw2)
echo "   ✓ Container started: $CONTAINER_ID"

# Wait for container to be ready
echo ""
echo "6. Waiting for container initialization (30 seconds)..."
sleep 30

# Verify elastic-agent binary exists
echo ""
echo "7. Verifying agent binary..."
if docker exec elastic-agent-sw2 which elastic-agent >/dev/null 2>&1; then
    echo "   ✓ elastic-agent binary found"
    VERSION=$(docker exec elastic-agent-sw2 elastic-agent version 2>/dev/null | head -1)
    echo "   Version: $VERSION"
else
    echo "   ✗ elastic-agent binary NOT found!"
    echo ""
    echo "   Container details:"
    docker exec elastic-agent-sw2 ls -la /usr/share/elastic-agent/ 2>&1 | sed 's/^/     /'
    exit 1
fi

# Configure network
echo ""
echo "8. Configuring network..."

# Get container PID for network namespace operations
AGENT_PID=$(docker inspect -f '{{.State.Pid}}' elastic-agent-sw2)

if [ -n "$AGENT_PID" ] && [ "$AGENT_PID" != "0" ]; then
    # Add IP to eth1 using nsenter (more reliable)
    sudo nsenter -t "$AGENT_PID" -n ip link set eth1 up 2>/dev/null || true
    sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev eth1 2>/dev/null || true
    sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 2>/dev/null || true
    echo "   ✓ Network configured (192.168.20.50/24)"
else
    echo "   ⚠ Could not get container PID"
fi

# Connect to sw2 bridge
echo ""
echo "9. Connecting to sw2 bridge..."
SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}")

if [ -n "$SW2_CONTAINER" ] && [ -n "$AGENT_PID" ] && [ "$AGENT_PID" != "0" ]; then
    SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
    
    if [ -n "$SW2_PID" ] && [ "$SW2_PID" != "0" ]; then
        # Clean up old veth pairs
        sudo ip link del veth-agent-sw2 2>/dev/null || true
        sudo ip link del veth-sw2-agent 2>/dev/null || true
        
        # Create new veth pair
        sudo ip link add veth-agent-sw2 type veth peer name veth-sw2-agent
        
        # Move to namespaces
        sudo ip link set veth-sw2-agent netns "$SW2_PID"
        sudo ip link set veth-agent-sw2 netns "$AGENT_PID"
        
        # Configure sw2 side
        sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent master br0 2>/dev/null || true
        sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent up
        
        # Configure agent side
        sudo nsenter -t "$AGENT_PID" -n ip link set veth-agent-sw2 up
        sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev veth-agent-sw2 2>/dev/null || true
        
        echo "   ✓ Connected to sw2 bridge"
        
        # Test connectivity
        sleep 3
        PING_RESULT=$(docker exec elastic-agent-sw2 ping -c 2 -W 2 192.168.20.1 2>/dev/null | grep -c "2 received" || echo "0")
        
        if [ "$PING_RESULT" -gt 0 ]; then
            echo "   ✓ Can reach gateway (192.168.20.1)"
        else
            echo "   ⚠ Cannot reach gateway (routing may still be configuring)"
        fi
    else
        echo "   ⚠ Could not get sw2 PID"
    fi
else
    echo "   ⚠ sw2 container not found or agent PID invalid"
fi

# Wait for enrollment
echo ""
echo "10. Waiting for Fleet enrollment (40 seconds)..."
sleep 40

# Check enrollment
echo ""
echo "11. Checking enrollment status..."

# Check if agent is running
if docker exec elastic-agent-sw2 ps aux 2>/dev/null | grep -q "[e]lastic-agent"; then
    echo "    ✓ elastic-agent process is running"
else
    echo "    ⚠ elastic-agent process not found"
fi

# Get logs
LOGS=$(docker logs elastic-agent-sw2 2>&1 | tail -100)

if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "    ✓ Successfully enrolled!"
    
    # Get agent status
    echo ""
    echo "    Agent Status:"
    docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | sed 's/^/    /' || echo "    (Status command failed)"
    
    # Get agent ID
    AGENT_ID=$(echo "$LOGS" | grep -oP '(?:agent\.id[=:]\s*|agent-id:\s*)\K[a-f0-9-]+' | head -1)
    if [ -n "$AGENT_ID" ]; then
        echo ""
        echo "    Agent ID: $AGENT_ID"
    fi
    
elif echo "$LOGS" | grep -qi "enrolling"; then
    echo "    ⚠ Still enrolling..."
    echo ""
    echo "    Recent logs:"
    echo "$LOGS" | tail -10 | sed 's/^/      /'
    
elif echo "$LOGS" | grep -qi "error.*enroll\|enrollment.*failed"; then
    echo "    ✗ Enrollment FAILED!"
    echo ""
    echo "    Error details:"
    echo "$LOGS" | grep -iE "error|failed|invalid|unauthorized" | tail -10 | sed 's/^/      /'
    
else
    echo "    ⚠ Enrollment status unclear"
    echo ""
    echo "    Recent logs:"
    echo "$LOGS" | tail -15 | sed 's/^/      /'
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Agent Details:"
echo "  Container: elastic-agent-sw2 ($CONTAINER_ID)"
echo "  Version: 8.17.0"
echo "  Status: $(docker inspect --format='{{.State.Status}}' elastic-agent-sw2 2>/dev/null)"
echo "  Network: 192.168.20.50/24"
echo "  Fleet: $FLEET_URL"
echo ""
echo "Next Steps:"
echo "  1. Verify in Kibana: Fleet → Agents"
echo "  2. Add NetFlow integration:"
echo "     - Go to agent policy"
echo "     - Add Integration → 'Network Packet Capture'"
echo "     - Type: netflow, Host: 0.0.0.0:2055"
echo "     - Internal Networks: 192.168.0.0/16, 10.0.0.0/8"
echo ""
echo "Troubleshooting:"
echo "  docker logs -f elastic-agent-sw2"
echo "  docker exec elastic-agent-sw2 elastic-agent status"
echo "  docker exec elastic-agent-sw2 ip addr"
echo ""

