#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Load environment
ENV_FILE="$HOME/ospf-otel-lab/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

clear
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}   OSPF OTEL Lab - Menu v21.3${NC}"
echo -e "${CYAN}  Full Mesh Topology + VRRP${NC}"
echo -e "${CYAN}  Elasticsearch Serverless${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

check_container() {
    docker ps --filter "name=$1" --filter "status=running" -q &>/dev/null
    return $?
}

status_indicator() {
    if check_container "$1"; then
        echo -e "${GREEN}●${NC}"
    else
        echo -e "${RED}●${NC}"
    fi
}

while true; do
    echo -e "${YELLOW}ROUTERS:${NC}"
    echo "  1)  $(status_indicator clab-ospf-network-csr28) CSR28 - Core/Edge (172.20.20.28)"
    echo "  2)  $(status_indicator clab-ospf-network-csr24) CSR24 - Distribution Left (172.20.20.24)"
    echo "  3)  $(status_indicator clab-ospf-network-csr23) CSR23 - Distribution Right (172.20.20.23)"
    echo "  4)  $(status_indicator clab-ospf-network-csr25) CSR25 - VRRP Active (172.20.20.25)"
    echo "  5)  $(status_indicator clab-ospf-network-csr26) CSR26 - VRRP Standby (172.20.20.26)"
    echo "  6)  $(status_indicator clab-ospf-network-csr27) CSR27 - Edge Right (172.20.20.27)"
    echo "  7)  $(status_indicator clab-ospf-network-csr29) CSR29 - Edge Left (172.20.20.29)"
    echo ""
    echo -e "${YELLOW}INFRASTRUCTURE:${NC}"
    echo "  13) $(status_indicator clab-ospf-network-sw) SW - Bottom Switch (VLAN 10)"
    echo "  14) $(status_indicator clab-ospf-network-sw2) SW2 - Top Switch (VLAN 20)"
    echo ""
    echo -e "${YELLOW}UBUNTU HOSTS:${NC}"
    echo "  8)  $(status_indicator clab-ospf-network-linux-bottom) linux-bottom - Shell (192.168.10.20)"
    echo "  9)  $(status_indicator clab-ospf-network-linux-top) linux-top - Shell (192.168.20.100)"
    echo "  10) $(status_indicator clab-ospf-network-linux-bottom) linux-bottom - Check Status"
    echo "  11) $(status_indicator clab-ospf-network-linux-top) linux-top - Check Status"
    echo "  12) Test connectivity (linux-bottom → linux-top)"
    echo ""
    echo -e "${YELLOW}TELEMETRY:${NC}"
    echo "  15) $(status_indicator clab-ospf-network-otel-collector) OTEL Collector logs (live)"
    echo "  16) $(status_indicator clab-ospf-network-logstash) Logstash logs (live)"
    echo "  17) $(status_indicator clab-ospf-network-logstash) Logstash shell access"
    echo "  18) $(status_indicator clab-ospf-network-otel-collector) OTEL Collector info & logs"
    echo ""
    echo -e "${YELLOW}NETWORK COMMANDS:${NC}"
    echo "  20) Show OSPF neighbors (all routers)"
    echo "  21) Show VRRP status (csr25 & csr26)"
    echo "  22) Show routing tables"
    echo "  23) Show IP interfaces summary"
    echo "  24) Ping test matrix (all routers)"
    echo "  25) Show connection matrix (all links)"
    echo ""
    echo -e "${YELLOW}LLDP COMMANDS:${NC}"
    echo "  30) Show LLDP neighbors (all routers)"
    echo "  31) Test LLDP SNMP on all routers"
    echo "  32) Show LLDP status overview"
    echo "  33) LLDP service logs"
    echo "  34) Restart LLDP service"
    echo "  35) Manual LLDP collection (30s)"
    echo ""
    echo -e "${YELLOW}SNMP COMMANDS:${NC}"
    echo "  36) Test SNMP on all routers"
    echo "  37) Show SNMP process status"
    echo "  38) Check AgentX sockets"
    echo "  39) Restart SNMP + LLDP on all routers"
    echo ""
    echo -e "${YELLOW}ELASTICSEARCH COMMANDS:${NC}"
    echo "  50) Configure Elasticsearch"
    echo "  51) Test Elasticsearch connection"
    echo "  52) Query SNMP metrics (sample)"
    echo "  53) Query LLDP topology (sample)"
    echo "  54) List all metric types"
    echo "  55) Show indices"
    echo "  56) Show collection rate"
    echo "  57) Per-router metrics count"
    echo ""
    echo -e "${YELLOW}TOPOLOGY & VISUALIZATION:${NC}"
    echo "  60) Show network topology (ASCII)"
    echo "  61) Live topology discovery (LLDP)"
    echo "  62) Generate topology graph (PNG)"
    echo "  63) Export topology to JSON"
    echo "  64) Lab status summary"
    echo "  65) Show detailed connection matrix"
    echo ""
    echo -e "${YELLOW}CONFIGURATION:${NC}"
    echo "  70) Reinstall SNMP + LLDP (with AgentX)"
    echo "  71) Regenerate OTEL config"
    echo "  72) Restart OTEL Collector"
    echo "  73) Setup LLDP export service"
    echo "  74) Restart Logstash"
    echo "  75) Check Logstash config"
    echo "  76) View current .env configuration"
    echo ""
    echo -e "${YELLOW}ADVANCED:${NC}"
    echo "  80) Emergency diagnostic"
    echo "  81) Container health check"
    echo "  82) View all container logs"
    echo "  83) Restart all services"
    echo ""
    echo -e "${YELLOW}CLEANUP:${NC}"
    echo "  90) Quick cleanup (destroy lab)"
    echo "  91) Full cleanup (lab + logs + configs)"
    echo ""
    echo "  0)  Exit"
    echo ""
    echo -ne "${CYAN}Select option: ${NC}"
    read -r choice

    case $choice in
        # ========================================
        # ROUTERS (1-7)
        # ========================================
        1) docker exec -it clab-ospf-network-csr28 vtysh ;;
        2) docker exec -it clab-ospf-network-csr24 vtysh ;;
        3) docker exec -it clab-ospf-network-csr23 vtysh ;;
        4) docker exec -it clab-ospf-network-csr25 vtysh ;;
        5) docker exec -it clab-ospf-network-csr26 vtysh ;;
        6) docker exec -it clab-ospf-network-csr27 vtysh ;;
        7) docker exec -it clab-ospf-network-csr29 vtysh ;;
        
        # ========================================
        # INFRASTRUCTURE (13-14)
        # ========================================
        13)
            clear
            echo -e "${CYAN}=== SW (Bottom Switch) Status ===${NC}"
            echo ""
            echo "Container: clab-ospf-network-sw"
            echo "Role: Layer 2 Bridge for VLAN 10 (192.168.10.0/24)"
            echo ""
            echo "Connected devices:"
            echo "  • CSR25 (eth5) - VRRP Active"
            echo "  • CSR26 (eth5) - VRRP Standby"
            echo "  • linux-bottom (eth1) - End host"
            echo ""
            docker exec clab-ospf-network-sw ip link show
            ;;
        14)
            clear
            echo -e "${CYAN}=== SW2 (Top Switch) Status ===${NC}"
            echo ""
            echo "Container: clab-ospf-network-sw2"
            echo "Role: Layer 2 Bridge for VLAN 20 (192.168.20.0/24)"
            echo ""
            echo "Connected devices:"
            echo "  • CSR28 (eth3) - Core router"
            echo "  • linux-top (eth1) - End host"
            echo ""
            docker exec clab-ospf-network-sw2 ip link show
            ;;
        
        # ========================================
        # UBUNTU HOSTS (8-12)
        # ========================================
        8) 
            clear
            echo -e "${CYAN}Connecting to linux-bottom (192.168.10.20)${NC}"
            echo -e "${YELLOW}Tip: Type 'exit' to return to menu${NC}"
            echo ""
            docker exec -it clab-ospf-network-linux-bottom bash
            ;;
        9) 
            clear
            echo -e "${CYAN}Connecting to linux-top (192.168.20.100)${NC}"
            echo -e "${YELLOW}Tip: Type 'exit' to return to menu${NC}"
            echo ""
            docker exec -it clab-ospf-network-linux-top bash
            ;;
        10)
            clear
            echo -e "${CYAN}=== linux-bottom Status ===${NC}"
            echo ""
            docker exec clab-ospf-network-linux-bottom bash -c '
                echo "Hostname: $(hostname)"
                echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
                echo ""
                echo "Network Configuration:"
                ip -br addr show | grep -v "lo"
                echo ""
                echo "Default Gateway:"
                ip route | grep default
                echo ""
                echo "Reachability:"
                ping -c 2 192.168.10.1 &>/dev/null && echo "  ✓ Gateway (192.168.10.1 - VRRP VIP) reachable" || echo "  ✗ Gateway unreachable"
                ping -c 2 192.168.20.100 &>/dev/null && echo "  ✓ linux-top (192.168.20.100) reachable" || echo "  ✗ linux-top unreachable"
                echo ""
                echo "Installed Tools:"
                command -v curl &>/dev/null && echo "  ✓ curl" || echo "  ✗ curl"
                command -v wget &>/dev/null && echo "  ✓ wget" || echo "  ✗ wget"
                command -v jq &>/dev/null && echo "  ✓ jq" || echo "  ✗ jq"
            '
            ;;
        11)
            clear
            echo -e "${CYAN}=== linux-top Status ===${NC}"
            echo ""
            docker exec clab-ospf-network-linux-top bash -c '
                echo "Hostname: $(hostname)"
                echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
                echo ""
                echo "Network Configuration:"
                ip -br addr show | grep -v "lo"
                echo ""
                echo "Default Gateway:"
                ip route | grep default
                echo ""
                echo "Reachability:"
                ping -c 2 192.168.20.1 &>/dev/null && echo "  ✓ Gateway (192.168.20.1) reachable" || echo "  ✗ Gateway unreachable"
                ping -c 2 192.168.10.20 &>/dev/null && echo "  ✓ linux-bottom (192.168.10.20) reachable" || echo "  ✗ linux-bottom unreachable"
                echo ""
                echo "Installed Tools:"
                command -v curl &>/dev/null && echo "  ✓ curl" || echo "  ✗ curl"
                command -v wget &>/dev/null && echo "  ✓ wget" || echo "  ✗ wget"
                command -v jq &>/dev/null && echo "  ✓ jq" || echo "  ✗ jq"
            '
            ;;
        12)
            clear
            echo -e "${CYAN}=== Testing Connectivity: linux-bottom → linux-top ===${NC}"
            echo ""
            docker exec clab-ospf-network-linux-bottom bash -c '
                echo "Source: linux-bottom (192.168.10.20)"
                echo "Target: linux-top (192.168.20.100)"
                echo ""
                echo "Ping test (5 packets):"
                ping -c 5 192.168.20.100
                echo ""
                echo "Traceroute:"
                traceroute -n -m 10 192.168.20.100 2>/dev/null || echo "traceroute not installed"
            '
            ;;
        
        # ========================================
        # TELEMETRY (15-18)
        # ========================================
        15) 
            clear
            echo -e "${CYAN}OTEL Collector Logs (Ctrl+C to exit)${NC}"
            docker logs --tail 100 -f clab-ospf-network-otel-collector
            ;;
        16) 
            clear
            echo -e "${CYAN}Logstash Logs (Ctrl+C to exit)${NC}"
            docker logs --tail 100 -f clab-ospf-network-logstash
            ;;
        17) 
            clear
            echo -e "${CYAN}Logstash Shell Access${NC}"
            docker exec -it clab-ospf-network-logstash bash
            ;;
        18)
            clear
            echo -e "${CYAN}=== OTEL Collector - Container Info ===${NC}"
            echo -e "${YELLOW}Note: OTEL Collector uses a minimal distroless image (no shell)${NC}"
            echo ""
            echo -e "${CYAN}Container Details:${NC}"
            docker inspect clab-ospf-network-otel-collector --format='{{json .}}' 2>/dev/null | jq -r '
                "Image: " + .Config.Image,
                "Status: " + .State.Status,
                "Started: " + .State.StartedAt,
                "RestartCount: " + (.RestartCount | tostring)
            ' 2>/dev/null || echo "Container not found or jq not available"
            echo ""
            echo -e "${CYAN}Recent Logs (last 50 lines):${NC}"
            docker logs --tail 50 clab-ospf-network-otel-collector
            echo ""
            echo -e "${YELLOW}Press 'l' for live logs, 'c' to view config, any other key to continue${NC}"
            read -n 1 -r response
            case $response in
                l|L)
                    clear
                    echo -e "${CYAN}Live OTEL Collector Logs (Ctrl+C to exit)${NC}"
                    docker logs -f clab-ospf-network-otel-collector
                    ;;
                c|C)
                    clear
                    echo -e "${CYAN}OTEL Collector Configuration${NC}"
                    docker exec clab-ospf-network-otel-collector cat /etc/otelcol-contrib/config.yaml 2>/dev/null || echo "Cannot access config"
                    echo ""
                    read -p "Press Enter to continue..."
                    ;;
            esac
            ;;
        
        # ========================================
        # NETWORK COMMANDS (20-25)
        # ========================================
        20) 
            clear
            echo -e "${CYAN}=== OSPF Neighbors (All Routers) ===${NC}"
            for r in csr28 csr24 csr23 csr25 csr26 csr27 csr29; do
                echo ""
                echo -e "${YELLOW}$r:${NC}"
                docker exec clab-ospf-network-$r vtysh -c "show ip ospf neighbor" 2>/dev/null || echo "  Error querying $r"
            done
            ;;
        21) 
            clear
            echo -e "${CYAN}=== VRRP Status ===${NC}"
            echo ""
            echo -e "${YELLOW}CSR25 (Active):${NC}"
            docker exec clab-ospf-network-csr25 vtysh -c "show vrrp" 2>/dev/null || echo "VRRP not configured"
            echo ""
            echo -e "${YELLOW}CSR26 (Standby):${NC}"
            docker exec clab-ospf-network-csr26 vtysh -c "show vrrp" 2>/dev/null || echo "VRRP not configured"
            ;;
        22) 
            clear
            echo -e "${CYAN}=== Routing Tables ===${NC}"
            for r in csr28 csr25; do
                echo ""
                echo -e "${YELLOW}$r:${NC}"
                docker exec clab-ospf-network-$r vtysh -c "show ip route"
            done
            ;;
        23)
            clear
            echo -e "${CYAN}=== IP Interface Summary ===${NC}"
            for r in csr28 csr24 csr23 csr25 csr26 csr27 csr29; do
                echo ""
                echo -e "${YELLOW}$r:${NC}"
                docker exec clab-ospf-network-$r vtysh -c "show interface brief"
            done
            ;;
        24)
            clear
            echo -e "${CYAN}=== Ping Test Matrix ===${NC}"
            echo ""
            echo "Testing connectivity between all routers..."
            for src in csr28 csr24; do
                for dst_ip in 172.20.20.23 172.20.20.25 172.20.20.28; do
                    result=$(docker exec clab-ospf-network-$src ping -c 1 -W 1 $dst_ip &>/dev/null && echo "✓" || echo "✗")
                    echo "  $src → $dst_ip: $result"
                done
            done
            ;;
        25)
            clear
            echo -e "${CYAN}=== Physical Connection Matrix ===${NC}"
            echo ""
            cat << 'CONNMATRIX'
