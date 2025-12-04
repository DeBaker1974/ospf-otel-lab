#!/bin/bash

# audit-menu.sh - Check which menu options are functional

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LAB_DIR="$HOME/ospf-otel-lab"
ENV_FILE="$LAB_DIR/.env"

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}   Menu Options Audit Report${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# Load environment if exists
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    ES_CONFIGURED="YES"
else
    ES_CONFIGURED="NO"
fi

# Track results
WORKING=0
BROKEN=0
MISSING=0

# Helper functions
check_container() {
    if docker ps --filter "name=$1" --filter "status=running" -q &>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_script() {
    if [ -f "$LAB_DIR/scripts/$1" ] && [ -x "$LAB_DIR/scripts/$1" ]; then
        return 0
    else
        return 1
    fi
}

test_command() {
    eval "$1" &>/dev/null
    return $?
}

report_status() {
    local option="$1"
    local description="$2"
    local status="$3"
    
    case $status in
        "WORKING")
            echo -e "  ${GREEN}✓${NC} $option: $description"
            ((WORKING++))
            ;;
        "BROKEN")
            echo -e "  ${RED}✗${NC} $option: $description"
            ((BROKEN++))
            ;;
        "MISSING")
            echo -e "  ${YELLOW}⚠${NC} $option: $description"
            ((MISSING++))
            ;;
    esac
}

# ============================================
# TEST ROUTERS (Options 1-7)
# ============================================
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}ROUTERS (Options 1-7)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

ROUTERS=(
    "1:csr28:CSR28 - Core/Edge"
    "2:csr24:CSR24 - Distribution Left"
    "3:csr23:CSR23 - Distribution Right"
    "4:csr25:CSR25 - VRRP Active"
    "5:csr26:CSR26 - VRRP Standby"
    "6:csr27:CSR27 - Edge Right"
    "7:csr29:CSR29 - Edge Left"
)

for router_info in "${ROUTERS[@]}"; do
    IFS=':' read -r option router desc <<< "$router_info"
    container="clab-ospf-network-$router"
    
    if check_container "$container"; then
        if docker exec "$container" vtysh -c "show version" &>/dev/null; then
            report_status "$option" "$desc" "WORKING"
        else
            report_status "$option" "$desc (container exists but vtysh fails)" "BROKEN"
        fi
    else
        report_status "$option" "$desc (container not running)" "BROKEN"
    fi
done

# ============================================
# TEST END DEVICES (Options 8-10)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}END DEVICES (Options 8-10)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Option 8: win-bottom
if check_container "clab-ospf-network-win-bottom"; then
    report_status "8" "Win-Bottom (192.168.10.10)" "WORKING"
else
    report_status "8" "Win-Bottom (NOT IN CURRENT TOPOLOGY)" "BROKEN"
fi

# Option 9: linux-bottom
if check_container "clab-ospf-network-linux-bottom"; then
    report_status "9" "Linux-Bottom (192.168.10.20)" "WORKING"
else
    report_status "9" "Linux-Bottom (container not running)" "BROKEN"
fi

# Option 10: node1
if check_container "clab-ospf-network-node1"; then
    report_status "10" "Node1 (192.168.20.100)" "WORKING"
else
    report_status "10" "Node1 (NOT IN CURRENT TOPOLOGY)" "BROKEN"
fi

# ============================================
# TEST TELEMETRY (Options 11-13)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TELEMETRY (Options 11-13)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_container "clab-ospf-network-otel-collector"; then
    report_status "11" "OTEL Collector logs" "WORKING"
else
    report_status "11" "OTEL Collector logs" "BROKEN"
fi

if check_container "clab-ospf-network-logstash"; then
    report_status "12" "Logstash logs" "WORKING"
    report_status "13" "Logstash shell access" "WORKING"
else
    report_status "12" "Logstash logs" "BROKEN"
    report_status "13" "Logstash shell access" "BROKEN"
fi

# ============================================
# TEST NETWORK COMMANDS (Options 20-24)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}NETWORK COMMANDS (Options 20-24)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Need at least one router running
ROUTER_COUNT=$(docker ps --filter "name=clab-ospf-network-csr" --filter "status=running" -q | wc -l)
if [ "$ROUTER_COUNT" -gt 0 ]; then
    report_status "20" "Show OSPF neighbors" "WORKING"
    report_status "22" "Show routing tables" "WORKING"
else
    report_status "20" "Show OSPF neighbors" "BROKEN"
    report_status "22" "Show routing tables" "BROKEN"
fi

# VRRP status
if check_container "clab-ospf-network-csr25" && check_container "clab-ospf-network-csr26"; then
    report_status "21" "Show VRRP status" "WORKING"
