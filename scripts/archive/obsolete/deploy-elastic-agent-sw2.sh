#!/bin/bash

set -e

echo "========================================="
echo "Elastic Agent Deployment on sw2"
echo "========================================="
echo ""

# Source the .env file for ES credentials
if [ -f "$HOME/ospf-otel-lab/.env" ]; then
    source "$HOME/ospf-otel-lab/.env"
fi

# Auto-detect Elasticsearch version
echo "Detecting Elasticsearch version..."
if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
    DETECTED_VERSION=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" 2>/dev/null | jq -r '.version.number // empty')
    if [ -n "$DETECTED_VERSION" ]; then
        echo "  Detected version: $DETECTED_VERSION"
        DEFAULT_VERSION="$DETECTED_VERSION"
    else
        echo "  Could not auto-detect version"
        DEFAULT_VERSION="8.15.3"
    fi
else
    echo "  No ES credentials found in .env"
    DEFAULT_VERSION="8.15.3"
fi

# Required information
read -p "Enter Fleet Server URL: " FLEET_URL
if [ -z "$FLEET_URL" ]; then
    echo "✗ Fleet Server URL is required"
    exit 1
fi

read -p "Enter Fleet Enrollment Token: " ENROLLMENT_TOKEN
if [ -z "$ENROLLMENT_TOKEN" ]; then
    echo "✗ Enrollment Token is required"
    exit 1
fi

read -p "Enter Elastic Stack version [default: $DEFAULT_VERSION]: " ELASTIC_VERSION
ELASTIC_VERSION=${ELASTIC_VERSION:-$DEFAULT_VERSION}

# Validate version format
if [[ ! "$ELASTIC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ Invalid version format. Use format: X.Y.Z (e.g., 8.15.3)"
    exit 1
fi

# Optional configuration
read -p "Enter container name [default: elastic-agent-sw2]: " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-"elastic-agent-sw2"}

# Verify the Docker image exists
echo ""
echo "Verifying Docker image availability..."
IMAGE_NAME="docker.elastic.co/beats/elastic-agent:${ELASTIC_VERSION}"

if docker manifest inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "  ✓ Image $IMAGE_NAME is available"
else
    echo "  ✗ Image $IMAGE_NAME not found"
    echo ""
    echo "  Checking available versions..."
    
    # Suggest similar versions
    MAJOR_MINOR=$(echo $ELASTIC_VERSION | cut -d. -f1-2)
    echo "  Common available versions for $MAJOR_MINOR.x:"
    echo "    - 8.15.3"
    echo "    - 8.15.2"
    echo "    - 8.15.1"
    echo "    - 8.15.0"
    echo "    - 8.14.3"
    echo ""
    read -p "  Enter a different version or 'q' to quit: " NEW_VERSION
    
    if [ "$NEW_VERSION" = "q" ]; then
        exit 0
    fi
    
    ELASTIC_VERSION="$NEW_VERSION"
    IMAGE_NAME="docker.elastic.co/beats/elastic-agent:${ELASTIC_VERSION}"
    
    if ! docker manifest inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "  ✗ Version $ELASTIC_VERSION also not available"
        exit 1
    fi
fi

echo ""
echo "Configuration Summary:"
echo "  Fleet URL: $FLEET_URL"
echo "  Enrollment Token: ${ENROLLMENT_TOKEN:0:20}..."
echo "  Elastic Version: $ELASTIC_VERSION"
echo "  Container Name: $CONTAINER_NAME"
echo "  Docker Image: $IMAGE_NAME"
echo ""

read -p "Proceed with deployment? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

LAB_DIR="$HOME/ospf-otel-lab"
cd "$LAB_DIR"

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠ Container $CONTAINER_NAME already exists"
    read -p "Remove and recreate? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing container..."
        docker rm -f "$CONTAINER_NAME"
    else
        echo "Deployment cancelled"
        exit 0
    fi
fi

# Create agent configuration directory
AGENT_CONFIG_DIR="$LAB_DIR/configs/elastic-agent"
mkdir -p "$AGENT_CONFIG_DIR"

# Get sw2 bridge network name
SW2_NETWORK=$(docker network ls --filter "name=clab" --format "{{.Name}}" | head -1)
if [ -z "$SW2_NETWORK" ]; then
    echo "✗ Could not find containerlab network"
    echo "  Make sure the lab is deployed first"
    exit 1
fi

echo "  Using network: $SW2_NETWORK"

# Deploy Elastic Agent container
echo ""
echo "Deploying Elastic Agent container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  --user root \
  --network "$SW2_NETWORK" \
  -e FLEET_URL="$FLEET_URL" \
  -e FLEET_ENROLLMENT_TOKEN="$ENROLLMENT_TOKEN" \
  -e FLEET_ENROLL=1 \
  -e FLEET_INSECURE=1 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro \
  -v /proc:/hostfs/proc:ro \
  -v /:/hostfs:ro \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_ADMIN \
  "$IMAGE_NAME"

if [ $? -eq 0 ]; then
    echo "✓ Container deployed successfully"
else
    echo "✗ Container deployment failed"
    exit 1
fi

# Wait for container to start
echo ""
echo "Waiting for container to start (20s)..."
sleep 20

# Check container status
STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
echo "Container status: $STATUS"

if [ "$STATUS" = "running" ]; then
    echo "✓ Container is running"
    
    # Get container network info
    MGMT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME" | head -1)
    echo "  Management IP: $MGMT_IP"
    
    # Now connect it to sw2 bridge in the topology
    echo ""
    echo "Connecting to sw2 network..."
    
    # Get sw2 container ID
    SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}")
    
    if [ -n "$SW2_CONTAINER" ]; then
        # Create a veth pair to connect agent to sw2
        AGENT_CONTAINER=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}")
        
        # Get sw2 PID
        SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
        AGENT_PID=$(docker inspect -f '{{.State.Pid}}' "$AGENT_CONTAINER")
        
        echo "  sw2 PID: $SW2_PID"
        echo "  agent PID: $AGENT_PID"
        
        # Create veth pair
        sudo ip link add "veth-agent" type veth peer name "veth-sw2"
        
        # Move one end to sw2 network namespace
        sudo ip link set "veth-sw2" netns "$SW2_PID"
        
        # Move other end to agent network namespace
        sudo ip link set "veth-agent" netns "$AGENT_PID"
        
        # Configure in sw2 (add to bridge)
        sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2" master br0
        sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2" up
        
        # Configure in agent (assign IP in 192.168.20.0/24 network)
        sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev "veth-agent"
        sudo nsenter -t "$AGENT_PID" -n ip link set "veth-agent" up
        sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1
        
        echo "  ✓ Agent connected to sw2 (192.168.20.50/24)"
    else
        echo "  ⚠ Could not find sw2 container"
        echo "  Agent is on management network only"
    fi
    
    echo ""
    echo "✓ Elastic Agent deployed"
