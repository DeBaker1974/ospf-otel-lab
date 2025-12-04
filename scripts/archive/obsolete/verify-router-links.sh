#!/bin/bash

echo "=============================================="
echo "Router Link Verification Script"
echo "Topology: 7 FRR Routers - OSPF Area 0"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define expected topology from ospf-network.clab.yml
declare -A ROUTER_LINKS=(
    ["csr23"]="eth1:10.0.7.0/31:csr26 eth2:10.0.2.0/31:csr28 eth3:10.0.3.0/31:csr24 eth4:10.0.5.0/31:csr25 eth5:10.0.11.0/31:csr27"
    ["csr24"]="eth1:10.0.1.0/31:csr28 eth2:10.0.9.0/31:csr29 eth3:10.0.3.1/31:csr23 eth4:10.0.4.0/31:csr26 eth5:10.0.6.0/31:csr25"
    ["csr25"]="eth1:10.0.5.1/31:csr23 eth2:10.0.6.1/31:csr24 eth3:10.0.8.0/31:csr26 eth4:10.0.12.0/31:csr27 eth5:192.168.10.2/24:sw"
    ["csr26"]="eth1:10.0.10.0/31:csr29 eth2:10.0.7.1/31:csr23 eth3:10.0.4.1/31:csr24 eth4:10.0.8.1/31:csr25 eth5:192.168.10.3/24:sw"
    ["csr27"]="eth1:10.0.11.1/31:csr23 eth2:10.0.12.1/31:csr25"
    ["csr28"]="eth1:10.0.1.1/31:csr24 eth2:10.0.2.1/31:csr23 eth3:192.168.20.1/24:sw2"
    ["csr29"]="eth1:10.0.9.1/31:csr24 eth2:10.0.10.1/31:csr26"
)

# Define expected OSPF neighbors per router
declare -A EXPECTED_OSPF_NEIGHBORS=(
    ["csr23"]="5"  # csr26, csr28, csr24, csr25, csr27
    ["csr24"]="5"  # csr28, csr29, csr23, csr26, csr25
    ["csr25"]="4"  # csr23, csr24, csr26, csr27
    ["csr26"]="4"  # csr29, csr23, csr24, csr25
    ["csr27"]="2"  # csr23, csr25
    ["csr28"]="2"  # csr24, csr23
    ["csr29"]="2"  # csr24, csr26
)

# Track statistics
TOTAL_LINKS=0
UP_LINKS=0
DOWN_LINKS=0
TOTAL_OSPF=0
FULL_OSPF=0

# ============================================
# Function: Check Interface Status
# ============================================
check_interface() {
    local router=$1
    local interface=$2
    local expected_ip=$3
    local neighbor=$4
    local container="clab-ospf-network-$router"
    
    # Check if interface exists and is UP
    local iface_status=$(docker exec "$container" ip link show "$interface" 2>/dev/null | grep -o "state [A-Z]*" | awk '{print $2}')
    
    if [ -z "$iface_status" ]; then
        echo -e "    ${RED}✗${NC} $interface: DOES NOT EXIST"
        return 1
    fi
    
    if [ "$iface_status" != "UP" ]; then
        echo -e "    ${RED}✗${NC} $interface: DOWN (state: $iface_status)"
        return 1
    fi
    
    # Check IP address
    local actual_ip=$(docker exec "$container" ip addr show "$interface" 2>/dev/null | grep -oP 'inet \K[\d./]+')
    
    if [ -z "$actual_ip" ]; then
        echo -e "    ${YELLOW}⚠${NC} $interface: UP but NO IP (expected: $expected_ip)"
        return 1
    fi
    
    if [ "$actual_ip" != "$expected_ip" ]; then
        echo -e "    ${YELLOW}⚠${NC} $interface: UP, IP mismatch (got: $actual_ip, expected: $expected_ip)"
        return 1
    fi
    
    # If it's a router-to-router link, check reachability
    if [[ "$neighbor" =~ ^csr[0-9]+ ]]; then
        local remote_ip=$(echo "$expected_ip" | sed 's/\.0\/31/\.1/' | sed 's/\.1\/31/\.0/')
        remote_ip=$(echo "$remote_ip" | cut -d'/' -f1)
        
        # Adjust for correct peer IP
        if [[ "$expected_ip" =~ \.0/31$ ]]; then
            remote_ip=$(echo "$expected_ip" | sed 's/\.0\/31/\.1/')
        else
            remote_ip=$(echo "$expected_ip" | sed 's/\.1\/31/\.0/')
        fi
        remote_ip=$(echo "$remote_ip" | cut -d'/' -f1)
        
        # Ping test
        if docker exec "$container" ping -c 1 -W 2 "$remote_ip" >/dev/null 2>&1; then
            echo -e "    ${GREEN}✓${NC} $interface ($actual_ip) → $neighbor ($remote_ip) ${GREEN}REACHABLE${NC}"
            return 0
        else
            echo -e "    ${YELLOW}⚠${NC} $interface ($actual_ip) → $neighbor ($remote_ip) ${YELLOW}NO PING${NC}"
            return 1
        fi
    else
        # Non-router link (to switch)
        echo -e "    ${GREEN}✓${NC} $interface ($actual_ip) → $neighbor"
        return 0
    fi
}