else
    report_status "21" "Show VRRP status (csr25/csr26 needed)" "BROKEN"
fi

# Connectivity test (needs win-bottom and node1)
if check_container "clab-ospf-network-win-bottom" && check_container "clab-ospf-network-node1"; then
    report_status "23" "Test connectivity (win-bottom to node1)" "WORKING"
else
    if check_container "clab-ospf-network-linux-bottom" && check_container "clab-ospf-network-linux-top"; then
        report_status "23" "Test connectivity (needs update: linux-bottom to linux-top)" "MISSING"
    else
        report_status "23" "Test connectivity" "BROKEN"
    fi
fi

# Emergency diagnostic script
if check_script "emergency-diagnostic.sh"; then
    report_status "24" "Run network diagnostics" "WORKING"
else
    report_status "24" "Run network diagnostics (script missing)" "MISSING"
fi

# ============================================
# TEST LLDP COMMANDS (Options 30-34)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}LLDP COMMANDS (Options 30-34)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_script "show-lldp-neighbors.sh"; then
    report_status "30" "Show LLDP neighbors" "WORKING"
else
    report_status "30" "Show LLDP neighbors (script missing)" "MISSING"
fi

if check_script "lldp-status.sh"; then
    report_status "31" "LLDP status overview" "WORKING"
else
    report_status "31" "LLDP status overview (script missing)" "MISSING"
fi

if [ -f "$LAB_DIR/logs/lldp-export.log" ]; then
    report_status "32" "LLDP service logs" "WORKING"
else
    report_status "32" "LLDP service logs (log file missing)" "MISSING"
fi

if systemctl list-unit-files | grep -q "lldp-export"; then
    report_status "33" "Restart LLDP service" "WORKING"
else
    report_status "33" "Restart LLDP service (service not installed)" "MISSING"
fi

if check_script "lldp-to-elasticsearch.sh"; then
    report_status "34" "Test LLDP manually" "WORKING"
else
    report_status "34" "Test LLDP manually (script missing)" "MISSING"
fi

# ============================================
# TEST NETFLOW COMMANDS (Options 35-39)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}NETFLOW COMMANDS (Options 35-39)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_script "setup-netflow.sh"; then
    report_status "35" "Setup NetFlow on all routers" "WORKING"
else
    report_status "35" "Setup NetFlow (script missing)" "MISSING"
fi

if check_script "check-netflow-status.sh"; then
    report_status "36" "Check NetFlow status" "WORKING"
else
    report_status "36" "Check NetFlow status (script missing)" "MISSING"
fi

# NetFlow data queries need Elasticsearch
if [ "$ES_CONFIGURED" = "YES" ]; then
    report_status "37" "Query NetFlow data" "WORKING"
    report_status "38" "NetFlow stats summary" "WORKING"
else
    report_status "37" "Query NetFlow data (ES not configured)" "BROKEN"
    report_status "38" "NetFlow stats summary (ES not configured)" "BROKEN"
fi

# Stop NetFlow
if [ "$ROUTER_COUNT" -gt 0 ]; then
    report_status "39" "Stop NetFlow collection" "WORKING"
else
    report_status "39" "Stop NetFlow collection" "BROKEN"
fi

# ============================================
# TEST ELASTICSEARCH COMMANDS (Options 40-46)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}ELASTICSEARCH COMMANDS (Options 40-46)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_script "configure-elasticsearch.sh"; then
    report_status "40" "Configure Elasticsearch" "WORKING"
else
    report_status "40" "Configure Elasticsearch (script missing)" "MISSING"
fi

if [ "$ES_CONFIGURED" = "YES" ]; then
    if curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" &>/dev/null; then
        report_status "41" "Test Elasticsearch connection" "WORKING"
        report_status "42" "Query SNMP metrics" "WORKING"
        report_status "43" "Query LLDP topology" "WORKING"
        report_status "45" "Show indices" "WORKING"
        report_status "46" "Show collection rate" "WORKING"
    else
        report_status "41" "Test Elasticsearch connection (credentials may be wrong)" "BROKEN"
        report_status "42" "Query SNMP metrics" "BROKEN"
        report_status "43" "Query LLDP topology" "BROKEN"
        report_status "45" "Show indices" "BROKEN"
        report_status "46" "Show collection rate" "BROKEN"
    fi
else
    report_status "41" "Test Elasticsearch connection (not configured)" "BROKEN"
    report_status "42" "Query SNMP metrics (not configured)" "BROKEN"
    report_status "43" "Query LLDP topology (not configured)" "BROKEN"
    report_status "45" "Show indices (not configured)" "BROKEN"
    report_status "46" "Show collection rate (not configured)" "BROKEN"