else
    echo "⚠ Container not running"
    echo "  Check logs: docker logs $CONTAINER_NAME"
    exit 1
fi

# Display enrollment status
echo ""
echo "Checking enrollment status (waiting 15s)..."
sleep 15

LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -30)
if echo "$LOGS" | grep -qi "successfully enrolled"; then
    echo "✓ Agent successfully enrolled with Fleet"
    
    # Get agent ID if available
    AGENT_ID=$(echo "$LOGS" | grep -i "agent id" | tail -1 | awk '{print $NF}' || echo "unknown")
    echo "  Agent ID: $AGENT_ID"
elif echo "$LOGS" | grep -qi "enrolling"; then
    echo "⚠ Agent is enrolling..."
    echo "  This may take a few minutes"
    echo "  Monitor with: docker logs -f $CONTAINER_NAME"
elif echo "$LOGS" | grep -qi "error\|failed"; then
    echo "⚠ Enrollment issues detected"
    echo "  Recent logs:"
    echo "$LOGS" | grep -i "error\|failed" | tail -5 | sed 's/^/    /'
    echo ""
    echo "  Full logs: docker logs $CONTAINER_NAME"
fi

echo ""
echo "========================================="
echo "Deployment Complete"
echo "========================================="
echo ""
echo "Container Details:"
echo "  Name: $CONTAINER_NAME"
echo "  Image: $IMAGE_NAME"
echo "  Network: $SW2_NETWORK + sw2 bridge"
echo "  Management IP: $MGMT_IP"
echo "  Data Network IP: 192.168.20.50/24"
echo "  Status: $STATUS"
echo ""
echo "Network Topology:"
echo "  elastic-agent-sw2 (192.168.20.50)"
echo "    └─ sw2 bridge"
echo "         ├─ csr28 (192.168.20.1)"
echo "         └─ linux-top (192.168.20.100)"
echo ""
echo "Useful Commands:"
echo "  Check status:     docker ps --filter name=$CONTAINER_NAME"
echo "  View logs:        docker logs -f $CONTAINER_NAME"
echo "  Enter shell:      docker exec -it $CONTAINER_NAME bash"
echo "  Stop agent:       docker stop $CONTAINER_NAME"
echo "  Remove agent:     docker rm -f $CONTAINER_NAME"
echo "  Test connectivity:"
echo "    docker exec $CONTAINER_NAME ping -c 3 192.168.20.1"
echo "    docker exec $CONTAINER_NAME ping -c 3 192.168.20.100"
echo ""
echo "Fleet Management:"
echo "  Check Fleet: Kibana → Fleet → Agents"
echo "  Agent should appear as: $CONTAINER_NAME"
echo ""
