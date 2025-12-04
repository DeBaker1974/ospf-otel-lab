#!/bin/bash

echo "========================================="
echo "Elastic Agent Redeploy with Config"
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
    echo ""
    echo "Add to .env file:"
    echo "  ES_ENDPOINT=https://your-cluster.es.region.cloud.es.io:443"
    echo "  ES_API_KEY=your-api-key"
    echo "  FLEET_URL=https://your-fleet.fleet.region.cloud.es.io:443"
    echo "  FLEET_ENROLLMENT_TOKEN=your-enrollment-token"
    exit 1
fi

echo ""

# Verify config file exists
if [ ! -f configs/elastic-agent.yml ]; then
    echo "✗ configs/elastic-agent.yml not found!"
    echo "Creating default config..."
    
    mkdir -p configs
    cat > configs/elastic-agent.yml << 'AGENTCFG'
id: elastic-agent-sw2

outputs:
  default:
    type: elasticsearch
    hosts:
      - '${ES_ENDPOINT}'
    api_key: '${ES_API_KEY}'

fleet:
  enabled: true
  hosts:
    - '${FLEET_URL}'
  enrollment_token: '${FLEET_ENROLLMENT_TOKEN}'

agent:
  monitoring:
    enabled: true
    use_output: default
    logs: true
    metrics: true
AGENTCFG
    
    echo "  ✓ Created configs/elastic-agent.yml"
fi

# Stop and remove old agent
echo ""
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

# Deploy agent with config mounted
echo ""
echo "4. Deploying Elastic Agent 8.19.0 with custom config..."
docker run -d \
  --name elastic-agent-sw2 \
  --hostname elastic-agent-sw2 \
  --user root \
  --network "$CLAB_NETWORK" \
  --restart unless-stopped \
  -e ES_ENDPOINT="$ES_ENDPOINT" \
  -e ES_API_KEY="$ES_API_KEY" \
  -e FLEET_URL="$FLEET_URL" \
  -e FLEET_ENROLLMENT_TOKEN="$FLEET_ENROLLMENT_TOKEN" \
  -e FLEET_ENROLL=1 \
  -e FLEET_INSECURE=1 \
  -v "$(pwd)/configs/elastic-agent.yml:/usr/share/elastic-agent/elastic-agent.yml:ro" \
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
    docker logs elastic-agent-sw2 2>&1 | tail -20
    exit 1
fi

# Wait for initialization
echo ""
echo "5. Waiting for initialization (20 seconds)..."
sleep 20

# Check if config was loaded
echo ""
echo "6. Verifying config file..."
CONFIG_CHECK=$(docker exec elastic-agent-sw2 cat /usr/share/elastic-agent/elastic-agent.yml 2>/dev/null | grep -c "elastic-agent-sw2")

if [ "$CONFIG_CHECK" -gt 0 ]; then
    echo "   ✓ Config file mounted successfully"
else
    echo "   ⚠ Config file may not be mounted correctly"
fi

# Configure network
echo ""
echo "7. Configuring network..."
docker exec elastic-agent-sw2 ip link set eth1 up 2>/dev/null || true
docker exec elastic-agent-sw2 ip addr add 192.168.20.50/24 dev eth1 2>/dev/null || true
docker exec elastic-agent-sw2 ip route add default via 192.168.20.1 2>/dev/null || true
echo "   ✓ Network configured (192.168.20.50/24)"

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
    sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 dev veth-agent-sw2 || true
    
    echo "   ✓ Connected to sw2 bridge"
    
    # Test connectivity
    sleep 3
    PING_RESULT=$(docker exec elastic-agent-sw2 ping -c 2 192.168.20.1 2>/dev/null | grep -c "2 received" || echo "0")
    
    if [ "$PING_RESULT" -gt 0 ]; then
        echo "   ✓ Can reach gateway (192.168.20.1)"
    else
        echo "   ⚠ Cannot reach gateway"
    fi
else
    echo "   ⚠ sw2 container not found, using containerlab network only"
fi

# Wait for enrollment
echo ""
echo "9. Waiting for Fleet enrollment (40 seconds)..."
sleep 40

# Check enrollment
echo ""
echo "10. Checking enrollment status..."
LOGS=$(docker logs elastic-agent-sw2 2>&1)

if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "    ✓ Successfully enrolled!"
    
    # Get agent status
    echo ""
    echo "    Agent Status:"
    docker exec elastic-agent-sw2 elastic-agent status 2>/dev/null | sed 's/^/    /' || echo "    (Status unavailable)"
    
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
    echo "$LOGS" | tail -15 | sed 's/^/      /'
    echo ""
    echo "    Continue watching:"
    echo "      docker logs -f elastic-agent-sw2"
    
elif echo "$LOGS" | grep -qi "error.*enroll\|enrollment.*failed\|authentication.*failed"; then
    echo "    ✗ Enrollment FAILED!"
    echo ""
    echo "    Error details:"
    echo "$LOGS" | grep -iE "error|failed|invalid|unauthorized|authentication" | tail -10 | sed 's/^/      /'
    echo ""
    echo "    Common fixes:"
    echo "      1. Get new enrollment token: Kibana → Fleet → Enrollment tokens"
    echo "      2. Update .env: FLEET_ENROLLMENT_TOKEN=new-token"
    echo "      3. Re-run this script"
else
    echo "    ⚠ Enrollment status unclear"
    echo ""
    echo "    Recent logs:"
    echo "$LOGS" | tail -20 | sed 's/^/      /'
fi

# Check agent version
echo ""
echo "11. Agent version:"
VERSION=$(docker exec elastic-agent-sw2 elastic-agent version 2>/dev/null | head -1)
echo "    $VERSION"

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Config file: $(pwd)/configs/elastic-agent.yml"
echo "  Container: elastic-agent-sw2"
echo "  Version: 8.19.0"
echo "  Network: 192.168.20.50/24"
echo "  Fleet: $FLEET_URL"
echo "  Elasticsearch: $ES_ENDPOINT"
echo ""
echo "Environment variables passed:"
echo "  ES_ENDPOINT ✓"
echo "  ES_API_KEY ✓"
echo "  FLEET_URL ✓"
echo "  FLEET_ENROLLMENT_TOKEN ✓"
echo ""
echo "Next Steps:"
echo "  1. Check Fleet UI: Kibana → Fleet → Agents"
echo "  2. Look for agent: elastic-agent-sw2"
echo "  3. Add NetFlow integration (see below)"
echo ""
echo "NetFlow Integration Setup:"
echo "  a) Go to agent's policy"
echo "  b) Add Integration → 'Network Packet Capture'"
echo "  c) Configure:"
echo "     - Type: netflow"
echo "     - Host: 0.0.0.0:2055"
echo "     - Internal Networks: 192.168.0.0/16, 10.0.0.0/8"
echo "  d) Save and deploy"
echo ""
echo "Troubleshooting:"
echo "  Logs:   docker logs -f elastic-agent-sw2"
echo "  Status: docker exec elastic-agent-sw2 elastic-agent status"
echo "  Config: docker exec elastic-agent-sw2 cat /usr/share/elastic-agent/elastic-agent.yml"
echo ""

