#!/bin/bash

echo "========================================="
echo "Elastic Agent Quick Redeploy"
echo "========================================="
echo ""

cd ~/ospf-otel-lab

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

# Deploy agent (using config from ospf-network.clab.yml)
echo ""
echo "4. Deploying Elastic Agent..."
docker run -d \
  --name elastic-agent-sw2 \
  --hostname elastic-agent-sw2 \
  --user root \
  --network "$CLAB_NETWORK" \
  --restart unless-stopped \
  -e FLEET_URL="https://6ffa2ea252d64a8ca4c1951c15a00b5f.fleet.us-west2.gcp.elastic-cloud.com:443" \
  -e FLEET_ENROLLMENT_TOKEN="MW8zMGpwb0JIOUNzblFEUWdGSDI6eEVDdHBCR3R0Q3VnRmgxdVhWQkM4QQ==" \
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
  docker.elastic.co/beats/elastic-agent:8.17.0

if [ $? -eq 0 ]; then
    echo "   ✓ Container started"
else
    echo "   ✗ Failed to start container!"
    exit 1
fi

# Wait for initialization
echo ""
echo "5. Waiting for initialization (15 seconds)..."
sleep 15

# Configure network
echo ""
echo "6. Configuring network..."
docker exec elastic-agent-sw2 ip link set eth1 up
docker exec elastic-agent-sw2 ip addr add 192.168.20.50/24 dev eth1
docker exec elastic-agent-sw2 ip route add default via 192.168.20.1
echo "   ✓ Network configured (192.168.20.50/24)"

# Test connectivity
echo ""
echo "7. Testing connectivity..."
PING_RESULT=$(docker exec elastic-agent-sw2 ping -c 2 192.168.20.1 2>/dev/null | grep -c "2 received" || echo "0")

if [ "$PING_RESULT" -gt 0 ]; then
    echo "   ✓ Can reach gateway (192.168.20.1)"
else
    echo "   ⚠ Cannot reach gateway"
fi

# Connect to sw2 bridge
echo ""
echo "8. Connecting to sw2 bridge..."
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
    
    # Configure agent side
    sudo nsenter -t "$AGENT_PID" -n ip link set veth-agent-sw2 up
    sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev veth-agent-sw2
    
    echo "   ✓ Connected to sw2 bridge"
else
    echo "   ⚠ Could not connect to sw2 bridge"
fi

# Wait for enrollment
echo ""
echo "9. Waiting for Fleet enrollment (30 seconds)..."
sleep 30

# Check enrollment
echo ""
echo "10. Checking enrollment status..."
LOGS=$(docker logs elastic-agent-sw2 2>&1 | tail -50)

if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "    ✓ Successfully enrolled!"
    
    AGENT_ID=$(docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | grep -oP 'ID:\s*\K[a-f0-9-]+' || echo "")
    if [ -n "$AGENT_ID" ]; then
        echo "    Agent ID: $AGENT_ID"
    fi
    
    echo ""
    echo "    Agent Status:"
    docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | sed 's/^/    /'
    
elif echo "$LOGS" | grep -qi "enrolling"; then
    echo "    ⚠ Still enrolling..."
    echo ""
    echo "    Wait a bit more and check:"
    echo "      docker logs -f elastic-agent-sw2"
    
elif echo "$LOGS" | grep -qi "error.*enroll\|enrollment.*failed"; then
    echo "    ✗ Enrollment FAILED!"
    echo ""
    echo "    Error details:"
    echo "$LOGS" | grep -i "error\|failed" | tail -5 | sed 's/^/      /'
    echo ""
    echo "    Possible issues:"
    echo "      1. Enrollment token expired"
    echo "      2. Fleet Server unreachable"
    echo "      3. Check Fleet settings in Kibana"
else
    echo "    ⚠ Enrollment status unclear"
    echo ""
    echo "    Recent logs:"
    echo "$LOGS" | tail -10 | sed 's/^/      /'
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Agent Details:"
echo "  Container: elastic-agent-sw2"
echo "  Status: $(docker inspect --format='{{.State.Status}}' elastic-agent-sw2)"
echo "  Network: 192.168.20.50/24 (sw2 bridge)"
echo "  Fleet: https://6ffa2ea252d64a8ca4c1951c15a00b5f.fleet.us-west2.gcp.elastic-cloud.com:443"
echo ""
echo "Next Steps:"
echo "  1. Verify in Kibana: Fleet → Agents"
echo "  2. Add NetFlow integration:"
echo "     - Type: netflow"
echo "     - Host: 0.0.0.0:2055"
echo "     - Internal networks: 192.168.0.0/16, 10.0.0.0/8"
echo ""
echo "Troubleshooting:"
echo "  View logs:   docker logs -f elastic-agent-sw2"
echo "  Check status: docker exec elastic-agent-sw2 elastic-agent status"
echo "  Test network: docker exec elastic-agent-sw2 ping 192.168.20.1"
echo ""

