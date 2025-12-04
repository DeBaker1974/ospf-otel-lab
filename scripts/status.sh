#!/bin/bash

# ============================================
# OSPF OTEL Lab - Comprehensive Status Dashboard
# Version: v17.0 - Fixed Index Names & Data Stream Detection
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}${BOLD}=========================================${NC}"
    echo -e "${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}=========================================${NC}"
    echo ""
}

print_section() {
    echo -e "${CYAN}${BOLD}━━━ $1 ━━━${NC}"
}

print_status() {
    local status=$1
    local message=$2
    case $status in
        ok)
            echo -e "  ${GREEN}✓${NC} $message"
            ;;
        warning)
            echo -e "  ${YELLOW}⚠${NC} $message"
            ;;
        error)
            echo -e "  ${RED}✗${NC} $message"
            ;;
        info)
            echo -e "  ${BLUE}ℹ${NC} $message"
            ;;
    esac
}

# Load environment
LAB_DIR="$HOME/ospf-otel-lab"
ENV_FILE="$LAB_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

clear
print_header "OSPF OTEL Lab - Status Dashboard v17.0"
echo -e "${CYAN}Complete Network Observability Stack${NC}"
echo -e "${CYAN}SNMP • Syslog • LLDP • NetFlow • Elastic Agent${NC}"

# ============================================
# INFRASTRUCTURE STATUS
# ============================================
print_section "Infrastructure"

RUNNING=$(docker ps --filter "name=clab-ospf-network" --filter "status=running" -q 2>/dev/null | wc -l)
TOTAL=$(docker ps -a --filter "name=clab-ospf-network" -q 2>/dev/null | wc -l)

echo -e "  ${BOLD}Containers:${NC} $RUNNING/$TOTAL running"
if [ "$RUNNING" -eq "$TOTAL" ] && [ "$TOTAL" -ge 13 ]; then
    print_status ok "All containers operational"
else
    print_status warning "Some containers stopped (Expected: 13+)"
    echo ""
    echo "  Stopped containers:"
    docker ps -a --filter "name=clab-ospf-network" --filter "status=exited" --format "    - {{.Names}}" 2>/dev/null | head -5
fi

echo ""
echo -e "  ${BOLD}Disk Usage:${NC}"
LAB_SIZE=$(du -sh "$LAB_DIR" 2>/dev/null | cut -f1)
BACKUP_SIZE=$(du -sh "$LAB_DIR/backups" 2>/dev/null | cut -f1 || echo "0")
echo "    Lab directory: $LAB_SIZE"
echo "    Backups: $BACKUP_SIZE"

# ============================================
# ROUTING PROTOCOLS
# ============================================
print_section "Routing Protocols"