# ============================================
# Function: Check OSPF Neighbors
# ============================================
check_ospf_neighbors() {
    local router=$1
    local expected=$2
    local container="clab-ospf-network-$router"
    
    echo ""
    echo -e "  ${BLUE}OSPF Neighbor Status:${NC}"
    
    # Get OSPF neighbor output
    local ospf_output=$(docker exec "$container" vtysh -c "show ip ospf neighbor" 2>/dev/null)
    
    if [ -z "$ospf_output" ]; then
        echo -e "    ${RED}✗${NC} OSPF daemon not responding"
        return 1
    fi
    
    # Count neighbors in Full state
    local full_count=$(echo "$ospf_output" | grep -c "Full" || echo "0")
    
    # Parse and display each neighbor
    echo "$ospf_output" | grep "Full" | while read -r line; do
        local neighbor_id=$(echo "$line" | awk '{print $1}')
        local state=$(echo "$line" | awk '{print $3}')
        local address=$(echo "$line" | awk '{print $6}')
        local interface=$(echo "$line" | awk '{print $7}')
        
        # Map router ID to router name
        local neighbor_name=$(echo "$neighbor_id" | sed 's/10.255.0./csr/')
        
        echo -e "    ${GREEN}✓${NC} Neighbor $neighbor_name ($neighbor_id) - $state - $address via $interface"
    done
    
    # Check if count matches expected
    if [ "$full_count" -eq "$expected" ]; then
        echo ""
        echo -e "    ${GREEN}✓${NC} All $expected OSPF neighbors in Full state"
        return 0
    elif [ "$full_count" -gt 0 ]; then
        echo ""
        echo -e "    ${YELLOW}⚠${NC} Only $full_count/$expected OSPF neighbors in Full state"
        return 1
    else
        echo ""
        echo -e "    ${RED}✗${NC} No OSPF neighbors in Full state (expected: $expected)"
        return 1
    fi
}