┌─────────────────────────────────────────────────────────────────┐
│                  PHYSICAL LINK CONNECTIONS                      │
├───────────────┬────────────────┬──────────────────┬─────────────┤
│   Source      │   Interface    │    Target        │  Interface  │
├───────────────┼────────────────┼──────────────────┼─────────────┤
│ CSR28         │ eth1           │ CSR24            │ eth1        │
│ CSR28         │ eth2           │ CSR23            │ eth2        │
│ CSR28         │ eth3           │ SW2              │ eth1        │
│ CSR24         │ eth2           │ CSR29            │ eth1        │
│ CSR24         │ eth3           │ CSR23            │ eth3        │
│ CSR24         │ eth4           │ CSR26            │ eth3        │
│ CSR24         │ eth5           │ CSR25            │ eth2        │
│ CSR23         │ eth1           │ CSR26            │ eth2        │
│ CSR23         │ eth4           │ CSR25            │ eth1        │
│ CSR23         │ eth5           │ CSR27            │ eth1        │
│ CSR29         │ eth2           │ CSR26            │ eth1        │
│ CSR27         │ eth2           │ CSR25            │ eth4        │
│ CSR26         │ eth4           │ CSR25            │ eth3        │
│ CSR25         │ eth5           │ SW               │ eth1        │
│ CSR26         │ eth5           │ SW               │ eth2        │
│ SW            │ eth3           │ linux-bottom     │ eth1        │
│ SW2           │ eth2           │ linux-top        │ eth1        │
└───────────────┴────────────────┴──────────────────┴─────────────┘

