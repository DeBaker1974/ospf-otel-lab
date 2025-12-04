#!/bin/bash

set -e

echo "========================================="
echo "Fix Agent Interface"
echo "========================================="
echo ""

AGENT_IP="192.168.20.50"
AGENT_PID=$(docker inspect -f '{{.State.Pid}}' elastic-agent-sw2)

echo "Agent PID: $AGENT_PID"
echo ""

echo "Current agent interfaces:"
sudo nsenter -t $AGENT_PID -n ip addr show | sed 's/^/  /'
echo ""

# Check if veth-agent-sw2 exists
if ! sudo nsenter -t $AGENT_PID -n ip link show veth-agent-sw2 >/dev/null 2>&1; then
    echo "✗ veth-agent-sw2 doesn't exist"
    echo ""
    echo "The veth pair needs to be created first."
    echo "This should have been done during the previous setup."
    exit 1
fi

echo "✓ veth-agent-sw2 exists"
echo ""

# Check current state
STATE=$(sudo nsenter -t $AGENT_PID -n ip link show veth-agent-sw2 | grep -oP 'state \K\w+')
echo "Current state: $STATE"

# Bring up the interface
echo ""
echo "Configuring veth-agent-sw2..."

# Flush any existing IPs
sudo nsenter -t $AGENT_PID -n ip addr flush dev veth-agent-sw2 2>/dev/null || true

# Add IP address
echo "  Adding IP ${AGENT_IP}/24..."
sudo nsenter -t $AGENT_PID -n ip addr add ${AGENT_IP}/24 dev veth-agent-sw2

# Bring interface up
echo "  Bringing interface up..."
sudo nsenter -t $AGENT_PID -n ip link set veth-agent-sw2 up

# Add default route
echo "  Adding default route via 192.168.20.1..."
sudo nsenter -t $AGENT_PID -n ip route add default via 192.168.20.1 2>/dev/null && echo "  ✓ Route added" || echo "  ℹ Route already exists"

echo ""
echo "========================================="
echo "Verification"
echo "========================================="
echo ""

echo "Agent interfaces:"
sudo nsenter -t $AGENT_PID -n ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'

echo ""
echo "Agent routes:"
sudo nsenter -t $AGENT_PID -n ip route | sed 's/^/  /'

echo ""
echo "Testing connectivity to CSR28 (192.168.20.1)..."
if sudo nsenter -t $AGENT_PID -n ping -c 3 -W 2 192.168.20.1 >/dev/null 2>&1; then
    echo "  ✓ Can reach CSR28"
else
    echo "  ✗ Cannot reach CSR28"
    echo ""
    echo "  Checking CSR28 side..."
    CSR28_PID=$(docker inspect -f '{{.State.Pid}}' clab-ospf-network-csr28)
    echo "  CSR28 eth3:"
    sudo nsenter -t $CSR28_PID -n ip addr show eth3 | grep "inet " | sed 's/^/    /'
fi

echo ""
echo "✓ Agent interface configured"
echo ""