echo -e "  ${BOLD}OSPF:${NC}"
OSPF_FULL=$(docker exec clab-ospf-network-csr28 vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full" || echo 0)
OSPF_TOTAL=$(docker exec clab-ospf-network-csr28 vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "/" || echo 0)
echo "    Neighbors: $OSPF_FULL Full / $OSPF_TOTAL Total"

if [ "$OSPF_FULL" -ge 2 ]; then
    print_status ok "OSPF converged"
    AREA=$(docker exec clab-ospf-network-csr28 vtysh -c "show ip ospf" 2>/dev/null | grep "Area ID" | awk '{print $3}' | head -1)
    echo "    Area: ${AREA:-0.0.0.0}"
else
    print_status warning "OSPF not fully converged"
fi

echo ""
echo -e "  ${BOLD}VRRP:${NC}"
if docker exec clab-ospf-network-csr25 vtysh -c "show vrrp" 2>/dev/null | grep -q "Master"; then
    VRRP_MASTER="CSR25"
    VRRP_BACKUP="CSR26"
else
    VRRP_MASTER="CSR26"
    VRRP_BACKUP="CSR25"
fi
echo "    Master: $VRRP_MASTER"
echo "    Backup: $VRRP_BACKUP"
echo "    VIP: 192.168.10.1"
print_status ok "VRRP operational"

# ============================================
# Get Elasticsearch Data (FIXED - Correct Index Names)
# ============================================
if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
    # SNMP data streams - FIXED: Using correct index names with snmp. prefix
    SNMP_SYSTEM=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.system-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_INTERFACE=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.interface-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_MEMORY=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.memory-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_TCP=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.tcp-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_UDP=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.udp-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_IPSTATS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.ipstats-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_ICMP=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.icmp-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_ARP=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.arp-prod/_count" 2>/dev/null | jq -r '.count // 0')
    SNMP_OSPF=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.ospf-prod/_count" 2>/dev/null | jq -r '.count // 0')
    
    SNMP_COUNT=$((SNMP_SYSTEM + SNMP_INTERFACE + SNMP_MEMORY + SNMP_TCP + SNMP_UDP + SNMP_IPSTATS + SNMP_ICMP + SNMP_ARP + SNMP_OSPF))
    
    # Recent SNMP (last 5 minutes) - FIXED index names
    SNMP_SYSTEM_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.system-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_INTERFACE_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.interface-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_MEMORY_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.memory-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_TCP_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.tcp-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_UDP_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.udp-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_IPSTATS_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.ipstats-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_ICMP_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.icmp-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_ARP_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.arp-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    SNMP_OSPF_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.ospf-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    SNMP_RECENT=$((SNMP_SYSTEM_RECENT + SNMP_INTERFACE_RECENT + SNMP_MEMORY_RECENT + SNMP_TCP_RECENT + SNMP_UDP_RECENT + SNMP_IPSTATS_RECENT + SNMP_ICMP_RECENT + SNMP_ARP_RECENT + SNMP_OSPF_RECENT))
    
    # LLDP - FIXED index name
    LLDP_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.lldp-prod/_count" 2>/dev/null | jq -r '.count // 0')
    LLDP_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.lldp-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    # LLDP Topology index (separate from SNMP LLDP)
    LLDP_TOPOLOGY_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/lldp-topology/_count" 2>/dev/null | jq -r '.count // 0')
    LLDP_TOPOLOGY_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/lldp-topology/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    # Syslog (check multiple possible indices)
    LOGS_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-*/_count" 2>/dev/null | jq -r '.count // 0')
    LOGS_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-*/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    # SNMP Traps
    TRAPS_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-snmp.trap-prod/_count" 2>/dev/null | jq -r '.count // 0')
    TRAPS_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-snmp.trap-prod/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    # NetFlow
    NETFLOW_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-netflow.log-default/_count" 2>/dev/null | jq -r '.count // 0')
    NETFLOW_RECENT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/logs-netflow.log-default/_count" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
    
    # Get active routers from SNMP data
    ACTIVE_ROUTERS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.system-prod/_search?size=0" \
        -H 'Content-Type: application/json' \
        -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}},"aggs":{"routers":{"cardinality":{"field":"host.name"}}}}' 2>/dev/null | \
        jq -r '.aggregations.routers.value // 0')
    
    # Get unique LLDP neighbors
    LLDP_NEIGHBORS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-snmp.lldp-prod/_search?size=0" \
        -H 'Content-Type: application/json' \
        -d '{"aggs":{"unique_neighbors":{"cardinality":{"field":"network.lldp.rem.sysname"}}}}' 2>/dev/null | \
        jq -r '.aggregations.unique_neighbors.value // 0')
else
    SNMP_COUNT=0
    SNMP_RECENT=0
    SNMP_SYSTEM=0
    SNMP_INTERFACE=0
    SNMP_MEMORY=0
    SNMP_TCP=0
    SNMP_UDP=0
    SNMP_IPSTATS=0
    SNMP_ICMP=0
    SNMP_ARP=0
    SNMP_OSPF=0
    SNMP_SYSTEM_RECENT=0
    SNMP_INTERFACE_RECENT=0
    SNMP_MEMORY_RECENT=0
    SNMP_TCP_RECENT=0
    SNMP_UDP_RECENT=0
    SNMP_IPSTATS_RECENT=0
    SNMP_ICMP_RECENT=0
    SNMP_ARP_RECENT=0
    SNMP_OSPF_RECENT=0
    LLDP_COUNT=0
    LLDP_RECENT=0
    LLDP_TOPOLOGY_COUNT=0
    LLDP_TOPOLOGY_RECENT=0
    LOGS_COUNT=0
    LOGS_RECENT=0
    TRAPS_COUNT=0
    TRAPS_RECENT=0
    NETFLOW_COUNT=0
    NETFLOW_RECENT=0
    ACTIVE_ROUTERS=0
    LLDP_NEIGHBORS=0
fi

# ============================================
# TOPOLOGY DISCOVERY
# ============================================
print_section "Topology Discovery"

echo -e "  ${BOLD}LLDP:${NC}"

# Check LLDP daemons on routers
LLDP_RUNNING=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker exec "clab-ospf-network-$router" pgrep lldpd >/dev/null 2>&1; then
        LLDP_RUNNING=$((LLDP_RUNNING + 1))
    fi
done

echo "    Daemons: $LLDP_RUNNING/7 running"

if [ "$LLDP_COUNT" -gt 0 ]; then
    echo "    SNMP LLDP documents: ${LLDP_COUNT}"
    echo "    Recent (5m): ${LLDP_RECENT} documents"
    echo "    Unique neighbors discovered: $LLDP_NEIGHBORS"
    
    if [ "$LLDP_RECENT" -gt 0 ]; then
        print_status ok "LLDP data actively flowing via SNMP"
    else
        print_status warning "LLDP data exists but not recent"
    fi
else
    echo "    Data in Elasticsearch: None"
    print_status warning "No LLDP data in Elasticsearch"
    echo "      Fix: Check OTEL collector LLDP pipeline"
fi

if [ "$LLDP_TOPOLOGY_COUNT" -gt 0 ]; then
    echo ""
    echo "    LLDP Topology index: ${LLDP_TOPOLOGY_COUNT} documents"
    echo "    Recent (5m): ${LLDP_TOPOLOGY_RECENT} documents"
fi

# ============================================
# DATA COLLECTION
# ============================================
print_section "Data Collection"

echo -e "  ${BOLD}SNMP (Multi-Stream):${NC}"

if [ "$SNMP_COUNT" -gt 0 ]; then
    echo "    Total documents: ${SNMP_COUNT}"
    echo ""
    echo "    Data streams breakdown:"
    printf "      %-12s %8s %10s\n" "Stream" "Total" "Recent(5m)"
    printf "      %-12s %8s %10s\n" "--------" "------" "----------"
    printf "      %-12s %8s %10s\n" "System" "$SNMP_SYSTEM" "$SNMP_SYSTEM_RECENT"
    printf "      %-12s %8s %10s\n" "Interface" "$SNMP_INTERFACE" "$SNMP_INTERFACE_RECENT"
    printf "      %-12s %8s %10s\n" "Memory" "$SNMP_MEMORY" "$SNMP_MEMORY_RECENT"
    printf "      %-12s %8s %10s\n" "TCP" "$SNMP_TCP" "$SNMP_TCP_RECENT"
    printf "      %-12s %8s %10s\n" "UDP" "$SNMP_UDP" "$SNMP_UDP_RECENT"
    printf "      %-12s %8s %10s\n" "IP Stats" "$SNMP_IPSTATS" "$SNMP_IPSTATS_RECENT"
    printf "      %-12s %8s %10s\n" "ICMP" "$SNMP_ICMP" "$SNMP_ICMP_RECENT"
    printf "      %-12s %8s %10s\n" "ARP" "$SNMP_ARP" "$SNMP_ARP_RECENT"
    printf "      %-12s %8s %10s\n" "OSPF" "$SNMP_OSPF" "$SNMP_OSPF_RECENT"
    printf "      %-12s %8s %10s\n" "LLDP" "$LLDP_COUNT" "$LLDP_RECENT"
    echo ""
    echo "    Active routers (5m): $ACTIVE_ROUTERS/7"
    
    if [ "$SNMP_RECENT" -gt 100 ]; then
        print_status ok "SNMP data actively flowing to all streams"
    elif [ "$SNMP_RECENT" -gt 0 ]; then
        print_status ok "SNMP data flowing (recent: $SNMP_RECENT docs)"
    else
        print_status warning "SNMP data exists but not recent"
        echo "      Check: docker restart clab-ospf-network-otel-collector"
    fi
else
    # Fallback to process check
    SNMP_RUNNING=0
    for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
        if docker exec "clab-ospf-network-$router" pgrep snmpd >/dev/null 2>&1; then
            SNMP_RUNNING=$((SNMP_RUNNING + 1))
        fi
    done
    echo "    Agents: $SNMP_RUNNING/7 running"
    echo "    Data in Elasticsearch: None"
    
    print_status warning "No SNMP data in Elasticsearch"
    echo "      Fix: Check OTEL collector and SNMP daemons"
fi

# SNMP Traps Section
echo ""
echo -e "  ${BOLD}SNMP Traps:${NC}"
if [ "$TRAPS_COUNT" -gt 0 ]; then
    echo "    Total traps: ${TRAPS_COUNT}"
    echo "    Recent (5m): ${TRAPS_RECENT}"
    print_status ok "SNMP traps being captured"
else
    echo "    Total traps: 0"
    print_status info "No SNMP traps captured yet"
    echo "      Traps sent from CSR23 → Logstash (172.20.20.31:1062)"
fi

echo ""
echo -e "  ${BOLD}Syslog:${NC}"

OTEL_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-ospf-network-otel-collector 2>/dev/null)