Total: 17 physical links
Core Backbone: 2 links (CSR28-CSR24, CSR28-CSR23)
VRRP Mesh: 8 links connecting CSR25/CSR26 to distribution
Access: 4 links (2 to switches, 2 to hosts)
Edge: 3 links (CSR29, CSR27 connections)
CONNMATRIX
            ;;
        
        # ========================================
        # LLDP COMMANDS (30-35)
        # ========================================
        30) 
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/show-lldp-neighbors.sh" ]; then
                $HOME/ospf-otel-lab/scripts/show-lldp-neighbors.sh
            else
                echo -e "${CYAN}=== LLDP Neighbors ===${NC}"
                for r in csr28 csr24 csr23 csr25 csr26 csr27 csr29; do
                    echo ""
                    echo -e "${YELLOW}$r:${NC}"
                    docker exec clab-ospf-network-$r lldpcli show neighbors 2>/dev/null | head -20
                done
            fi
            ;;
        31)
            clear
            echo -e "${CYAN}=== Testing LLDP SNMP (AgentX) ===${NC}"
            echo ""
            for i in 23 24 25 26 27 28 29; do
                echo -n "csr$i (172.20.20.$i): "
                result=$(snmpwalk -v2c -c public -t 3 -r 1 172.20.20.$i 1.0.8802.1.1.2.1.4.1.1.9 2>&1)
                if echo "$result" | grep -q "STRING"; then
                    count=$(echo "$result" | grep -c "STRING")
                    echo -e "${GREEN}✓${NC} ($count neighbors)"
                else
                    echo -e "${RED}✗${NC} (no data)"
                fi
            done
            ;;
        32)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/lldp-status.sh" ]; then
                $HOME/ospf-otel-lab/scripts/lldp-status.sh
            else
                echo "Script lldp-status.sh not found"
            fi
            ;;
        33)
            tail -f ~/ospf-otel-lab/logs/lldp-export.log 2>/dev/null || echo "Log file not found"
            ;;
        34)
            sudo systemctl restart lldp-export 2>/dev/null && echo "✓ LLDP service restarted" || echo "✗ Service not installed"
            ;;
        35)
            clear
            echo "Running manual LLDP collection for 30 seconds..."
            if [ -f "$HOME/ospf-otel-lab/scripts/lldp-to-elasticsearch.sh" ]; then
                timeout 30s $HOME/ospf-otel-lab/scripts/lldp-to-elasticsearch.sh
            else
                echo "Script lldp-to-elasticsearch.sh not found"
            fi
            ;;
        
        # ========================================
        # SNMP COMMANDS (36-39)
        # ========================================
        36)
            clear
            echo -e "${CYAN}=== Testing SNMP on All Routers ===${NC}"
            echo ""
            for i in 23 24 25 26 27 28 29; do
                echo -n "csr$i (172.20.20.$i): "
                if timeout 3 snmpget -v2c -c public 172.20.20.$i 1.3.6.1.2.1.1.1.0 &>/dev/null; then
                    echo -e "${GREEN}✓${NC} SNMP responding"
                else
                    echo -e "${RED}✗${NC} No response"
                fi
            done
            ;;
        37)
            clear
            echo -e "${CYAN}=== SNMP Process Status ===${NC}"
            for r in csr28 csr24 csr23; do
                echo ""
                echo -e "${YELLOW}$r:${NC}"
                docker exec clab-ospf-network-$r sh -c '
                    ps aux | grep snmpd | grep -v grep
                    echo "Port 161:"
                    netstat -uln 2>/dev/null | grep 161 || ss -uln | grep 161
                '
            done
            ;;
        38)
            clear
            echo -e "${CYAN}=== AgentX Socket Status ===${NC}"
            for r in csr28 csr24 csr23; do
                echo ""
                echo -e "${YELLOW}$r:${NC}"
                docker exec clab-ospf-network-$r sh -c '
                    if [ -S /var/agentx/master ]; then
                        echo "  ✓ AgentX socket exists"
                        ls -l /var/agentx/master
                    else
                        echo "  ✗ AgentX socket missing"
                    fi
                '
            done
            ;;
        39)
            clear
            echo -e "${CYAN}=== Restarting SNMP + LLDP on All Routers ===${NC}"
            for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
                echo -n "$r: "
                docker exec clab-ospf-network-$r sh -c '
                    mkdir -p /var/agentx && chmod 777 /var/agentx
                    pkill -9 snmpd lldpd 2>/dev/null
                    sleep 2
                    /usr/sbin/snmpd -c /etc/snmp/snmpd.conf -Lsd -Lf /dev/null udp:161
                    sleep 5
                    lldpd -x -X /var/agentx/master 2>/dev/null &
                    sleep 3
                    pgrep snmpd >/dev/null && pgrep lldpd >/dev/null && echo "✓" || echo "✗"
                '
            done
            echo ""
            echo "Wait 30 seconds for neighbor discovery..."
            ;;
        
        # ========================================
        # ELASTICSEARCH COMMANDS (50-57)
        # ========================================
        50)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/configure-elasticsearch.sh" ]; then
                $HOME/ospf-otel-lab/scripts/configure-elasticsearch.sh
            else
                echo "Script configure-elasticsearch.sh not found"
            fi
            ;;
        51)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                echo "Testing connection to: $ES_ENDPOINT"
                echo ""
                curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" | jq '.' || echo "✗ Connection failed"
            else
                echo "✗ Elasticsearch not configured (.env missing)"
                echo "Run option 50 to configure"
            fi
            ;;
        52)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                echo -e "${CYAN}Sample SNMP Metrics (last 10):${NC}"
                curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_search?size=10&sort=@timestamp:desc" | jq '.hits.hits[]._source | {time: .["@timestamp"], host: .host.name, metric: .metric.name, value: .metric.value}'
            else
                echo "Elasticsearch not configured"
            fi
            ;;
        53)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                echo -e "${CYAN}Sample LLDP Topology (last 10):${NC}"
                curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/lldp-topology/_search?size=10&sort=@timestamp:desc" | jq '.hits.hits[]._source | {time: .["@timestamp"], router: .router, interface: .local_interface, neighbor: .neighbor_sysname}'
            else
                echo "Elasticsearch not configured"
            fi
            ;;
        54)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/list-all-metrics.sh" ]; then
                $HOME/ospf-otel-lab/scripts/list-all-metrics.sh
            else
                echo "Script list-all-metrics.sh not found"
            fi
            ;;
        55)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/_cat/indices/*?v&s=index"
            else
                echo "Elasticsearch not configured"
            fi
            ;;
        56)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" -H 'Content-Type: application/json' -d '{"query":{"range":{"@timestamp":{"gte":"now-1m"}}}}' | jq -r '"Last minute: \(.count) documents"'
            else
                echo "Elasticsearch not configured"
            fi
            ;;
        57)
            clear
            if [ -f "$ENV_FILE" ]; then
                source "$ENV_FILE"
                echo -e "${CYAN}Per-Router Metrics Count:${NC}"
                echo ""
                for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
                    count=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" -H 'Content-Type: application/json' -d "{\"query\":{\"match\":{\"host.name\":\"$router\"}}}" | jq -r '.count')
                    echo "  $router: $count documents"
                done
            else
                echo "Elasticsearch not configured"
            fi
            ;;
        
        # ========================================
        # TOPOLOGY & VISUALIZATION (60-65)
        # ========================================
        60)
            clear
            echo -e "${CYAN}════════════════════════════════════════════════${NC}"
            echo -e "${CYAN}     COMPLETE NETWORK TOPOLOGY (v21.3)         ${NC}"
            echo -e "${CYAN}════════════════════════════════════════════════${NC}"
            echo ""
            if [ -f "$HOME/ospf-otel-lab/ospf-network.clab.yml" ]; then
                echo -e "${YELLOW}Container Status:${NC}"
                echo ""
                echo "Routers:"
                for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
                    if check_container "clab-ospf-network-$r"; then
                        echo -e "  ${GREEN}●${NC} $r (172.20.20.${r#csr})"
                    else
                        echo -e "  ${RED}●${NC} $r (172.20.20.${r#csr}) - DOWN"
                    fi
                done
                
                echo ""
                echo "Infrastructure:"
                for s in sw sw2; do
                    if check_container "clab-ospf-network-$s"; then
                        echo -e "  ${GREEN}●${NC} $s (Layer 2 Bridge)"
                    else
                        echo -e "  ${RED}●${NC} $s - DOWN"
                    fi
                done
                
                echo ""
                echo "Hosts:"
                for h in linux-bottom linux-top; do
                    if check_container "clab-ospf-network-$h"; then
                        if [ "$h" = "linux-bottom" ]; then
                            echo -e "  ${GREEN}●${NC} $h (192.168.10.20 via SW)"
                        else
                            echo -e "  ${GREEN}●${NC} $h (192.168.20.100 via SW2)"
                        fi
                    else
                        echo -e "  ${RED}●${NC} $h - DOWN"
                    fi
                done
                
                echo ""
                echo "Telemetry:"
                for t in otel-collector logstash; do
                    if check_container "clab-ospf-network-$t"; then
                        echo -e "  ${GREEN}●${NC} $t"
                    else
                        echo -e "  ${RED}●${NC} $t - DOWN"
                    fi
                done
                
                echo ""
                echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
                echo -e "${CYAN}              PHYSICAL TOPOLOGY                        ${NC}"
                echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
                echo ""
                cat << 'TOPOLOGY'
                         Internet/GCP
                              │
                    ┌─────────▼─────────┐
                    │      CSR28        │ Core/Edge
                    │   172.20.20.28    │ (Management Gateway)
                    └─┬──────┬──────┬───┘
                  e1 │      │e2    │e3
        ┌────────────┘      │      └──────────────┐
        │              ┌────▼────┐                │
   ┌────▼───┐         │  CSR23  │           ┌────▼────┐
   │ CSR24  │         │ .20.23  │           │  SW2    │ L2 Bridge
   │ .20.24 │         └┬──┬─┬─┬┬┘           │ (br0)   │ VLAN 20
   └┬─┬─┬─┬─┘       e1 │  │ │ ││e5          └────┬────┘
 e2 │ │ │ │e5          │  │ │ └┴────┐            │e2
    │ │ │ │            │  │ │       │            │
 ┌──▼─┴─┴─┴───┐    ┌───▼──▼─▼┐   ┌─▼────┐  ┌────▼──────┐
 │   CSR29    │    │  CSR26  │   │CSR25 │  │ linux-top │
 │  .20.29    │    │  .20.26 │   │.20.25│  │ .20.100   │
 │  Edge L    │    │  VRRP   │◄═►│VRRP  │  │ VLAN 20   │
 └────────────┘    │ Standby │   │Active│  └───────────┘
              e1   └──┬───┬──┘   └┬─┬─┬┬┘
               └──────┤e5 │e4  e2 │ │ ││e4
                      │   │    ┌──┘ │ │└────┐
                 ┌────▼───▼────▼┐   │ │  ┌──▼────┐
                 │      SW      │   │ │  │ CSR27 │
                 │     (br0)    │   │ │  │.20.27 │
                 │  L2 Bridge   │   │ │  │Edge R │
                 └──────┬───────┘   │ │  └───────┘
                     e3 │           │ │
                        │      ┌────┘ │
                   ┌────▼──────▼┐     │
                   │linux-bottom│◄────┘
                   │  .10.20    │  Redundant
                   │  VLAN 10   │  Paths
                   └────────────┘

┌─────────────────────────────────────────────────────────┐
│                   KEY FEATURES                          │
├─────────────────────────────────────────────────────────┤
│ • 7 FRRouting Routers (CSR23-29)                       │
│ • 2 Layer 2 Bridges (SW, SW2)                          │
│ • Full OSPF Area 0 Mesh                                 │
│ • VRRP HA Pair: CSR25 (Active) ↔ CSR26 (Standby)      │
│ • VIP: 192.168.10.1 (Gateway for linux-bottom)         │
│ • VLAN 10: 192.168.10.0/24 (via SW)                    │
│ • VLAN 20: 192.168.20.0/24 (via SW2)                   │
│ • 17 Physical Links (Full Redundancy)                   │
│ • SNMP/LLDP on all routers                              │
│ • Telemetry: OTEL Collector → Elasticsearch            │
└─────────────────────────────────────────────────────────┘

VRRP Configuration:
  • Virtual IP: 192.168.10.1
  • Active: CSR25 (Priority 110)
  • Standby: CSR26 (Priority 100)
  • Heartbeat: Direct link (CSR26:eth4 ↔ CSR25:eth3)
  
Redundant Paths:
  • linux-bottom → linux-top:
    - Primary: SW → CSR25 → CSR23 → CSR28 → SW2
    - Backup: SW → CSR26 → CSR23 → ...
    - Tertiary: SW → CSR25 → CSR24 → CSR28 → ...

TOPOLOGY
                
                echo ""
                echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
                echo ""
                echo -e "${YELLOW}Tip: Use option 25 for detailed connection matrix${NC}"
                echo -e "${YELLOW}     Use option 62 to generate visual graph${NC}"
                echo ""
            else
                echo -e "${RED}✗${NC} Topology file not found"
            fi
            ;;
        61)
            clear
            echo -e "${CYAN}=== Live LLDP Topology Discovery ===${NC}"
            echo ""
            if [ -f "$ENV_FILE" ] && [ -n "$ES_ENDPOINT" ]; then
                source "$ENV_FILE"
                echo "Querying LLDP data from Elasticsearch..."
                echo ""
                
                # Query last 100 LLDP entries
                LLDP_DATA=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
                    "$ES_ENDPOINT/lldp-topology/_search?size=100&sort=@timestamp:desc" 2>/dev/null)
                
                if echo "$LLDP_DATA" | jq -e '.hits.hits[0]' &>/dev/null; then
                    echo -e "${GREEN}✓${NC} Found LLDP topology data"
                    echo ""
                    echo -e "${YELLOW}Discovered Connections:${NC}"
                    echo "$LLDP_DATA" | jq -r '.hits.hits[]._source | 
                        "\(.router) [\(.local_interface)] <---> \(.neighbor_sysname) [\(.neighbor_port)]"' | 
                        sort -u | head -40
                    
                    echo ""
                    total=$(echo "$LLDP_DATA" | jq -r '.hits.total.value // 0')
                    unique=$(echo "$LLDP_DATA" | jq -r '.hits.hits[]._source | "\(.router)-\(.neighbor_sysname)"' | sort -u | wc -l)
                    echo "Total LLDP records: $total"
                    echo "Unique connections: $unique (expected: 17)"
                    
                    echo ""
                    echo -e "${CYAN}Unique Routers in Topology:${NC}"
                    echo "$LLDP_DATA" | jq -r '.hits.hits[]._source.router' | sort -u
                else
                    echo -e "${YELLOW}⚠${NC} No LLDP data in Elasticsearch yet"
                    echo ""
                    echo "To populate LLDP data:"
                    echo "  1. Ensure LLDP service is running (option 34)"
                    echo "    • sudo systemctl status lldp-export"
                    echo "    • sudo systemctl start lldp-export"
                    echo "  2. Wait 2-3 minutes for data collection"
                    echo "  3. Verify with: sudo journalctl -u lldp-export -f"
                    echo "  4. Try this option again"
                fi
            else
                echo -e "${RED}✗${NC} Elasticsearch not configured"
                echo "Run option 50 to configure Elasticsearch first"
            fi
            ;;
        62)
            clear
            echo -e "${CYAN}=== Generate Topology Graph ===${NC}"
            echo ""
            
            # Check if graphviz is installed
            if ! command -v dot &>/dev/null; then
                echo -e "${YELLOW}⚠${NC} Graphviz not installed"
                echo ""
                read -p "Install graphviz? (yes/no): " install_gv
                if [ "$install_gv" = "yes" ]; then
                    echo "Installing graphviz..."
                    sudo apt-get update && sudo apt-get install -y graphviz
                else
                    echo "Cannot generate graph without graphviz"
                    echo ""
                    read -p "Press Enter to continue..."
                    continue
                fi
            fi
            
            # Generate DOT file
            OUTPUT_DIR="$HOME/ospf-otel-lab/outputs"
            mkdir -p "$OUTPUT_DIR"
            DOT_FILE="$OUTPUT_DIR/topology.dot"
            PNG_FILE="$OUTPUT_DIR/topology.png"
            
            echo "Generating full mesh topology graph..."
            
            cat > "$DOT_FILE" << 'EOF'
digraph ospf_full_mesh {
    rankdir=TB;
    bgcolor="white";
    splines=true;
    overlap=false;
    
    // Global styling
    node [fontname="Arial", fontsize=10, shape=box, style=rounded];
    edge [fontname="Arial", fontsize=8];
    
    // Core router (top level)
    CSR28 [label="CSR28\nCore/Edge\n172.20.20.28", fillcolor="#4A90E2", style=filled, fontcolor=white];
    
    // Distribution layer
    CSR24 [label="CSR24\nDist Left\n172.20.20.24", fillcolor="#87CEEB", style=filled];
    CSR23 [label="CSR23\nDist Right\n172.20.20.23", fillcolor="#87CEEB", style=filled];
    
    // Edge routers
    CSR29 [label="CSR29\nEdge Left\n172.20.20.29", fillcolor="#B0E0E6", style=filled];
    CSR27 [label="CSR27\nEdge Right\n172.20.20.27", fillcolor="#B0E0E6", style=filled];
    
    // VRRP pair
    CSR25 [label="CSR25\nVRRP Active\n172.20.20.25\nVIP: .10.1", fillcolor="#90EE90", style=filled];
    CSR26 [label="CSR26\nVRRP Standby\n172.20.20.26\nVIP: .10.1", fillcolor="#FFD700", style=filled];
    
    // Layer 2 switches
    SW [label="SW\nL2 Bridge\nVLAN 10", fillcolor="#DDA0DD", shape=box, style="filled,rounded"];
    SW2 [label="SW2\nL2 Bridge\nVLAN 20", fillcolor="#DDA0DD", shape=box, style="filled,rounded"];
    
    // End hosts
    LinuxBot [label="linux-bottom\n192.168.10.20", fillcolor="#D3D3D3", shape=component, style=filled];
    LinuxTop [label="linux-top\n192.168.20.100", fillcolor="#D3D3D3", shape=component, style=filled];
    
    // Telemetry
    OTEL [label="OTEL\nCollector", fillcolor="#FFA500", shape=cylinder, style=filled];
    ES [label="Elasticsearch\nServerless", fillcolor="#00BFA5", shape=cylinder, style=filled];
    
    // Core connections (thick lines)
    CSR28 -> CSR24 [label="e1", color="#333333", penwidth=2];
    CSR28 -> CSR23 [label="e2", color="#333333", penwidth=2];
    CSR28 -> SW2 [label="e3", color="#9370DB", penwidth=2];
    
    // Distribution connections
    CSR24 -> CSR29 [label="e2-e1", color="#333333"];
    CSR24 -> CSR23 [label="e3-e3", color="#333333"];
    CSR24 -> CSR26 [label="e4-e3", color="#FF6B6B"];
    CSR24 -> CSR25 [label="e5-e2", color="#FF6B6B"];
    
    CSR23 -> CSR26 [label="e1-e2", color="#FF6B6B"];
    CSR23 -> CSR25 [label="e4-e1", color="#FF6B6B"];
    CSR23 -> CSR27 [label="e5-e1", color="#333333"];
    
    // Edge to VRRP
    CSR29 -> CSR26 [label="e2-e1", color="#666666"];
    CSR27 -> CSR25 [label="e2-e4", color="#666666"];
    
    // VRRP heartbeat (dashed, thick red)
    CSR25 -> CSR26 [label="VRRP\ne3-e4", style=dashed, color="#FF0000", penwidth=3];
    
    // VRRP to access switch
    CSR25 -> SW [label="e5-e1", color="#9370DB"];
    CSR26 -> SW [label="e5-e2", color="#9370DB", style=dashed];
    
    // Access connections
    SW -> LinuxBot [label="e3-e1", color="#0066CC"];
    SW2 -> LinuxTop [label="e2-e1", color="#0066CC"];
    
    // Telemetry (dotted blue)
    {CSR28, CSR24, CSR23, CSR29, CSR27, CSR25, CSR26} -> OTEL [style=dotted, color="#0000FF", label="SNMP"];
    OTEL -> ES [color="#00BFA5", penwidth=2, label="OTLP"];
    
    // Grouping for visual clarity
    subgraph cluster_core {
        label="Core Layer";
        style=dashed;
        color="#4A90E2";
        CSR28;
    }
    
    subgraph cluster_distribution {
        label="Distribution Layer";
        style=dashed;
        color="#87CEEB";
        CSR24; CSR23;
    }
    
    subgraph cluster_vrrp {
        label="VRRP Gateway Pair\nVIP: 192.168.10.1";
        style="filled,rounded";
        fillcolor="#FFFFE0";
        color="#FF6B6B";
        penwidth=2;
        CSR25; CSR26;
    }
    
    subgraph cluster_access_vlan10 {
        label="VLAN 10 (192.168.10.0/24)";
        style=dashed;
        color="#9370DB";
        SW; LinuxBot;
    }
    
    subgraph cluster_access_vlan20 {
        label="VLAN 20 (192.168.20.0/24)";
        style=dashed;
        color="#9370DB";
        SW2; LinuxTop;
    }
    
    subgraph cluster_telemetry {
        label="Telemetry Pipeline";
        style="filled,rounded";
        fillcolor="#FFF8DC";
        color="#FFA500";
        OTEL; ES;
    }
}
EOF

            # Generate PNG
            echo "Rendering graph..."
            dot -Tpng "$DOT_FILE" -o "$PNG_FILE" 2>/dev/null
            
            if [ -f "$PNG_FILE" ]; then
                echo -e "${GREEN}✓${NC} Topology graph generated"
                echo ""
                echo "Files created:"
                echo "  DOT: $DOT_FILE"
                echo "  PNG: $PNG_FILE"
                echo ""
                
                # Show file size
                size=$(du -h "$PNG_FILE" | cut -f1)
                echo "Image size: $size"
                echo ""
                
                # Generate SVG version too
                echo "Generating SVG version..."
                dot -Tsvg "$DOT_FILE" -o "${OUTPUT_DIR}/topology.svg" 2>/dev/null
                if [ -f "${OUTPUT_DIR}/topology.svg" ]; then
                    echo "  SVG: ${OUTPUT_DIR}/topology.svg"
                fi
                
                echo ""
                # Try to open the image
                if command -v xdg-open &>/dev/null; then
                    echo "Opening image with default viewer..."
                    xdg-open "$PNG_FILE" &>/dev/null &
                    echo "✓ Image opened"
                elif command -v open &>/dev/null; then
                    open "$PNG_FILE" &>/dev/null &
                    echo "✓ Image opened"
                else
                    echo "View the image at: $PNG_FILE"
                    echo ""
                    echo "Or use: eog $PNG_FILE"
                fi
            else
                echo -e "${RED}✗${NC} Failed to generate graph"
                echo "Check if graphviz is properly installed"
            fi
            ;;
        63)
            clear
            echo -e "${CYAN}=== Export Topology to JSON ===${NC}"
            echo ""
            
            OUTPUT_DIR="$HOME/ospf-otel-lab/outputs"
            mkdir -p "$OUTPUT_DIR"
            JSON_FILE="$OUTPUT_DIR/topology-$(date +%Y%m%d-%H%M%S).json"
            
            echo "Generating comprehensive topology JSON..."
            
            # Generate comprehensive topology JSON
            cat > "$JSON_FILE" << EOF
{
  "generated": "$(date -Iseconds)",
  "lab_name": "ospf-otel-lab",
  "topology_version": "v21.3",
  "description": "Full mesh OSPF lab with 7 routers, 2 switches, VRRP HA, and telemetry",
  "summary": {
    "total_routers": 7,
    "total_switches": 2,
    "total_hosts": 2,
    "total_links": 17,
    "ospf_area": "0",
    "vrrp_pairs": 1,
    "telemetry_collectors": 1
  },
  "nodes": {
    "routers": [
      {
        "name": "csr28",
        "role": "core-edge",
        "ip": "172.20.20.28",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2", "eth3"],
        "connections": ["csr24", "csr23", "sw2"],
        "container": "clab-ospf-network-csr28",
        "running": $(check_container "clab-ospf-network-csr28" && echo "true" || echo "false")
      },
      {
        "name": "csr24",
        "role": "distribution-left",
        "ip": "172.20.20.24",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5"],
        "connections": ["csr28", "csr29", "csr23", "csr26", "csr25"],
        "container": "clab-ospf-network-csr24",
        "running": $(check_container "clab-ospf-network-csr24" && echo "true" || echo "false")
      },
      {
        "name": "csr23",
        "role": "distribution-right",
        "ip": "172.20.20.23",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5"],
        "connections": ["csr28", "csr24", "csr26", "csr25", "csr27"],
        "container": "clab-ospf-network-csr23",
        "running": $(check_container "clab-ospf-network-csr23" && echo "true" || echo "false")
      },
      {
        "name": "csr29",
        "role": "edge-left",
        "ip": "172.20.20.29",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2"],
        "connections": ["csr24", "csr26"],
        "container": "clab-ospf-network-csr29",
        "running": $(check_container "clab-ospf-network-csr29" && echo "true" || echo "false")
      },
      {
        "name": "csr27",
        "role": "edge-right",
        "ip": "172.20.20.27",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2"],
        "connections": ["csr23", "csr25"],
        "container": "clab-ospf-network-csr27",
        "running": $(check_container "clab-ospf-network-csr27" && echo "true" || echo "false")
      },
      {
        "name": "csr25",
        "role": "vrrp-active",
        "ip": "172.20.20.25",
        "vrrp_vip": "192.168.10.1",
        "vrrp_priority": 110,
        "vrrp_state": "active",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5"],
        "connections": ["csr24", "csr23", "csr26", "csr27", "sw"],
        "container": "clab-ospf-network-csr25",
        "running": $(check_container "clab-ospf-network-csr25" && echo "true" || echo "false")
      },
      {
        "name": "csr26",
        "role": "vrrp-standby",
        "ip": "172.20.20.26",
        "vrrp_vip": "192.168.10.1",
        "vrrp_priority": 100,
        "vrrp_state": "standby",
        "ospf_area": "0",
        "interfaces": ["eth0", "eth1", "eth2", "eth3", "eth4", "eth5"],
        "connections": ["csr24", "csr23", "csr29", "csr25", "sw"],
        "container": "clab-ospf-network-csr26",
        "running": $(check_container "clab-ospf-network-csr26" && echo "true" || echo "false")
      }
    ],
    "switches": [
      {
        "name": "sw",
        "role": "layer2-bridge",
        "vlan": 10,
        "network": "192.168.10.0/24",
        "interfaces": ["eth1", "eth2", "eth3", "br0"],
        "connections": ["csr25", "csr26", "linux-bottom"],
        "container": "clab-ospf-network-sw",
        "running": $(check_container "clab-ospf-network-sw" && echo "true" || echo "false")
      },
      {
        "name": "sw2",
        "role": "layer2-bridge",
        "vlan": 20,
        "network": "192.168.20.0/24",
        "interfaces": ["eth1", "eth2", "br0"],
        "connections": ["csr28", "linux-top"],
        "container": "clab-ospf-network-sw2",
        "running": $(check_container "clab-ospf-network-sw2" && echo "true" || echo "false")
      }
    ],
    "hosts": [
      {
        "name": "linux-bottom",
        "ip": "192.168.10.20",
        "gateway": "192.168.10.1",
        "vlan": 10,
        "switch": "sw",
        "os": "Ubuntu 22.04",
        "container": "clab-ospf-network-linux-bottom",
        "running": $(check_container "clab-ospf-network-linux-bottom" && echo "true" || echo "false")
      },
      {
        "name": "linux-top",
        "ip": "192.168.20.100",
        "gateway": "192.168.20.1",
        "vlan": 20,
        "switch": "sw2",
        "os": "Ubuntu 22.04",
        "container": "clab-ospf-network-linux-top",
        "running": $(check_container "clab-ospf-network-linux-top" && echo "true" || echo "false")
      }
    ],
    "telemetry": [
      {
        "name": "otel-collector",
        "type": "collector",
        "protocol": "SNMP UDP/161",
        "export": "OTLP to Elasticsearch",
        "container": "clab-ospf-network-otel-collector",
        "running": $(check_container "clab-ospf-network-otel-collector" && echo "true" || echo "false")
      },
      {
        "name": "logstash",
        "type": "processor",
        "status": "optional",
        "container": "clab-ospf-network-logstash",
        "running": $(check_container "clab-ospf-network-logstash" && echo "true" || echo "false")
      }
    ]
  },
  "links": [
    {"id": 1, "source": "csr28", "source_if": "eth1", "target": "csr24", "target_if": "eth1", "type": "core"},
    {"id": 2, "source": "csr28", "source_if": "eth2", "target": "csr23", "target_if": "eth2", "type": "core"},
    {"id": 3, "source": "csr28", "source_if": "eth3", "target": "sw2", "target_if": "eth1", "type": "access"},
    {"id": 4, "source": "csr24", "source_if": "eth2", "target": "csr29", "target_if": "eth1", "type": "edge"},
    {"id": 5, "source": "csr24", "source_if": "eth3", "target": "csr23", "target_if": "eth3", "type": "distribution"},
    {"id": 6, "source": "csr24", "source_if": "eth4", "target": "csr26", "target_if": "eth3", "type": "vrrp"},
    {"id": 7, "source": "csr24", "source_if": "eth5", "target": "csr25", "target_if": "eth2", "type": "vrrp"},
    {"id": 8, "source": "csr23", "source_if": "eth1", "target": "csr26", "target_if": "eth2", "type": "vrrp"},
    {"id": 9, "source": "csr23", "source_if": "eth4", "target": "csr25", "target_if": "eth1", "type": "vrrp"},
    {"id": 10, "source": "csr23", "source_if": "eth5", "target": "csr27", "target_if": "eth1", "type": "edge"},
    {"id": 11, "source": "csr29", "source_if": "eth2", "target": "csr26", "target_if": "eth1", "type": "redundant"},
    {"id": 12, "source": "csr27", "source_if": "eth2", "target": "csr25", "target_if": "eth4", "type": "redundant"},
    {"id": 13, "source": "csr26", "source_if": "eth4", "target": "csr25", "target_if": "eth3", "type": "vrrp-heartbeat"},
    {"id": 14, "source": "csr25", "source_if": "eth5", "target": "sw", "target_if": "eth1", "type": "access"},
    {"id": 15, "source": "csr26", "source_if": "eth5", "target": "sw", "target_if": "eth2", "type": "access-backup"},
    {"id": 16, "source": "sw", "source_if": "eth3", "target": "linux-bottom", "target_if": "eth1", "type": "host"},
    {"id": 17, "source": "sw2", "source_if": "eth2", "target": "linux-top", "target_if": "eth1", "type": "host"}
  ],
  "networks": [
    {
      "name": "VLAN 10",
      "subnet": "192.168.10.0/24",
      "gateway": "192.168.10.1",
      "type": "VRRP",
      "active_router": "csr25",
      "standby_router": "csr26",
      "switch": "sw"
    },
    {
      "name": "VLAN 20",
      "subnet": "192.168.20.0/24",
      "gateway": "192.168.20.1",
      "type": "Standard",
      "router": "csr23",
      "switch": "sw2"
    },
    {
      "name": "Management",
      "subnet": "172.20.20.0/24",
      "type": "OSPF Area 0",
      "description": "Router interconnects"
    }
  ],
  "vrrp": {
    "virtual_ip": "192.168.10.1",
    "active_router": {
      "name": "csr25",
      "priority": 110,
      "preempt": true,
      "interface": "eth5"
    },
    "standby_router": {
      "name": "csr26",
      "priority": 100,
      "preempt": true,
      "interface": "eth5"
    },
    "heartbeat_link": {
      "interface_active": "eth3",
      "interface_standby": "eth4"
    }
  }
}
EOF

            echo -e "${GREEN}✓${NC} Topology exported to JSON"
            echo ""
            echo "File: $JSON_FILE"
            echo ""
            
            # Show file size
            size=$(du -h "$JSON_FILE" | cut -f1)
            echo "File size: $size"
            echo ""
            
            echo "Preview (first 50 lines):"
            cat "$JSON_FILE" | jq '.' 2>/dev/null | head -50 || cat "$JSON_FILE" | head -50
            echo "..."
            echo ""
            echo "To view full file:"
            echo "  cat $JSON_FILE | jq '.'"
            echo ""
            echo "To query specific sections:"
            echo "  cat $JSON_FILE | jq '.nodes.routers'"
            echo "  cat $JSON_FILE | jq '.links'"
            echo "  cat $JSON_FILE | jq '.vrrp'"
            ;;
        64)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/status.sh" ]; then
                $HOME/ospf-otel-lab/scripts/status.sh
            else
                echo -e "${CYAN}=== Lab Status Summary ===${NC}"
                echo ""
                echo -e "${YELLOW}Containers:${NC}"
                docker ps --filter "name=clab-ospf-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
                
                echo ""
                echo -e "${YELLOW}SNMP Status:${NC}"
                for i in 23 24 25 26 27 28 29; do
                    echo -n "  csr$i: "
                    timeout 2 snmpget -v2c -c public 172.20.20.$i 1.3.6.1.2.1.1.1.0 &>/dev/null && \
                        echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}"
                done
                
                if [ -f "$ENV_FILE" ]; then
                    source "$ENV_FILE"
                    echo ""
                    echo -e "${YELLOW}Elasticsearch:${NC}"
                    if curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" &>/dev/null; then
                        echo -e "  ${GREEN}✓${NC} Connected"
                        
                        # Show document counts
                        metrics_count=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" | jq -r '.count // 0')
                        lldp_count=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/lldp-topology/_count" | jq -r '.count // 0')
                        
                        echo "  Metrics documents: $metrics_count"
                        echo "  LLDP documents: $lldp_count"
                    else
                        echo -e "  ${RED}✗${NC} Not connected"
                    fi
                fi
            fi
            ;;
        65)
            clear
            echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
            echo -e "${CYAN}            DETAILED CONNECTION MATRIX                  ${NC}"
            echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
            echo ""
            cat << 'MATRIX'
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬────────┐
│          │  CSR28   │  CSR24   │  CSR23   │  CSR29   │  CSR27   │  CSR25   │  CSR26   │  SW/2  │
├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┼────────┤
│  CSR28   │    -     │ e1↔e1 ✓  │ e2↔e2 ✓  │    -     │    -     │    -     │    -     │ e3→sw2 │
│  CSR24   │ e1↔e1 ✓  │    -     │ e3↔e3 ✓  │ e2↔e1 ✓  │    -     │ e5↔e2 ✓  │ e4↔e3 ✓  │   -    │
│  CSR23   │ e2↔e2 ✓  │ e3↔e3 ✓  │    -     │    -     │ e5↔e1 ✓  │ e4↔e1 ✓  │ e1↔e2 ✓  │   -    │
│  CSR29   │    -     │ e1↔e2 ✓  │    -     │    -     │    -     │    -     │ e2↔e1 ✓  │   -    │
│  CSR27   │    -     │    -     │ e1↔e5 ✓  │    -     │    -     │ e2↔e4 ✓  │    -     │   -    │
│  CSR25   │    -     │ e2↔e5 ✓  │ e1↔e4 ✓  │    -     │ e4↔e2 ✓  │    -     │ e3↔e4 ⚡  │ e5→sw  │
│  CSR26   │    -     │ e3↔e4 ✓  │ e2↔e1 ✓  │ e1↔e2 ✓  │    -     │ e4↔e3 ⚡  │    -     │ e5→sw  │
│   SW     │    -     │    -     │    -     │    -     │    -     │ e1↔e5    │ e2↔e5    │ e3→bot │
│   SW2    │ e1↔e3    │    -     │    -     │    -     │    -     │    -     │    -     │ e2→top │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴────────┘

Legend:
  ✓ = OSPF Neighbor
  ⚡ = VRRP Heartbeat
  → = L2 Access Link
  - = No Direct Connection

┌─────────────────────────────────────────────────────────────────┐
│                      CONNECTION SUMMARY                         │
├─────────────────────────────────────────────────────────────────┤
│ CSR28 (Core):        3 links (CSR24, CSR23, SW2)               │
│ CSR24 (Dist-L):      5 links (CSR28, CSR29, CSR23, CSR25, 26)  │
│ CSR23 (Dist-R):      5 links (CSR28, CSR24, CSR27, CSR25, 26)  │
│ CSR29 (Edge-L):      2 links (CSR24, CSR26)                     │
│ CSR27 (Edge-R):      2 links (CSR23, CSR25)                     │
│ CSR25 (VRRP-Act):    5 links (CSR24, CSR23, CSR27, CSR26, SW)  │
│ CSR26 (VRRP-Stby):   5 links (CSR24, CSR23, CSR29, CSR25, SW)  │
│ SW (VLAN10):         3 links (CSR25, CSR26, linux-bottom)      │
│ SW2 (VLAN20):        2 links (CSR28, linux-top)                 │
├─────────────────────────────────────────────────────────────────┤
│ Total Physical Links: 17                                        │
│ OSPF Links: 15                                                   │
│ L2 Access Links: 4                                              │
│ VRRP Heartbeat: 1 (dedicated)                                   │
└─────────────────────────────────────────────────────────────────┘

Redundancy Analysis:
┌──────────────────────────────────────────────────────────────┐
│ Path: linux-bottom → linux-top                               │
├──────────────────────────────────────────────────────────────┤
│ Primary:   SW → CSR25 → CSR23 → CSR28 → SW2                 │
│ Backup 1:  SW → CSR26 → CSR23 → CSR28 → SW2                 │
│ Backup 2:  SW → CSR25 → CSR24 → CSR28 → SW2                 │
│ Backup 3:  SW → CSR26 → CSR24 → CSR28 → SW2                 │
│ Backup 4:  SW → CSR25 → CSR27 → CSR23 → CSR28 → SW2         │
└──────────────────────────────────────────────────────────────┘

VRRP Mesh (CSR25↔CSR26):
┌──────────────────────────────────────────────────────────────┐
│ • Direct heartbeat: eth3↔eth4 (dedicated)                    │
│ • Via CSR24: eth2↔eth5 and eth3↔eth4                         │
│ • Via CSR23: eth1↔eth4 and eth2↔eth1                         │
│ • Access: Both connect to SW (eth5)                           │
│ • Total connections: 4 paths between VRRP pair               │
└──────────────────────────────────────────────────────────────┘
MATRIX
            ;;
        
        # ========================================
        # CONFIGURATION (70-76)
        # ========================================
        70)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/install-snmp-lldp.sh" ]; then
                $HOME/ospf-otel-lab/scripts/install-snmp-lldp.sh
            else
                echo "Script install-snmp-lldp.sh not found"
                echo ""
                echo "Use option 39 to restart SNMP + LLDP manually"
            fi
            ;;
        71)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/create-otel-config-fast-mode.sh" ]; then
                $HOME/ospf-otel-lab/scripts/create-otel-config-fast-mode.sh
                echo ""
                echo "Restarting OTEL Collector..."
                docker restart clab-ospf-network-otel-collector
                echo "Wait 30 seconds..."
                sleep 30
                echo "✓ Done"
            else
                echo "Script create-otel-config-fast-mode.sh not found"
            fi
            ;;
        72)
            docker restart clab-ospf-network-otel-collector
            echo "✓ OTEL Collector restarted. Wait 30 seconds for initialization..."
            ;;
        73)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/setup-lldp-service.sh" ]; then
                $HOME/ospf-otel-lab/scripts/setup-lldp-service.sh
            else
                echo "Script setup-lldp-service.sh not found"
            fi
            ;;
        74)
            docker restart clab-ospf-network-logstash
            echo "✓ Logstash restarted. Wait 30 seconds for initialization..."
            ;;
        75)
            docker exec clab-ospf-network-logstash /usr/share/logstash/bin/logstash --config.test_and_exit -f /usr/share/logstash/pipeline/netflow.conf 2>/dev/null || echo "Config test failed or file missing"
            ;;
        76)
            clear
            echo -e "${CYAN}=== Current .env Configuration ===${NC}"
            echo ""
            if [ -f "$ENV_FILE" ]; then
                cat "$ENV_FILE"
            else
                echo "✗ .env file not found"
                echo "Run option 50 to configure Elasticsearch"
            fi
            ;;
        
        # ========================================
        # ADVANCED (80-83)
        # ========================================
        80)
            clear
            if [ -f "$HOME/ospf-otel-lab/scripts/emergency-diagnostic.sh" ]; then
                $HOME/ospf-otel-lab/scripts/emergency-diagnostic.sh
            else
                echo "Script emergency-diagnostic.sh not found"
            fi
            ;;
        81)
            clear
            echo -e "${CYAN}=== Container Health Check ===${NC}"
            echo ""
            docker ps --filter "name=clab-ospf-network" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
            ;;
        82)
            clear
            echo -e "${CYAN}=== Viewing All Container Logs ===${NC}"
            echo ""
            for container in $(docker ps --filter "name=clab-ospf-network" --format "{{.Names}}" | sort); do
                echo -e "${YELLOW}━━━ ${container#clab-ospf-network-} ━━━${NC}"
                docker logs --tail 10 "$container" 2>&1 | head -10
                echo ""
            done
            ;;
        83)
            clear
            echo "Restarting all services..."
            echo ""
            docker restart clab-ospf-network-otel-collector
            echo "  ✓ OTEL Collector"
            docker restart clab-ospf-network-logstash
            echo "  ✓ Logstash"
            sudo systemctl restart lldp-export 2>/dev/null && echo "  ✓ LLDP service" || echo "  ⚠ LLDP service not installed"
            echo ""
            echo "Wait 60 seconds for services to initialize..."
            ;;
        
        # ========================================
        # CLEANUP (90-91)
        # ========================================
        90)
            clear
            echo -e "${RED}WARNING: This will destroy the lab!${NC}"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                echo "Destroying lab..."
                sudo clab destroy -t $HOME/ospf-otel-lab/ospf-network.clab.yml --cleanup
                if systemctl is-active --quiet lldp-export 2>/dev/null; then
                    sudo systemctl stop lldp-export
                    echo "✓ LLDP service stopped"
                fi
                echo "✓ Lab destroyed"
            else
                echo "Cancelled"
            fi
            ;;
        91)
            clear
            echo -e "${RED}WARNING: This will destroy EVERYTHING (lab + logs + configs)!${NC}"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                echo "Full cleanup..."
                sudo clab destroy -t $HOME/ospf-otel-lab/ospf-network.clab.yml --cleanup 2>/dev/null
                rm -f $HOME/ospf-otel-lab/logs/*.log
                rm -f $HOME/ospf-otel-lab/configs/otel/otel-collector.yml.backup-*
                if systemctl is-active --quiet lldp-export 2>/dev/null; then
                    sudo systemctl stop lldp-export
                    sudo systemctl disable lldp-export
                fi
                echo "✓ Full cleanup complete"
            else
                echo "Cancelled"
            fi
            ;;
        
        # ========================================
        # EXIT
        # ========================================
        0) 
            echo "Exiting..."
            exit 0
            ;;
        
        # ========================================
        # INVALID
        # ========================================
        *) 
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read -r
    clear
done
