#!/bin/bash

set -e

echo "========================================="
echo "Verify and Fix Network Configuration"
echo "========================================="
echo ""

# Get PIDs
SW2_PID=$(docker inspect -f '{{.State.Pid}}' clab-ospf-network-sw2)
AGENT_PID=$(docker inspect -f '{{.State.Pid}}' elastic-agent-sw2)
CSR28_PID=$(docker inspect -f '{{.State.Pid}}' clab-ospf-network-csr28)

echo "Container PIDs:"
echo "  sw2:   $SW2_PID"
echo "  agent: $AGENT_PID"
echo "  csr28: $CSR28_PID"
echo ""

# ============================================
# CHECK AND FIX SW2
# ============================================
echo "========================================="
echo "1. Checking sw2 Bridge"
echo "========================================="
echo ""

if sudo nsenter -t $SW2_PID -n ip link show br0 >/dev/null 2>&1; then
    echo "✓ br0 exists"
    
    # Check if interfaces are in bridge
    BR0_SLAVES=$(sudo nsenter -t $SW2_PID -n ip link show master br0 2>/dev/null | grep -oP '^\d+: \K[^:@]+' || echo "")
    
    if [ -z "$BR0_SLAVES" ]; then
        echo "⚠ br0 has no interfaces, adding them..."
        for iface in eth1 eth2 eth3; do
            if sudo nsenter -t $SW2_PID -n ip link show $iface >/dev/null 2>&1; then
                echo "  Adding $iface to br0"
                sudo nsenter -t $SW2_PID -n ip link set $iface master br0
                sudo nsenter -t $SW2_PID -n ip link set $iface up
            fi
        done
    else
        echo "✓ br0 has interfaces:"
        echo "$BR0_SLAVES" | sed 's/^/    /'
    fi
else
    echo "✗ br0 does not exist, creating..."
    sudo nsenter -t $SW2_PID -n ip link add br0 type bridge
    sudo nsenter -t $SW2_PID -n ip link set br0 up
    
    for iface in eth1 eth2 eth3; do
        if sudo nsenter -t $SW2_PID -n ip link show $iface >/dev/null 2>&1; then
            echo "  Adding $iface to br0"
            sudo nsenter -t $SW2_PID -n ip link set $iface master br0
            sudo nsenter -t $SW2_PID -n ip link set $iface up
        fi
    done
    echo "✓ br0 created and configured"
fi

# ============================================
# CHECK AND FIX CSR28
# ============================================
echo ""
echo "========================================="
echo "2. Checking CSR28 eth3"
echo "========================================="
echo ""

CSR28_ETH3_IP=$(sudo nsenter -t $CSR28_PID -n ip addr show eth3 2>/dev/null | grep "inet " | awk '{print $2}' || echo "")

if [ -z "$CSR28_ETH3_IP" ]; then
    echo "⚠ CSR28 eth3 has no IP, configuring..."
    sudo nsenter -t $CSR28_PID -n ip link set eth3 up
    sudo nsenter -t $CSR28_PID -n ip addr add 192.168.20.1/24 dev eth3
    echo "✓ Configured 192.168.20.1/24 on eth3"
elif [[ "$CSR28_ETH3_IP" == "192.168.20.1/"* ]]; then
    echo "✓ CSR28 eth3: $CSR28_ETH3_IP"
else
    echo "⚠ CSR28 eth3 has wrong IP: $CSR28_ETH3_IP"
    echo "  Fixing..."
    sudo nsenter -t $CSR28_PID -n ip addr flush dev eth3
    sudo nsenter -t $CSR28_PID -n ip addr add 192.168.20.1/24 dev eth3
    sudo nsenter -t $CSR28_PID -n ip link set eth3 up
    echo "✓ Fixed to 192.168.20.1/24"
fi

# ============================================
# CHECK AND FIX AGENT
# ============================================
echo ""
echo "========================================="
echo "3. Checking Elastic Agent eth1"
echo "========================================="
echo ""

AGENT_ETH1_IP=$(sudo nsenter -t $AGENT_PID -n ip addr show eth1 2>/dev/null | grep "inet " | awk '{print $2}' || echo "")

if [ -z "$AGENT_ETH1_IP" ]; then
    echo "⚠ Agent eth1 has no IP, configuring..."
    sudo nsenter -t $AGENT_PID -n ip link set eth1 up
    sudo nsenter -t $AGENT_PID -n ip addr add 192.168.20.50/24 dev eth1
    sudo nsenter -t $AGENT_PID -n ip route add default via 192.168.20.1 2>/dev/null || true
    echo "✓ Configured 192.168.20.50/24 on eth1"