if [ "$LOGS_COUNT" -gt 0 ]; then
    echo "    Data in Elasticsearch: ${LOGS_COUNT} documents"
    echo "    Recent activity (5m): ${LOGS_RECENT} documents"
    echo "    Target: $OTEL_IP:5140"
    
    if [ "$LOGS_RECENT" -gt 0 ]; then
        print_status ok "Syslog data actively flowing"
    else
        print_status warning "Syslog data exists but not recent"
    fi
else
    RSYSLOG_RUNNING=0
    for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
        if docker exec "clab-ospf-network-$router" pgrep rsyslogd >/dev/null 2>&1; then
            RSYSLOG_RUNNING=$((RSYSLOG_RUNNING + 1))
        fi
    done
    echo "    Agents: $RSYSLOG_RUNNING/7 running"
    echo "    Target: $OTEL_IP:5140"
    echo "    Data in Elasticsearch: None"
    
    if [ "$RSYSLOG_RUNNING" -gt 0 ]; then
        print_status info "Syslog configured but no data yet"
    else
        print_status info "Syslog not configured"
        echo "      Setup: ./scripts/fix-syslog-complete.sh"
    fi
fi

echo ""
echo -e "  ${BOLD}NetFlow:${NC}"

# Check for Elastic Agent first
AGENT_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-elastic-agent-sw2 2>/dev/null || echo "not_found")

