#!/bin/bash

echo "========================================="
echo "Elastic Agent Redeploy (v8.19.0)"
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
if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_API_KEY" ] || [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
    echo "✗ Missing required environment variables in .env"
    echo ""
    echo "Required variables:"
    echo "  ES_ENDPOINT"
    echo "  ES_API_KEY"
    echo "  FLEET_URL"
    echo "  FLEET_ENROLLMENT_TOKEN"
    exit 1
fi

echo "Configuration:"
echo "  ES_ENDPOINT: $ES_ENDPOINT"
echo "  FLEET_URL: $FLEET_URL"
echo "  Agent Version: 8.19.0"
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

# Deploy agent with 8.19.0
echo ""
echo "4. Deploying Elastic Agent 8.19.0..."
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
  -e ELASTICSEARCH_HOST="$ES_ENDPOINT" \
  -e ELASTICSEARCH_API_KEY="$ES_API_KEY" \
  -v "$(pwd)/configs/elastic-agent/data:/usr/share/elastic-agent/data" \
  -v "$(pwd)/configs/elastic-agent/state:/usr/share/elastic-agent/state" \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro \
  -v /proc:/hostfs/proc:ro \
  -v /:/hostfs:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_ADMIN \
  --cap-add=NET_RAW \
  docker.elastic.co/beats/elastic-agent:8.19.0

if [ $? -eq 0 ]; then
    echo "   ✓ Container started"
else
    echo "   ✗ Failed to start container!"
    exit 1
fi

# Wait for initialization
echo ""
echo "5. Waiting for initialization (20 seconds)..."
sleep 20

# Configure network
echo ""
echo "6. Configuring network..."
docker exec elastic-agent-sw2 ip link set eth1 up 2>/dev/null || true
docker exec elastic-agent-sw2 ip addr add 192.168.20.50/24 dev eth1 2>/dev/null || true
docker exec elastic-agent-sw2 ip route add default via 192.168.20.1 2>/dev/null || true
echo "   ✓ Network configured (192.168.20.50/24)"

# Connect to sw2 bridge
echo ""
echo "7. Connecting to sw2 bridge..."
SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}")
AGENT_CONTAINER=$(docker ps --filter "name=elastic-agent-sw2" --format "{{.ID}}")

if [ -n "$SW2_CONTAINER" ] && [ -n "$AGENT_CONTAINER" ]; then
    SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
    AGENT_PID=$(docker inspect -f '{{.State.Pid}}' "$AGENT_CONTAINER")
    
    # Clean up old veth pairs
    sudo ip link del veth-agent-sw2 2>/dev/null || true
    sudo ip link del veth-sw2-agent 2>/dev/null || true
    
    # Create new veth pair
    sudo ip link add veth-agent-sw2 type veth peer name veth-sw2-agent
    
    # Move to namespaces
    sudo ip link set veth-sw2-agent netns "$SW2_PID"
    sudo ip link set veth-agent-sw2 netns "$AGENT_PID"
    
    # Configure sw2 side
    sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent master br0
    sudo nsenter -t "$SW2_PID" -n ip link set veth-sw2-agent up
    
    # Configure agent side (use the veth interface as eth1)
    sudo nsenter -t "$AGENT_PID" -n ip link set veth-agent-sw2 name eth1
    sudo nsenter -t "$AGENT_PID" -n ip link set eth1 up
    sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev eth1
    sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1
    
    echo "   ✓ Connected to sw2 bridge via veth pair"
    
    # Test connectivity
    sleep 3
    PING_RESULT=$(docker exec elastic-agent-sw2 ping -c 2 192.168.20.1 2>/dev/null | grep -c "2 received" || echo "0")
    
    if [ "$PING_RESULT" -gt 0 ]; then
        echo "   ✓ Can reach gateway (192.168.20.1)"
    else
        echo "   ⚠ Cannot reach gateway"
    fi