# ============================================
# Main Verification Loop
# ============================================

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}$router${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    container="clab-ospf-network-$router"
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        echo -e "  ${RED}✗ Container not running${NC}"
        continue
    fi
    
    echo -e "  ${BLUE}Physical Interface Status:${NC}"
    
    # Parse links for this router
    links="${ROUTER_LINKS[$router]}"
    router_total=0
    router_up=0
    
    for link in $links; do
        IFS=':' read -r interface ip neighbor <<< "$link"
        
        TOTAL_LINKS=$((TOTAL_LINKS + 1))
        router_total=$((router_total + 1))
        
        if check_interface "$router" "$interface" "$ip" "$neighbor"; then
            UP_LINKS=$((UP_LINKS + 1))
            router_up=$((router_up + 1))
        else
            DOWN_LINKS=$((DOWN_LINKS + 1))
        fi
    done
    
    # Check OSPF neighbors
    expected_neighbors="${EXPECTED_OSPF_NEIGHBORS[$router]}"
    TOTAL_OSPF=$((TOTAL_OSPF + expected_neighbors))
    
    if check_ospf_neighbors "$router" "$expected_neighbors"; then
        FULL_OSPF=$((FULL_OSPF + expected_neighbors))
    else
        # Count actual Full neighbors
        actual_full=$(docker exec "$container" vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full" || echo "0")
        FULL_OSPF=$((FULL_OSPF + actual_full))
    fi
    
    # Router summary
    echo ""
    echo -e "  ${BLUE}Summary for $router:${NC}"
    echo "    Physical links: $router_up/$router_total UP"
    echo "    OSPF neighbors: $(docker exec "$container" vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full" || echo "0")/$expected_neighbors Full"
done

# ============================================
# Overall Summary
# ============================================

echo ""
echo "=============================================="
echo "Overall Network Summary"
echo "=============================================="
echo ""

echo "Physical Links:"
echo "  Total configured: $TOTAL_LINKS"
echo "  UP: $UP_LINKS"
echo "  DOWN: $DOWN_LINKS"

if [ "$UP_LINKS" -eq "$TOTAL_LINKS" ]; then
    echo -e "  Status: ${GREEN}✓ ALL LINKS UP${NC}"
elif [ "$UP_LINKS" -ge "$((TOTAL_LINKS * 80 / 100))" ]; then
    echo -e "  Status: ${YELLOW}⚠ MOSTLY UP ($(( UP_LINKS * 100 / TOTAL_LINKS ))%)${NC}"
else
    echo -e "  Status: ${RED}✗ MULTIPLE LINKS DOWN${NC}"
fi

echo ""
echo "OSPF Adjacencies:"
echo "  Expected: $TOTAL_OSPF"
echo "  Full state: $FULL_OSPF"

if [ "$FULL_OSPF" -eq "$TOTAL_OSPF" ]; then
    echo -e "  Status: ${GREEN}✓ FULLY CONVERGED${NC}"
elif [ "$FULL_OSPF" -ge "$((TOTAL_OSPF * 80 / 100))" ]; then
    echo -e "  Status: ${YELLOW}⚠ MOSTLY CONVERGED ($(( FULL_OSPF * 100 / TOTAL_OSPF ))%)${NC}"
else
    echo -e "  Status: ${RED}✗ CONVERGENCE ISSUES${NC}"
fi

echo ""
echo "Per-Router Breakdown:"
printf "  %-8s %-15s %-20s\n" "Router" "Links" "OSPF Neighbors"
echo "  ───────────────────────────────────────────────"

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-$router"
    
    # Count links
    links="${ROUTER_LINKS[$router]}"
    link_count=$(echo "$links" | wc -w)
    
    # Count OSPF neighbors
    ospf_count=$(docker exec "$container" vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full" || echo "0")
    expected="${EXPECTED_OSPF_NEIGHBORS[$router]}"
    
    # Status indicators
    if [ "$ospf_count" -eq "$expected" ]; then
        ospf_status="${GREEN}✓${NC}"
    else
        ospf_status="${YELLOW}⚠${NC}"
    fi
    
    printf "  %-8s %-15s %-20s\n" "$router" "$link_count interfaces" "$ospf_status $ospf_count/$expected Full"
done

echo ""
echo "=============================================="
echo "Troubleshooting Commands"
echo "=============================================="
echo ""
echo "Check specific router:"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip ospf neighbor'"
echo "  docker exec clab-ospf-network-csr28 ip -br addr"
echo "  docker exec clab-ospf-network-csr28 ip -br link"
echo ""
echo "Check interface details:"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show interface'"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip ospf interface'"
echo ""
echo "Check OSPF routing:"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip route ospf'"
echo "  docker exec clab-ospf-network-csr28 vtysh -c 'show ip ospf database'"
echo ""
echo "Ping between routers:"
echo "  docker exec clab-ospf-network-csr28 ping -c 3 10.0.2.0"
echo ""

# Exit code based on status
if [ "$UP_LINKS" -eq "$TOTAL_LINKS" ] && [ "$FULL_OSPF" -eq "$TOTAL_OSPF" ]; then
    exit 0
elif [ "$UP_LINKS" -ge "$((TOTAL_LINKS * 80 / 100))" ] && [ "$FULL_OSPF" -ge "$((TOTAL_OSPF * 80 / 100))" ]; then
    exit 1
else
    exit 2
fi