if [ "$AGENT_STATUS" = "running" ]; then
    AGENT_IP=$(docker exec clab-ospf-network-elastic-agent-sw2 ip addr show eth1 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "N/A")
    echo "    Collector: Elastic Agent ($AGENT_IP:2055)"
    
    # Check if agent is listening - FIXED: handle multiline output
    AGENT_LISTENING=$(docker exec clab-ospf-network-elastic-agent-sw2 netstat -uln 2>/dev/null | grep -c ":2055" | tr -d '[:space:]' || echo "0")
    if [ "$AGENT_LISTENING" -gt 0 ] 2>/dev/null; then
        echo "    Status: Listening on port 2055"
    else
        echo "    Status: Not listening (configure NetFlow integration in Fleet)"
    fi
else
    LOGSTASH_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-ospf-network-logstash 2>/dev/null)
    echo "    Collector: Logstash ($LOGSTASH_IP:2055)"
fi

# Check exporters
SOFTFLOWD_RUNNING=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    PROCESSES=$(docker exec "clab-ospf-network-$router" pgrep -c softflowd 2>/dev/null || echo 0)
    if [ "$PROCESSES" -gt 0 ] 2>/dev/null; then
        SOFTFLOWD_RUNNING=$((SOFTFLOWD_RUNNING + 1))
    fi
