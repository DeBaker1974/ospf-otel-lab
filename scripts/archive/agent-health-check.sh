#!/bin/bash

echo "========================================="
echo "Elastic Agent Health Check"
echo "========================================="
echo ""

AGENT="clab-ospf-network-elastic-agent-sw2"

# 1. Container Status
echo "1. Container Status:"
STATUS=$(docker inspect --format='{{.State.Status}}' "$AGENT" 2>/dev/null)
RESTARTS=$(docker inspect --format='{{.RestartCount}}' "$AGENT" 2>/dev/null)
echo "   Status: $STATUS"
echo "   Restart count: $RESTARTS"
echo ""

# 2. Network Connectivity
echo "2. Network Connectivity:"
echo -n "   eth0 (management): "
docker exec "$AGENT" ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' || echo "N/A"
echo -n "   eth1 (data): "
docker exec "$AGENT" ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' || echo "N/A"

echo -n "   Gateway ping: "
if docker exec "$AGENT" ping -c 1 -W 2 192.168.20.1 >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

echo -n "   DNS resolution: "
if docker exec "$AGENT" nslookup google.com >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi
echo ""

# 3. Fleet Configuration
echo "3. Fleet Configuration:"
source ~/ospf-otel-lab/.env
echo "   FLEET_URL: $FLEET_URL"
echo "   TOKEN: ${FLEET_ENROLLMENT_TOKEN:0:30}..."

FLEET_HOST=$(echo "$FLEET_URL" | sed 's|https://||;s|http://||;s|:.*||')
echo -n "   Fleet host DNS: "
if docker exec "$AGENT" nslookup "$FLEET_HOST" >/dev/null 2>&1; then
    echo "✓ OK"
else
    echo "✗ FAILED"
fi

echo -n "   Fleet connectivity: "
FLEET_TEST=$(docker exec "$AGENT" curl -k -s -o /dev/null -w "%{http_code}" "$FLEET_URL/api/status" 2>/dev/null)
if [ "$FLEET_TEST" = "200" ] || [ "$FLEET_TEST" = "401" ]; then
    echo "✓ OK (HTTP $FLEET_TEST)"
else
    echo "✗ FAILED (HTTP $FLEET_TEST)"
fi
echo ""

# 4. Agent Status
echo "4. Agent Internal Status:"
docker exec "$AGENT" elastic-agent status 2>&1 | head -20
echo ""

# 5. Resource Usage
echo "5. Resource Usage:"
docker stats "$AGENT" --no-stream --format "   CPU: {{.CPUPerc}}\t Memory: {{.MemUsage}}"
echo ""

# 6. Recent Errors
echo "6. Recent Errors (last 10):"
docker logs "$AGENT" 2>&1 | grep -i "error\|fatal\|warn" | tail -10
echo ""

# 7. State File Check
echo "7. State File Status:"
docker exec "$AGENT" ls -lh /usr/share/elastic-agent/state/data/ 2>/dev/null | tail -5
echo ""

echo "========================================="
echo "Recommendations:"
echo ""

# Analyze issues
LOGS=$(docker logs "$AGENT" 2>&1 | tail -50)

if [ "$RESTARTS" -gt 5 ]; then
    echo "  ⚠ High restart count ($RESTARTS) - Container is crashlooping"
    echo "    → Run: docker logs $AGENT | grep -i error | tail -20"
fi

if echo "$LOGS" | grep -qi "state.enc.*authentication failed"; then
    echo "  ⚠ Corrupted state file detected"
    echo "    → Run: docker exec $AGENT rm -rf /usr/share/elastic-agent/state/data/*"
    echo "    → Then: docker restart $AGENT"
fi

if echo "$LOGS" | grep -qi "connection refused\|timeout"; then
    echo "  ⚠ Fleet connection issues"
    echo "    → Check FLEET_URL is accessible: curl -k $FLEET_URL/api/status"
    echo "    → Verify enrollment token is valid in Fleet UI"
fi

if echo "$LOGS" | grep -qi "401\|unauthorized"; then
    echo "  ⚠ Authentication failure"
    echo "    → Enrollment token may be expired or invalid"
    echo "    → Re-run: ./scripts/reenroll-elastic-agent.sh"
fi

if docker exec "$AGENT" ping -c 1 -W 2 192.168.20.1 >/dev/null 2>&1; then
    :
else
    echo "  ⚠ Network connectivity issue"
    echo "    → Check if eth1 is configured: docker exec $AGENT ip addr show eth1"
    echo "    → Check sw2 bridge: docker exec clab-ospf-network-sw2 ip link"
fi

echo ""
echo "To monitor live:"
echo "  docker logs -f $AGENT"
