#!/bin/bash

echo "=================================================="
echo "  NetFlow Configuration Scanner"
echo "  Scanning all router configs and live systems"
echo "=================================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================
# 1. SCAN CONFIG FILES
# ============================================
echo "=== 1. Scanning Config Files ==="
echo ""

CONFIG_DIRS=(
    "$HOME/ospf-otel-lab/configs/routers"
    "$HOME/ospf-otel-lab/router-configs"
    "$HOME/ospf-otel-lab/scripts"
    "$HOME/ospf-otel-lab"
)

for dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Searching: $dir"
        
        # Find all config files
        find "$dir" -type f \( -name "*.conf" -o -name "*.cfg" -o -name "*.txt" -o -name "*.sh" \) 2>/dev/null | while read -r file; do
            # Search for NetFlow/flow/sflow keywords
            if grep -iE "(netflow|flow export|flow-export|ip flow|sflow|softflowd|fprobe|pmacct)" "$file" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Found in: $file"
                echo "     Content:"
                grep -iE "(netflow|flow export|flow-export|ip flow|sflow|softflowd|fprobe)" "$file" | sed 's/^/       /'
                echo ""
            fi
        done
    fi
done

echo ""

# ============================================
# 2. SCAN RUNNING ROUTERS
# ============================================
echo "=== 2. Scanning Live Router Configurations ==="
echo ""

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker ps | grep -q "clab-ospf-network-$router"; then
        echo -e "${YELLOW}Router: $router${NC}"
        
        # Check running config via vtysh
        echo "  Checking FRRouting config..."
        docker exec clab-ospf-network-$router vtysh -c "show running-config" 2>/dev/null | \
            grep -iE "(flow|netflow)" && echo "" || echo "    No NetFlow in FRR config"
        
        # Check for softflowd process
        echo "  Checking processes..."
        if docker exec clab-ospf-network-$router pgrep -a softflowd 2>/dev/null; then
            echo -e "    ${GREEN}✓ softflowd running${NC}"
            docker exec clab-ospf-network-$router ps aux | grep softflowd | grep -v grep | sed 's/^/       /'
        else
            echo "    ✗ softflowd not running"
        fi
        
        # Check for fprobe process
        if docker exec clab-ospf-network-$router pgrep -a fprobe 2>/dev/null; then
            echo -e "    ${GREEN}✓ fprobe running${NC}"
            docker exec clab-ospf-network-$router ps aux | grep fprobe | grep -v grep | sed 's/^/       /'
        fi
        
        # Check for startup scripts
        echo "  Checking startup scripts..."
        docker exec clab-ospf-network-$router ls -la /usr/local/bin/*netflow* 2>/dev/null | sed 's/^/    /' || \
            echo "    No netflow startup scripts"
        
        # Check systemd services
        echo "  Checking systemd services..."
        docker exec clab-ospf-network-$router systemctl list-units --all 2>/dev/null | \
            grep -i flow | sed 's/^/    /' || echo "    No flow-related services"
        
        # Check /etc/default configs
        echo "  Checking /etc/default configs..."
        docker exec clab-ospf-network-$router cat /etc/default/softflowd 2>/dev/null | sed 's/^/    /' || \
            echo "    No /etc/default/softflowd"
        
        echo ""
    else
        echo -e "${RED}Router: $router (not running)${NC}"
        echo ""
    fi
done

# ============================================
# 3. SCAN EXPORTED CONFIGS
# ============================================
echo "=== 3. Scanning Export Directories ==="
echo ""

EXPORT_DIRS=(
    "$HOME/ospf-otel-lab/exports"
    "$HOME/ospf-otel-lab/backups"
)

for dir in "${EXPORT_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "Checking: $dir"
        find "$dir" -type f -name "*.conf" 2>/dev/null | while read -r file; do
            if grep -iE "(netflow|flow export|softflowd)" "$file" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} Found in: $file"
                grep -iE "(netflow|flow export|softflowd)" "$file" | sed 's/^/     /'
                echo ""
            fi
        done
    fi
done

echo ""

# ============================================
# 4. NETWORK CONNECTIONS CHECK
# ============================================
echo "=== 4. Active NetFlow Connections ==="
echo ""

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker ps | grep -q "clab-ospf-network-$router"; then
        connections=$(docker exec clab-ospf-network-$router netstat -an 2>/dev/null | grep -E "(2055|9996|9995)" || \
                     docker exec clab-ospf-network-$router ss -an 2>/dev/null | grep -E "(2055|9996|9995)")
        
        if [ -n "$connections" ]; then
            echo -e "${GREEN}$router:${NC}"
            echo "$connections" | sed 's/^/  /'
            echo ""
        fi
    fi
done

# ============================================
# 5. CHECK CONTAINERLAB TOPOLOGY
# ============================================
echo "=== 5. ContainerLab Topology Configuration ==="
echo ""

if [ -f "$HOME/ospf-otel-lab/ospf-network.clab.yml" ]; then
    echo "Checking topology file..."
    if grep -iE "(netflow|flow|2055|9996)" "$HOME/ospf-otel-lab/ospf-network.clab.yml" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ NetFlow references found:${NC}"
        grep -iE "(netflow|flow|2055|9996)" "$HOME/ospf-otel-lab/ospf-network.clab.yml" | sed 's/^/  /'
    else
        echo "No NetFlow references in topology"
    fi
fi

echo ""

# ============================================
# 6. CHECK DOCKER IMAGES FOR NETFLOW TOOLS
# ============================================
echo "=== 6. NetFlow Tools in Docker Images ==="
echo ""

for router in csr23 csr24 csr25 csr26 csr27; do
    if docker ps | grep -q "clab-ospf-network-$router"; then
        echo -n "$router: "
        has_softflowd=$(docker exec clab-ospf-network-$router which softflowd 2>/dev/null)
        has_fprobe=$(docker exec clab-ospf-network-$router which fprobe 2>/dev/null)
        has_pmacct=$(docker exec clab-ospf-network-$router which pmacct 2>/dev/null)
        
        tools=()
        [ -n "$has_softflowd" ] && tools+=("softflowd")
        [ -n "$has_fprobe" ] && tools+=("fprobe")
        [ -n "$has_pmacct" ] && tools+=("pmacct")
        
        if [ ${#tools[@]} -gt 0 ]; then
            echo -e "${GREEN}✓ Installed: ${tools[*]}${NC}"
        else
            echo "No NetFlow tools installed"
        fi
    fi
done

echo ""

# ============================================
# 7. SUMMARY AND RECOMMENDATIONS
# ============================================
echo "=================================================="
echo "  SUMMARY"
echo "=================================================="
echo ""

# Count findings
config_files=$(find "$HOME/ospf-otel-lab" -type f \( -name "*.conf" -o -name "*.cfg" \) -exec grep -l "netflow\|flow export" {} \; 2>/dev/null | wc -l)
running_processes=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker ps | grep -q "clab-ospf-network-$router" && \
       docker exec clab-ospf-network-$router pgrep softflowd > /dev/null 2>&1; then
        ((running_processes++))
    fi
done

echo "Config files with NetFlow: $config_files"
echo "Routers with active NetFlow: $running_processes/7"
echo ""

if [ $config_files -gt 0 ]; then
    echo -e "${YELLOW}📋 Found existing NetFlow configurations!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the configurations found above"
    echo "  2. Extract the NetFlow settings"
    echo "  3. Apply to all routers consistently"
    echo ""
    echo "Would you like to:"
    echo "  A) Export all NetFlow configs to a single file"
    echo "  B) Apply existing config to all routers"
    echo "  C) Show detailed config for a specific router"
    echo ""
fi

if [ $running_processes -gt 0 ]; then
    echo -e "${GREEN}✓ NetFlow already running on $running_processes router(s)${NC}"
    echo ""
    echo "Get detailed status:"
    echo "  ./scripts/netflow-status.sh"
fi

echo "=================================================="