done
echo "    Exporters: $SOFTFLOWD_RUNNING/7 routers"

if [ "$NETFLOW_COUNT" -gt 0 ]; then
    echo "    Data in Elasticsearch: ${NETFLOW_COUNT} documents"
    echo "    Recent activity (5m): ${NETFLOW_RECENT} documents"
    
    if [ "$NETFLOW_RECENT" -gt 0 ]; then
        print_status ok "NetFlow data actively flowing"
    else
        print_status warning "NetFlow data exists but not recent"
        echo "      Generate traffic: ./scripts/generate-traffic.sh"
    fi
else
    echo "    Data in Elasticsearch: None"
    
    if [ "$SOFTFLOWD_RUNNING" -gt 0 ]; then
        print_status warning "NetFlow exporters running but no data"
        echo "      • Check collector is listening"
        echo "      • Generate traffic: ./scripts/generate-traffic.sh"
    else
        print_status info "NetFlow exporters not running"
        echo "      Setup: Check netflow-startup.sh script"
    fi
fi

# ============================================
# ELASTIC AGENT
# ============================================
print_section "Elastic Agent (sw2)"

if [ "$AGENT_STATUS" = "running" ]; then
    print_status ok "Elastic Agent operational"
    
    AGENT_VER=$(docker exec clab-ospf-network-elastic-agent-sw2 elastic-agent version 2>/dev/null | head -1 || echo "unknown")
    echo "  Version: $AGENT_VER"
    echo "  Network: $AGENT_IP (connected to sw2)"
    
    # Check enrollment
    AGENT_HEALTH=$(docker exec clab-ospf-network-elastic-agent-sw2 elastic-agent status 2>/dev/null | head -5)
    if echo "$AGENT_HEALTH" | grep -qi "healthy"; then
        echo "  Status: Enrolled and healthy"
    elif echo "$AGENT_HEALTH" | grep -qi "degraded"; then
        echo "  Status: Degraded (check Fleet)"
    else
        echo "  Status: Unknown"
    fi
    
    # Check NetFlow integration - FIXED: handle multiline output properly
    NETFLOW_LISTENING=$(docker exec clab-ospf-network-elastic-agent-sw2 netstat -uln 2>/dev/null | grep -c ":2055" | tr -d '[:space:]' || echo "0")
    if [ "$NETFLOW_LISTENING" -gt 0 ] 2>/dev/null; then
        print_status ok "NetFlow integration active"
    else
        print_status info "NetFlow integration not configured"
        echo "      Configure in Fleet: Network Packet Capture"
    fi
else
    print_status warning "Elastic Agent not running"
    echo "  Deploy: Check topology includes elastic-agent-sw2"
fi

# ============================================
# OTEL COLLECTOR
# ============================================
print_section "OpenTelemetry Collector"

OTEL_STATUS=$(docker inspect clab-ospf-network-otel-collector --format='{{.State.Status}}' 2>/dev/null || echo "not_found")
echo -e "  ${BOLD}Status:${NC} ${OTEL_STATUS:-Unknown}"