elif [[ "$AGENT_ETH1_IP" == "192.168.20.50/"* ]]; then
    echo "✓ Agent eth1: $AGENT_ETH1_IP"
else
    echo "⚠ Agent eth1 has wrong IP: $AGENT_ETH1_IP"
    echo "  Fixing..."
    sudo nsenter -t $AGENT_PID -n ip addr flush dev eth1
    sudo nsenter -t $AGENT_PID -n ip addr add 192.168.20.50/24 dev eth1
    sudo nsenter -t $AGENT_PID -n ip link set eth1 up
    sudo nsenter -t $AGENT_PID -n ip route add default via 192.168.20.1 2>/dev/null || true
    echo "✓ Fixed to 192.168.20.50/24"
fi

# Check agent default route
echo ""
echo "Agent routes:"
sudo nsenter -t $AGENT_PID -n ip route | sed 's/^/  /'

# ============================================
# VERIFY CONNECTIVITY
# ============================================
echo ""
echo "========================================="
echo "4. Testing Connectivity"
echo "========================================="
echo ""

echo "Agent -> CSR28:"
if sudo nsenter -t $AGENT_PID -n ping -c 2 -W 2 192.168.20.1 >/dev/null 2>&1; then
    echo "  ✓ Can ping 192.168.20.1"
else
    echo "  ✗ Cannot ping 192.168.20.1"
fi

echo ""
echo "CSR28 -> Agent:"
if sudo nsenter -t $CSR28_PID -n ping -c 2 -W 2 192.168.20.50 >/dev/null 2>&1; then
    echo "  ✓ Can ping 192.168.20.50"
else
    echo "  ✗ Cannot ping 192.168.20.50"
fi

# ============================================
# CONFIGURE OSPF
# ============================================
echo ""
echo "========================================="
echo "5. Configuring OSPF"
echo "========================================="
echo ""

LAB_DIR="$HOME/ospf-otel-lab"
CSR28_CONFIG="$LAB_DIR/configs/routers/csr28/frr.conf"

if [ ! -f "$CSR28_CONFIG" ]; then
    echo "✗ CSR28 config not found: $CSR28_CONFIG"
else
    if grep -q "network 192.168.20.0/24 area 0" "$CSR28_CONFIG"; then
        echo "✓ 192.168.20.0/24 already in OSPF config"
    else
        echo "Adding 192.168.20.0/24 to OSPF..."
        cp "$CSR28_CONFIG" "${CSR28_CONFIG}.backup-$(date +%s)"
        
        # Add network line after finding router ospf section
        awk '/^router ospf$/ {print; print " network 192.168.20.0/24 area 0"; next}1' "$CSR28_CONFIG" > "$CSR28_CONFIG.tmp"
        mv "$CSR28_CONFIG.tmp" "$CSR28_CONFIG"
        
        echo "✓ Updated config file"
    fi
    
    # Apply via vtysh
    echo "Applying OSPF config..."
    docker exec clab-ospf-network-csr28 vtysh -c "conf t" \
        -c "router ospf" \
        -c "network 192.168.20.0/24 area 0" \
        -c "end" \
        -c "wr" 2>/dev/null || echo "  (may already be configured)"
    
    echo "✓ OSPF configuration applied"
fi

echo ""
echo "Waiting 15s for OSPF convergence..."
sleep 15

# ============================================
# TEST FROM CSR23
# ============================================
echo ""
echo "========================================="
echo "6. Testing from CSR23"
echo "========================================="
echo ""

echo "CSR23 route to 192.168.20.50:"
docker exec clab-ospf-network-csr23 ip route get 192.168.20.50 2>/dev/null | sed 's/^/  /' || echo "  No route"

echo ""
echo "CSR23 ping to agent:"
if docker exec clab-ospf-network-csr23 ping -c 3 -W 2 192.168.20.50 >/dev/null 2>&1; then
    echo "  ✓ Can reach agent"
else
    echo "  ✗ Cannot reach agent"
fi

echo ""
echo "========================================="
echo "Network Configuration Summary"
echo "========================================="
echo ""
echo "sw2 bridge:"
sudo nsenter -t $SW2_PID -n ip link show br0 | grep "br0:" | sed 's/^/  /'
echo ""
echo "CSR28 eth3:"
sudo nsenter -t $CSR28_PID -n ip addr show eth3 | grep "inet " | sed 's/^/  /'
echo ""
echo "Agent eth1:"
sudo nsenter -t $AGENT_PID -n ip addr show eth1 | grep "inet " | sed 's/^/  /'
echo ""
echo "✓ Network verification complete"
echo ""
