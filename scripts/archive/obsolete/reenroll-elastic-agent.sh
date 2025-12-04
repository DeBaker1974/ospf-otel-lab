#!/bin/bash

set -e

echo "========================================="
echo "Elastic Agent Re-enrollment Script"
echo "========================================="
echo ""

# Change to lab directory
cd "$HOME/ospf-otel-lab"

# Load environment variables
if [ ! -f ".env" ]; then
    echo "✗ .env file not found!"
    echo "  Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

source .env

# Verify Fleet configuration
if [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
    echo "✗ Fleet not configured in .env"
    echo ""
    echo "Missing variables:"
    [ -z "$FLEET_URL" ] && echo "  - FLEET_URL"
    [ -z "$FLEET_ENROLLMENT_TOKEN" ] && echo "  - FLEET_ENROLLMENT_TOKEN"
    echo ""
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

echo "Fleet Configuration:"
echo "  URL: $FLEET_URL"
echo "  Token: ${FLEET_ENROLLMENT_TOKEN:0:30}..."
echo ""

# Check if agent container exists
AGENT_CONTAINER="clab-ospf-network-elastic-agent-sw2"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${AGENT_CONTAINER}$"; then
    echo "✗ Agent container not found: $AGENT_CONTAINER"
    echo ""
    echo "Available containers:"
    docker ps -a --filter "name=clab-ospf-network" --format "  - {{.Names}} ({{.Status}})"
    exit 1
fi

# Check container status
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$AGENT_CONTAINER")
echo "Agent container status: $CONTAINER_STATUS"

if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "  Starting container..."
    docker start "$AGENT_CONTAINER"
    sleep 10
fi

echo ""

# Step 1: Unenroll
echo "Step 1: Unenrolling agent..."
if docker exec "$AGENT_CONTAINER" elastic-agent unenroll --force 2>&1; then
    echo "  ✓ Agent unenrolled successfully"
else
    echo "  ⚠ Unenroll returned error (might already be unenrolled)"
fi

echo ""
sleep 5

# Step 2: Re-enroll
echo "Step 2: Enrolling agent with Fleet..."
ENROLL_OUTPUT=$(docker exec "$AGENT_CONTAINER" elastic-agent enroll \
    --url="$FLEET_URL" \
    --enrollment-token="$FLEET_ENROLLMENT_TOKEN" \
    --insecure \
    --force 2>&1)

if echo "$ENROLL_OUTPUT" | grep -qi "successfully enrolled\|enrolled and started"; then
    echo "  ✓ Agent enrolled successfully"
elif echo "$ENROLL_OUTPUT" | grep -qi "error"; then
    echo "  ✗ Enrollment failed"
    echo ""
    echo "Error output:"
    echo "$ENROLL_OUTPUT" | grep -i error | head -5
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify Fleet URL is reachable from container"
    echo "  2. Check enrollment token is valid in Fleet UI"
    echo "  3. Check agent logs: docker logs $AGENT_CONTAINER"
    exit 1
else
    echo "  ✓ Enrollment command completed"
fi

echo ""

# Step 3: Restart container
echo "Step 3: Restarting agent container..."
if docker restart "$AGENT_CONTAINER" >/dev/null; then
    echo "  ✓ Container restarted"
else
    echo "  ✗ Failed to restart container"
    exit 1
fi

echo ""

# Step 4: Wait for initialization
echo "Step 4: Waiting for agent initialization..."
for i in {1..6}; do
    echo -n "  Waiting... ${i}0s"
    sleep 10
    
    # Check if agent is responding
    if docker exec "$AGENT_CONTAINER" elastic-agent status >/dev/null 2>&1; then
        echo " ✓"
        break
    else
        echo ""
    fi
done

echo ""

# Step 5: Check agent status
echo "Step 5: Verifying agent status..."
echo ""

AGENT_STATUS=$(docker exec "$AGENT_CONTAINER" elastic-agent status 2>&1)

echo "$AGENT_STATUS"
echo ""

# Parse status
if echo "$AGENT_STATUS" | grep -qi "healthy"; then
    echo "✓ Agent is HEALTHY"
    AGENT_HEALTHY=true
else
    echo "⚠ Agent status unclear"
    AGENT_HEALTHY=false
fi

if echo "$AGENT_STATUS" | grep -qi "connected"; then
    echo "✓ Agent is CONNECTED to Fleet"
    AGENT_CONNECTED=true
else
    echo "⚠ Agent may not be connected to Fleet"
    AGENT_CONNECTED=false
fi

echo ""

# Step 6: Verify in Elasticsearch
echo "Step 6: Verifying enrollment in Fleet..."
sleep 5

AGENT_CHECK=$(curl -s -k \
    -H "Authorization: ApiKey $ES_API_KEY" \
    "$ES_ENDPOINT/.fleet-agents/_search" \
    -H "Content-Type: application/json" \
    -d '{
        "size": 1,
        "query": {
            "bool": {
                "must": [
                    {
                        "wildcard": {
                            "local_metadata.host.hostname": "*elastic-agent*"
                        }
                    }
                ],
                "filter": [
                    {
                        "range": {
                            "last_checkin": {
                                "gte": "now-5m"
                            }
                        }
                    }
                ]
            }
        },
        "sort": [{"last_checkin": "desc"}]
    }' 2>/dev/null)

AGENT_COUNT=$(echo "$AGENT_CHECK" | jq -r '.hits.total.value // 0')

if [ "$AGENT_COUNT" -gt 0 ]; then
    echo "✓ Agent found in Fleet registry"
    
    AGENT_INFO=$(echo "$AGENT_CHECK" | jq -r '.hits.hits[0]._source')
    AGENT_ID=$(echo "$AGENT_INFO" | jq -r '.agent.id')
    AGENT_HOSTNAME=$(echo "$AGENT_INFO" | jq -r '.local_metadata.host.hostname')
    AGENT_STATUS_ES=$(echo "$AGENT_INFO" | jq -r '.last_checkin_status')
    LAST_CHECKIN=$(echo "$AGENT_INFO" | jq -r '.last_checkin')
    
    echo ""
    echo "Agent Details:"
    echo "  ID:           $AGENT_ID"
    echo "  Hostname:     $AGENT_HOSTNAME"
    echo "  Status:       $AGENT_STATUS_ES"
    echo "  Last checkin: $LAST_CHECKIN"
else
    echo "⚠ Agent not yet visible in Fleet (may need more time)"
fi

echo ""
echo "========================================="

# Final summary
if [ "$AGENT_HEALTHY" = true ] && [ "$AGENT_CONNECTED" = true ]; then
    echo "✓✓✓ Re-enrollment SUCCESSFUL!"
    echo ""
    echo "Next steps:"
    echo "  1. Check Fleet UI: Kibana → Fleet → Agents"
    echo "  2. Agent should appear as: $AGENT_HOSTNAME"
    echo "  3. Add integrations as needed (e.g., Network Packet Capture)"
    echo ""
    echo "To add NetFlow integration:"
    echo "  1. Fleet → Agents → Select agent"
    echo "  2. Add integration → Network Packet Capture"
    echo "  3. Configure: Port=2055, Protocol=netflow"
elif [ "$AGENT_HEALTHY" = true ]; then
    echo "✓ Re-enrollment PARTIALLY SUCCESSFUL"
    echo ""
    echo "Agent is healthy but connection to Fleet unclear."
    echo "Wait 2-3 minutes and check Fleet UI."
else
    echo "⚠ Re-enrollment COMPLETED with warnings"
    echo ""
    echo "Agent may need more time to stabilize."
    echo ""
    echo "Check logs:"
    echo "  docker logs $AGENT_CONTAINER | tail -50"
fi

echo "========================================="