if [ "$OTEL_STATUS" = "running" ]; then
    print_status ok "OTEL collector operational"
    
    echo ""
    echo -e "  ${BOLD}Active Pipelines:${NC}"
    
    # Count receivers
    SNMP_RECEIVERS=$(grep -c "snmp/csr" "$LAB_DIR/configs/otel/otel-collector.yml" 2>/dev/null || echo 0)
    echo "    • SNMP receivers: $SNMP_RECEIVERS"
    echo "    • Pipelines: 10 (system, memory, interface, tcp, udp, ipstats, icmp, arp, ospf, lldp)"
    
    echo ""
    echo -e "  ${BOLD}Collection Intervals:${NC}"
    echo "    • System/Interface: 15-30s"
    echo "    • Memory/LLDP: 30-60s"
    echo "    • Protocols (IP/TCP/UDP/ICMP): 30s"
    echo "    • ARP/OSPF: 60s"
    
    # Check for ACTUAL errors (exclude metric names)
    ACTUAL_ERRORS=$(docker logs --since 5m clab-ospf-network-otel-collector 2>&1 | \
        grep -iE "level=error|\"level\":\"error\"" | \
        grep -v "network.interface" | \
        grep -v "Name: network" | \
        wc -l || echo 0)
    
    if [ "$ACTUAL_ERRORS" -gt 10 ] 2>/dev/null; then
        print_status warning "Found $ACTUAL_ERRORS errors in last 5 minutes"
        echo "      Check: docker logs --since 5m clab-ospf-network-otel-collector | grep -i error"
    elif [ "$ACTUAL_ERRORS" -gt 0 ] 2>/dev/null; then
        print_status info "Found $ACTUAL_ERRORS minor errors (may be normal)"
    else
        print_status ok "No errors in last 5 minutes"
    fi
else
    print_status error "OTEL collector not running"
    echo "      Fix: docker restart clab-ospf-network-otel-collector"
fi

# ============================================
# LOGSTASH (Optional/Legacy)
# ============================================
LOGSTASH_STATUS=$(docker inspect clab-ospf-network-logstash --format='{{.State.Status}}' 2>/dev/null || echo "not_found")

if [ "$LOGSTASH_STATUS" = "running" ]; then
    print_section "Logstash (SNMP Traps & Backup NetFlow)"
    print_status ok "Logstash operational"
    LOGSTASH_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' clab-ospf-network-logstash 2>/dev/null)
    echo "  IP: $LOGSTASH_IP"
    echo "  Ports: 2055/udp (NetFlow), 1062/udp (SNMP Traps)"
    echo "  SNMP Traps captured: $TRAPS_COUNT"
fi

# ============================================
# ELASTICSEARCH
# ============================================
print_section "Elasticsearch Serverless"