fi

if check_script "list-all-metrics.sh"; then
    report_status "44" "List all metric types" "WORKING"
else
    report_status "44" "List all metric types (script missing)" "MISSING"
fi

# ============================================
# TEST TOPOLOGY & VISUALIZATION (Options 50-54)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}TOPOLOGY & VISUALIZATION (Options 50-54)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_script "show-topology.sh"; then
    report_status "50" "Show network topology (ASCII)" "WORKING"
else
    report_status "50" "Show network topology (script missing)" "MISSING"
fi

if check_script "show-topology-live.sh"; then
    report_status "51" "Live topology discovery" "WORKING"
else
    report_status "51" "Live topology discovery (script missing)" "MISSING"
fi

if check_script "generate-topology-graph.sh"; then
    report_status "52" "Generate topology graph (Graphviz)" "WORKING"
else
    report_status "52" "Generate topology graph (script missing)" "MISSING"
fi

if check_script "export-topology-json.sh"; then
    report_status "53" "Export topology to JSON" "WORKING"
else
    report_status "53" "Export topology to JSON (script missing)" "MISSING"
fi

if check_script "status.sh"; then
    report_status "54" "Lab status summary" "WORKING"
else
    report_status "54" "Lab status summary (script missing)" "MISSING"
fi

# ============================================
# TEST CONFIGURATION (Options 60-65)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}CONFIGURATION (Options 60-65)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if check_script "install-snmp-lldp.sh"; then
    report_status "60" "Reinstall SNMP + LLDP" "WORKING"
else
    report_status "60" "Reinstall SNMP + LLDP (script missing)" "MISSING"
fi

if check_script "create-otel-config-fast-mode.sh"; then
    report_status "61" "Regenerate OTEL config" "WORKING"
else
    report_status "61" "Regenerate OTEL config (script missing)" "MISSING"
fi

if check_container "clab-ospf-network-otel-collector"; then
    report_status "62" "Restart OTEL Collector" "WORKING"
else
    report_status "62" "Restart OTEL Collector" "BROKEN"
fi

if check_script "setup-lldp-service.sh"; then
    report_status "63" "Setup LLDP export service" "WORKING"
else
    report_status "63" "Setup LLDP export service (script missing)" "MISSING"
fi

if check_container "clab-ospf-network-logstash"; then
    report_status "64" "Restart Logstash" "WORKING"
    report_status "65" "Check Logstash config" "WORKING"
else
    report_status "64" "Restart Logstash" "BROKEN"
    report_status "65" "Check Logstash config" "BROKEN"
fi

# ============================================
# TEST CLEANUP (Option 70)
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}CLEANUP (Option 70)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -f "$LAB_DIR/ospf-network.clab.yml" ]; then
    report_status "70" "Quick cleanup (destroy lab)" "WORKING"
else
    report_status "70" "Quick cleanup (topology file missing)" "BROKEN"
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}SUMMARY${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}Working:${NC} $WORKING"
echo -e "  ${RED}Broken:${NC} $BROKEN"
echo -e "  ${YELLOW}Missing:${NC} $MISSING"
echo ""

TOTAL=$((WORKING + BROKEN + MISSING))
PERCENTAGE=$((WORKING * 100 / TOTAL))

echo -e "${CYAN}Health Score: ${PERCENTAGE}%${NC}"
echo ""

if [ "$BROKEN" -gt 0 ] || [ "$MISSING" -gt 0 ]; then
    echo -e "${YELLOW}Recommendations:${NC}"
    echo ""
    
    # Check for deprecated containers
    if ! check_container "clab-ospf-network-linux-bottom"; then
        echo "  • linux-bottom container not running (required for current topology)"
    fi
    
    if ! check_container "clab-ospf-network-linux-top"; then
        echo "  • linux-top container not running (required for current topology)"
    fi
    
    if check_container "clab-ospf-network-win-bottom"; then
        echo "  • win-bottom found but deprecated (should be removed)"
    fi
    
    if check_container "clab-ospf-network-node1"; then
        echo "  • node1 found but deprecated (should be removed)"
    fi
    
    # Check for missing scripts
    if [ "$MISSING" -gt 0 ]; then
        echo "  • $MISSING script(s) missing - check scripts/ directory"
    fi
    
    # Check Elasticsearch
    if [ "$ES_CONFIGURED" = "NO" ]; then
        echo "  • Elasticsearch not configured - run option 40"
    fi
    
    echo ""
fi

echo -e "${CYAN}=========================================${NC}"
echo "Audit complete!"
echo ""