else
    echo "   ⚠ Could not connect to sw2 bridge (sw2 container not found)"
    echo "   Using containerlab network only"
fi

# Wait for enrollment
echo ""
echo "8. Waiting for Fleet enrollment (30 seconds)..."
sleep 30

# Check enrollment
echo ""
echo "9. Checking enrollment status..."
LOGS=$(docker logs elastic-agent-sw2 2>&1 | tail -100)

if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "   ✓ Successfully enrolled!"
    
    # Get agent status
    echo ""
    echo "   Agent Status:"
    docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | sed 's/^/   /' || echo "   (Status command unavailable)"
    
    # Get agent ID
    AGENT_ID=$(echo "$LOGS" | grep -oP 'agent.id[=:]\s*\K[a-f0-9-]+' | head -1)
    if [ -n "$AGENT_ID" ]; then
        echo ""
        echo "   Agent ID: $AGENT_ID"
    fi
    
elif echo "$LOGS" | grep -qi "enrolling"; then
    echo "   ⚠ Still enrolling..."
    echo ""
    echo "   Wait a bit more and check:"
    echo "     docker logs -f elastic-agent-sw2"
    
elif echo "$LOGS" | grep -qi "error.*enroll\|enrollment.*failed"; then
    echo "   ✗ Enrollment FAILED!"
    echo ""
    echo "   Error details:"
    echo "$LOGS" | grep -iE "error|failed|invalid|unauthorized" | tail -10 | sed 's/^/     /'
    echo ""
    echo "   Common issues:"
    echo "     1. Enrollment token expired (check Fleet → Enrollment tokens)"
    echo "     2. Fleet Server URL incorrect or unreachable"
    echo "     3. Agent version mismatch with Fleet Server"
    echo ""
    echo "   To get new token:"
    echo "     Kibana → Fleet → Enrollment tokens → Default → Copy token"
    echo "     Update .env file with new FLEET_ENROLLMENT_TOKEN"
else
    echo "   ⚠ Enrollment status unclear"
    echo ""
    echo "   Recent logs:"
    echo "$LOGS" | tail -15 | sed 's/^/     /'
fi

# Check agent version
echo ""
echo "10. Verifying agent version..."
VERSION=$(docker exec elastic-agent-sw2 elastic-agent version 2>/dev/null || echo "unknown")
echo "    Installed version: $VERSION"

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Agent Details:"
echo "  Container: elastic-agent-sw2"
echo "  Version: 8.19.0"
echo "  Status: $(docker inspect --format='{{.State.Status}}' elastic-agent-sw2 2>/dev/null || echo 'unknown')"
echo "  Network: 192.168.20.50/24"
echo "  Fleet: $FLEET_URL"
echo "  Elasticsearch: $ES_ENDPOINT"
echo ""
echo "Next Steps:"
echo "  1. Verify in Kibana: Fleet → Agents"
echo "     Look for: elastic-agent-sw2 or Agent ID above"
echo ""
echo "  2. Add NetFlow integration to this agent's policy:"
echo "     a) Click on the agent policy"
echo "     b) Add Integration → 'Network Packet Capture'"
echo "     c) Configure:"
echo "        Integration name: netflow-collector"
echo "        Type: netflow"
echo "        Host: 0.0.0.0:2055"
echo "        Internal Networks:"
echo "          - 192.168.0.0/16"
echo "          - 10.0.0.0/8"
echo "          - 172.16.0.0/12"
echo "        Protocols: netflow"
echo "     d) Save integration"
echo ""
echo "  3. Verify routers are sending NetFlow:"
echo "     ./scripts/verify-netflow.sh"
echo ""
echo "Troubleshooting:"
echo "  View logs:    docker logs -f elastic-agent-sw2"
echo "  Check status: docker exec elastic-agent-sw2 elastic-agent status"
echo "  Test network: docker exec elastic-agent-sw2 ping 192.168.20.1"
echo "  Inspect:      docker exec elastic-agent-sw2 ip addr"
echo ""