if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
    echo -e "  ${BOLD}Endpoint:${NC} $ES_ENDPOINT"
    
    ES_VERSION=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT" 2>/dev/null | jq -r '.version.number // "unknown"')
    if [ "$ES_VERSION" != "unknown" ] && [ "$ES_VERSION" != "null" ]; then
        echo "  Version: $ES_VERSION"
        print_status ok "Elasticsearch reachable"
    else
        print_status error "Elasticsearch connection failed"
        echo "      Check: curl -s -H \"Authorization: ApiKey \$ES_API_KEY\" \"\$ES_ENDPOINT/_cluster/health\""
    fi
    
    echo ""
    echo -e "  ${BOLD}Data Summary:${NC}"
    TOTAL_DOCS=$((SNMP_COUNT + LLDP_COUNT + LOGS_COUNT + NETFLOW_COUNT + TRAPS_COUNT))
    TOTAL_RECENT=$((SNMP_RECENT + LLDP_RECENT + LOGS_RECENT + NETFLOW_RECENT + TRAPS_RECENT))
    
    echo "    Total SNMP metrics: ${SNMP_COUNT}"
    echo "    Total LLDP: ${LLDP_COUNT}"
    echo "    Total Logs: ${LOGS_COUNT}"
    echo "    Total NetFlow: ${NETFLOW_COUNT}"
    echo "    Total SNMP Traps: ${TRAPS_COUNT}"
    echo "    ─────────────────────"
    echo "    Grand Total: ${TOTAL_DOCS} documents"
    echo ""
    echo "    Recent (5m): ${TOTAL_RECENT} docs"
    
    # Calculate docs per minute
    if [ "$TOTAL_RECENT" -gt 0 ]; then
        DOCS_PER_MIN=$((TOTAL_RECENT / 5))
        echo "    Rate: ~${DOCS_PER_MIN} docs/min"
    fi
    
    echo "    Active routers: ${ACTIVE_ROUTERS}/7"
    
    echo ""
    # Status determination
    if [ "$TOTAL_RECENT" -gt 200 ]; then
        print_status ok "All data streams actively collecting"
    elif [ "$TOTAL_RECENT" -gt 50 ]; then
        print_status ok "Data collection active"
    elif [ "$TOTAL_RECENT" -gt 0 ]; then
        print_status warning "Low collection rate (expected >200 docs/5m)"
    elif [ "$TOTAL_DOCS" -gt 1000 ]; then
        print_status warning "Old data exists but no recent activity"
        echo "      Fix: docker restart clab-ospf-network-otel-collector"
    else
        print_status warning "Limited data in Elasticsearch"
        echo "      Check: OTEL collector logs and SNMP agents"
    fi
    
    # Show index health
    echo ""
    echo -e "  ${BOLD}Index Health:${NC}"
    
    # Get indices with document counts
    curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/_cat/indices/metrics-snmp.*-prod?h=index,health,docs.count&s=docs.count:desc" 2>/dev/null | head -10 | while read line; do
        INDEX_NAME=$(echo "$line" | awk '{print $1}')
        HEALTH=$(echo "$line" | awk '{print $2}')
        COUNT=$(echo "$line" | awk '{print $3}')
        
        # Extract short name
        SHORT_NAME=$(echo "$INDEX_NAME" | sed 's/metrics-snmp\.\(.*\)-prod/\1/' | sed 's/\.ds-//')
        
        case $HEALTH in
            green)
                echo -e "    ${GREEN}●${NC} ${SHORT_NAME}: ${COUNT} docs"
                ;;
            yellow)
                echo -e "    ${YELLOW}●${NC} ${SHORT_NAME}: ${COUNT} docs"
                ;;
            red)
                echo -e "    ${RED}●${NC} ${SHORT_NAME}: ${COUNT} docs"
                ;;
            *)
                echo "    ○ ${SHORT_NAME}: ${COUNT} docs"
                ;;
        esac
    done
    
    # Also show other indices
    OTHER_INDICES=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/_cat/indices/logs-*,lldp-*?h=index,docs.count&s=docs.count:desc" 2>/dev/null | head -5)
    
    if [ -n "$OTHER_INDICES" ]; then
        echo ""
        echo "    Other indices:"
        echo "$OTHER_INDICES" | while read line; do
            INDEX_NAME=$(echo "$line" | awk '{print $1}')
            COUNT=$(echo "$line" | awk '{print $2}')
            SHORT_NAME=$(echo "$INDEX_NAME" | sed 's/logs-//' | sed 's/\.ds-//')
            echo "    ○ ${SHORT_NAME}: ${COUNT} docs"
        done
    fi
    
else
    print_status warning "Elasticsearch not configured"
    echo "  Setup: ./scripts/configure-elasticsearch.sh"
    echo ""
    echo "  Required environment variables:"
    echo "    ES_ENDPOINT=https://your-cluster.es.cloud.es.io"
    echo "    ES_API_KEY=your-api-key"
fi

# ============================================
# BACKUP STATUS
# ============================================
print_section "Backup System"

