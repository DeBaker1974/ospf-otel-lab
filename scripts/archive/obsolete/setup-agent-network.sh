#!/bin/bash

set -e

echo "========================================="
echo "Setup Agent Network on sw2"
echo "========================================="
echo ""

AGENT_IP="192.168.20.50"
CONTAINER_NAME="elastic-agent-sw2"
SW2_CONTAINER="clab-ospf-network-sw2"

# Check containers exist
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✗ Agent container not running"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${SW2_CONTAINER}$"; then
    echo "✗ sw2 container not running"
    exit 1
fi

echo "✓ Containers found"
echo ""

# Get container PIDs
SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
AGENT_PID=$(docker inspect -f '{{.State.Pid}}' "$CONTAINER_NAME")

echo "Container PIDs:"
echo "  sw2:   $SW2_PID"
echo "  agent: $AGENT_PID"
echo ""

# Check current agent network
echo "Current agent network (via nsenter):"
sudo nsenter -t "$AGENT_PID" -n ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
echo ""

# Check if already has 192.168.20.50
if sudo nsenter -t "$AGENT_PID" -n ip addr show 2>/dev/null | grep -q "192.168.20.50"; then
    echo "✓ Agent already has IP 192.168.20.50"
    exit 0
fi

echo "Agent does NOT have 192.168.20.50, configuring..."
echo ""

# Clean up any existing veth pairs
echo "Cleaning up old veth pairs..."
sudo ip link del veth-agent-sw2 2>/dev/null && echo "  Removed veth-agent-sw2 from host" || true
sudo nsenter -t "$SW2_PID" -n ip link del veth-sw2-agent 2>/dev/null && echo "  Removed veth-sw2-agent from sw2" || true
sudo nsenter -t "$AGENT_PID" -n ip link del veth-agent-sw2 2>/dev/null && echo "  Removed veth-agent-sw2 from agent" || true

sleep 2

# Create new veth pair
echo ""
echo "Creating veth pair..."
if ! sudo ip link add "veth-agent-sw2" type veth peer name "veth-sw2-agent"; then
    echo "✗ Failed to create veth pair"
    exit 1
fi
echo "  ✓ Created veth pair"

# Move endpoints to namespaces
echo ""
echo "Moving veth endpoints to namespaces..."
if ! sudo ip link set "veth-sw2-agent" netns "$SW2_PID"; then
    echo "✗ Failed to move veth-sw2-agent to sw2"
    exit 1
fi
echo "  ✓ Moved veth-sw2-agent to sw2"

if ! sudo ip link set "veth-agent-sw2" netns "$AGENT_PID"; then
    echo "✗ Failed to move veth-agent-sw2 to agent"
    exit 1
fi
echo "  ✓ Moved veth-agent-sw2 to agent"

# Configure sw2 side (add to bridge)
echo ""
echo "Configuring sw2 side..."
sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" master br0
sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" up
echo "  ✓ Added veth-sw2-agent to br0 bridge"

# Configure agent side (add IP)
echo ""
echo "Configuring agent side..."
sudo nsenter -t "$AGENT_PID" -n ip addr add ${AGENT_IP}/24 dev "veth-agent-sw2"
sudo nsenter -t "$AGENT_PID" -n ip link set "veth-agent-sw2" up
echo "  ✓ Configured ${AGENT_IP}/24 on veth-agent-sw2"

# Add default route via csr28
echo ""
echo "Adding default route..."
sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 2>/dev/null && echo "  ✓ Added default via 192.168.20.1" || echo "  ℹ Default route already exists"

# Verify configuration
echo ""
echo "Verifying configuration..."
sleep 2

echo ""
echo "Agent network interfaces:"
sudo nsenter -t "$AGENT_PID" -n ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'

echo ""
echo "Agent routes:"
sudo nsenter -t "$AGENT_PID" -n ip route | sed 's/^/  /'

# Test connectivity
echo ""
echo "Testing connectivity..."
if sudo nsenter -t "$AGENT_PID" -n ping -c 3 192.168.20.1 >/dev/null 2>&1; then
    echo "  ✓ Agent can ping csr28 (192.168.20.1)"
else
    echo "  ⚠ Agent cannot ping csr28"
fi

echo ""
echo "========================================="
echo "✓ Agent Network Setup Complete"
echo "========================================="
echo ""
echo "Agent is now on:"
echo "  Management: 172.20.20.8 (eth0)"
echo "  Data:       ${AGENT_IP} (veth-agent-sw2)"
echo ""