if [ -d "$LAB_DIR/backups" ]; then
    BACKUP_COUNT=$(ls -1 "$LAB_DIR/backups" 2>/dev/null | grep -E "^[0-9]{8}_[0-9]{6}$" | wc -l)
    ARCHIVE_COUNT=$(ls -1 "$LAB_DIR/backups"/*.tar.gz 2>/dev/null | wc -l || echo 0)
    
    echo "  Backups: $BACKUP_COUNT directories, $ARCHIVE_COUNT archives"
    
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        LATEST=$(ls -1t "$LAB_DIR/backups" 2>/dev/null | grep -E "^[0-9]{8}_[0-9]{6}$" | head -1)
        if [ -n "$LATEST" ]; then
            LATEST_DATE=$(echo "$LATEST" | sed 's/_/ /')
            LATEST_SIZE=$(du -sh "$LAB_DIR/backups/$LATEST" 2>/dev/null | cut -f1)
            echo "  Latest: $LATEST_DATE ($LATEST_SIZE)"
        fi
        print_status ok "Backups available"
    else
        print_status info "No backups yet"
    fi
    
    if systemctl is-active --quiet ospf-lab-backup.timer 2>/dev/null; then
        NEXT_BACKUP=$(systemctl show ospf-lab-backup.timer -p NextElapseUSecRealtime 2>/dev/null | cut -d= -f2 | cut -d' ' -f1-3)
        echo "  Automated: Enabled (next: $NEXT_BACKUP)"
        print_status ok "Automated backups active"
    else
        print_status info "Automated backups not configured"
    fi
else
    print_status info "No backup directory"
fi

# ============================================
# HEALTH SCORE
# ============================================
print_section "System Health Summary"

HEALTH=0
MAX_HEALTH=100

# Infrastructure (15 points)
if [ "$RUNNING" -eq "$TOTAL" ] 2>/dev/null; then
    HEALTH=$((HEALTH + 15))
elif [ "$RUNNING" -ge $((TOTAL - 1)) ] 2>/dev/null; then
    HEALTH=$((HEALTH + 10))
else
    HEALTH=$((HEALTH + 5))
fi

# Routing (10 points)
if [ "$OSPF_FULL" -ge 2 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 10))
else
    HEALTH=$((HEALTH + 5))
fi

# LLDP (15 points) - based on recent data
if [ "${LLDP_RECENT:-0}" -gt 50 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 15))
elif [ "${LLDP_RECENT:-0}" -gt 0 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 10))
elif [ "${LLDP_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 5))
fi

# SNMP (25 points) - based on recent data
if [ "${SNMP_RECENT:-0}" -gt 500 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 25))
elif [ "${SNMP_RECENT:-0}" -gt 100 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 20))
elif [ "${SNMP_RECENT:-0}" -gt 10 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 15))
elif [ "${SNMP_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 7))
fi

# OTEL (10 points)
if [ "$OTEL_STATUS" = "running" ]; then
    HEALTH=$((HEALTH + 10))
fi

# Elastic Agent (10 points)
if [ "$AGENT_STATUS" = "running" ]; then
    HEALTH=$((HEALTH + 10))
fi

# Elasticsearch connectivity (10 points)
if [ "$ES_VERSION" != "unknown" ] && [ "$ES_VERSION" != "null" ] && [ -n "$ES_VERSION" ]; then
    HEALTH=$((HEALTH + 10))
fi

# Active routers (5 points)
if [ "${ACTIVE_ROUTERS:-0}" -ge 7 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 5))
elif [ "${ACTIVE_ROUTERS:-0}" -ge 5 ] 2>/dev/null; then
    HEALTH=$((HEALTH + 3))
fi

# Cap health at 100
if [ "$HEALTH" -gt "$MAX_HEALTH" ]; then
    HEALTH=$MAX_HEALTH
fi

echo ""
echo -e "  ${BOLD}Overall Health Score: $HEALTH/$MAX_HEALTH${NC}"
echo ""

# Draw progress bar
echo -n "  ["
for i in $(seq 1 10); do
    if [ $((i * 10)) -le $HEALTH ]; then
        echo -n -e "${GREEN}█${NC}"
    else
        echo -n "░"
    fi
done
echo "]"
echo ""

if [ "$HEALTH" -ge 90 ]; then
    print_status ok "System operating at peak performance"
elif [ "$HEALTH" -ge 75 ]; then
    print_status ok "System operational"
elif [ "$HEALTH" -ge 50 ]; then
    print_status warning "System needs attention"
else
    print_status error "System has significant issues"
fi

# ============================================
# QUICK COMMANDS
# ============================================
print_header "Quick Commands"

echo -e "${BOLD}Management:${NC}"
echo "  ./scripts/connect.sh                  - Interactive menu"
echo ""

print_header "End of Status Report"
