#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load environment
ENV_FILE="$HOME/ospf-otel-lab/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

clear
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}   OSPF OTEL Lab - Menu v13.0${NC}"
echo -e "${CYAN}  FAST MODE + LOGSTASH NetFlow${NC}"
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
    echo "  1)  $(status_indicator clab-ospf-network-csr28) CSR28 - Core/Edge (10.255.0.28)"
    echo "  2)  $(status_indicator clab-ospf-network-csr24) CSR24 - Distribution Left (10.255.0.24)"
    echo "  3)  $(status_indicator clab-ospf-network-csr23) CSR23 - Distribution Right (10.255.0.23)"
    echo "  4)  $(status_indicator clab-ospf-network-csr25) CSR25 - VRRP Active (10.255.0.25)"
    echo "  5)  $(status_indicator clab-ospf-network-csr26) CSR26 - VRRP Standby (10.255.0.26)"
    echo "  6)  $(status_indicator clab-ospf-network-csr27) CSR27 - Edge Right (10.255.0.27)"
    echo "  7)  $(status_indicator clab-ospf-network-csr29) CSR29 - Edge Left (10.255.0.29)"
    echo ""
    echo -e "${YELLOW}END DEVICES:${NC}"
    echo "  8)  $(status_indicator clab-ospf-network-win-bottom) Win-Bottom (192.168.10.10)"
    echo "  9)  $(status_indicator clab-ospf-network-linux-bottom) Linux-Bottom (192.168.10.20)"
    echo "  10) $(status_indicator clab-ospf-network-node1) Node1 (192.168.20.100)"
    echo ""
    echo -e "${YELLOW}TELEMETRY:${NC}"
    echo "  11) $(status_indicator clab-ospf-network-otel-collector) OTEL Collector logs (live)"
    echo "  12) $(status_indicator clab-ospf-network-logstash) Logstash logs (live)"
    echo "  13) $(status_indicator clab-ospf-network-logstash) Logstash shell access"
    echo ""
    echo -e "${YELLOW}NETWORK COMMANDS:${NC}"
    echo "  20) Show OSPF neighbors"
    echo "  21) Show VRRP status"
    echo "  22) Show routing tables"
    echo "  23) Test connectivity"
    echo "  24) Run network diagnostics"
    echo ""
    echo -e "${YELLOW}LLDP COMMANDS:${NC}"
    echo "  30) Show LLDP neighbors"
    echo "  31) LLDP status overview"
    echo "  32) LLDP service logs"
    echo "  33) Restart LLDP service"
    echo "  34) Test LLDP manually (30s)"
    echo ""
    echo -e "${YELLOW}NETFLOW QUICK START:${NC}"
    echo "  35) ${GREEN}★${NC} Start NetFlow (master script)"
    echo "  36) Check NetFlow status"
    echo "  37) Stop all NetFlow collectors"
    echo "  38) Restart NetFlow (stop + start)"
    echo ""
    echo -e "${YELLOW}NETFLOW MONITORING:${NC}"
    echo "  40) Query NetFlow data (last 10)"
    echo "  41) NetFlow stats summary"
    echo "  42) Top talkers (by bandwidth)"
    echo "  43) Protocol distribution"
    echo "  44) NetFlow document count"
    echo ""
    echo -e "${YELLOW}ELASTICSEARCH COMMANDS:${NC}"
    echo "  50) Configure Elasticsearch"
    echo "  51) Test Elasticsearch connection"
    echo "  52) Query SNMP metrics (sample)"
    echo "  53) Query LLDP topology (sample)"
    echo "  54) List all metric types"
    echo "  55) Show indices"
    echo "  56) Show collection rate"
    echo ""
    echo -e "${YELLOW}TOPOLOGY & VISUALIZATION:${NC}"
    echo "  60) Show network topology (ASCII)"
    echo "  61) Live topology discovery"
    echo "  62) Generate topology graph (Graphviz)"
    echo "  63) Export topology to JSON"
    echo "  64) Lab status summary"
    echo ""
    echo -e "${YELLOW}CONFIGURATION:${NC}"
    echo "  70) Reinstall SNMP + LLDP"
    echo "  71) Regenerate OTEL config (ALL METRICS)"
    echo "  72) Restart OTEL Collector"
    echo "  73) Setup LLDP export service"
    echo "  74) Restart Logstash"
    echo "  75) Check Logstash config"
    echo ""
    echo -e "${YELLOW}CLEANUP:${NC}"
    echo "  80) Quick cleanup (destroy lab)"
    echo ""
    echo "  0)  Exit"
    echo ""
    echo -ne "${CYAN}Select option: ${NC}"
    read -r choice

    case $choice in
        # Router access
        1) docker exec -it clab-ospf-network-csr28 vtysh ;;
        2) docker exec -it clab-ospf-network-csr24 vtysh ;;
        3) docker exec -it clab-ospf-network-csr23 vtysh ;;
        4) docker exec -it clab-ospf-network-csr25 vtysh ;;
        5) docker exec -it clab-ospf-network-csr26 vtysh ;;
        6) docker exec -it clab-ospf-network-csr27 vtysh ;;
        7) docker exec -it clab-ospf-network-csr29 vtysh ;;
        
        # End devices
        8) docker exec -it clab-ospf-network-win-bottom sh ;;
        9) docker exec -it clab-ospf-network-linux-bottom sh ;;
        10) docker exec -it clab-ospf-network-node1 sh ;;
        
        # Telemetry
        11) docker logs --tail 100 -f clab-ospf-network-otel-collector ;;
        12) docker logs --tail 100 -f clab-ospf-network-logstash ;;
        13) docker exec -it clab-ospf-network-logstash bash ;;
        
        # Network commands
        20) clear; echo "=== OSPF Neighbors ==="; for r in csr28 csr24 csr23 csr25 csr26 csr27 csr29; do echo ""; echo "$r:"; docker exec clab-ospf-network-$r vtysh -c "show ip ospf neighbor"; done ;;
        21) clear; echo "=== VRRP Status ==="; docker exec clab-ospf-network-csr25 vtysh -c "show vrrp"; echo ""; docker exec clab-ospf-network-csr26 vtysh -c "show vrrp" ;;
        22) clear; echo "=== Routing Tables ==="; for r in csr28 csr25; do echo ""; echo "$r:"; docker exec clab-ospf-network-$r vtysh -c "show ip route"; done ;;
        23) clear; docker exec clab-ospf-network-win-bottom ping -c 3 192.168.20.100 ;;
        24) clear; ./scripts/emergency-diagnostic.sh 2>/dev/null || echo "Script not found" ;;
        
        # LLDP commands
        30) clear; ./scripts/show-lldp-neighbors.sh ;;
        31) clear; ./scripts/lldp-status.sh ;;
        32) tail -f ~/ospf-otel-lab/logs/lldp-export.log ;;
        33) sudo systemctl restart lldp-export; echo "LLDP service restarted" ;;
        34) clear; echo "Running manual LLDP collection for 30 seconds..."; timeout 30s ./scripts/lldp-to-elasticsearch.sh ;;
        
        # NetFlow Quick Start
        35) clear; ./scripts/start-netflow.sh ;;
        36) clear; 
            echo "=== NetFlow Status ==="
            echo ""
            echo "Softflowd processes per router:"
            for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do 
                count=$(docker exec clab-ospf-network-$r pgrep softflowd 2>/dev/null | wc -l)
                printf "  %-10s %d processes\n" "$r:" "$count"
            done
            echo ""
            echo "Logstash IP: $(docker inspect clab-ospf-network-logstash --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
            echo ""
            if [ -f .env ]; then
                source .env
                recent=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_count" -H 'Content-Type: application/json' -d '{"query":{"range":{"@timestamp":{"gte":"now-5m"}}}}' 2>/dev/null | jq -r '.count // 0')
                echo "NetFlow docs (last 5 min): $recent"
            fi
            ;;
        37) clear; 
            echo "Stopping all NetFlow collectors..."
            for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do 
                docker exec clab-ospf-network-$r pkill softflowd 2>/dev/null
                printf "  %-10s stopped\n" "$r:"
            done
            echo "✓ All stopped"
            ;;
        38) clear;
            echo "Restarting NetFlow..."
            echo ""
            echo "Step 1: Stopping existing collectors..."
            for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do 
                docker exec clab-ospf-network-$r pkill softflowd 2>/dev/null
            done
            echo "✓ Stopped"
            echo ""
            echo "Step 2: Starting NetFlow..."
            ./scripts/start-netflow.sh
            ;;
        
        # NetFlow Monitoring
        40) clear; 
            source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_search?size=10&sort=@timestamp:desc" -H 'Content-Type: application/json' | jq '.hits.hits[]._source | {time: .["@timestamp"], src: .source.ip, dst: .destination.ip, bytes: .network.bytes, proto: .network.transport}' || echo "Error querying ES"
            ;;
        41) clear; 
            source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_search" -H 'Content-Type: application/json' -d '{"size":0,"aggs":{"by_src":{"terms":{"field":"source.ip","size":10,"order":{"total_bytes":"desc"}},"aggs":{"total_bytes":{"sum":{"field":"network.bytes"}}}}}}' | jq '.aggregations.by_src.buckets[] | {ip: .key, flows: .doc_count, bytes: .total_bytes.value}' || echo "Error querying ES"
            ;;
        42) clear;
            echo "=== Top 10 Talkers by Bandwidth ==="
            source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_search" -H 'Content-Type: application/json' -d '{"size":0,"aggs":{"top_talkers":{"terms":{"field":"source.ip","size":10,"order":{"total_bytes":"desc"}},"aggs":{"total_bytes":{"sum":{"field":"network.bytes"}}}}}}' | jq -r '.aggregations.top_talkers.buckets[] | "\(.key): \(.total_bytes.value / 1024 / 1024 | floor) MB"' || echo "Error"
            ;;
        43) clear;
            echo "=== Protocol Distribution ==="
            source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_search" -H 'Content-Type: application/json' -d '{"size":0,"aggs":{"protocols":{"terms":{"field":"network.transport","size":20}}}}' | jq -r '.aggregations.protocols.buckets[] | "\(.key): \(.doc_count) flows"' || echo "Error"
            ;;
        44) clear;
            source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/logs-netflow.log-default/_count" | jq -r '"Total NetFlow documents: \(.count)"' || echo "Error"
            ;;
        
        # Elasticsearch commands
        50) clear; ./scripts/configure-elasticsearch.sh ;;
        51) clear; source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" | jq '.' || echo "Not configured" ;;
        52) clear; source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_search?size=10&sort=@timestamp:desc" | jq '.hits.hits[]._source | {time: .["@timestamp"], host: .host.name, metric: .metric.name}' ;;
        53) clear; source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/lldp-topology/_search?size=10&sort=@timestamp:desc" | jq '.hits.hits[]._source | {time: .["@timestamp"], router: .router, interface: .local_interface, neighbor: .neighbor_sysname}' ;;
        54) clear; ./scripts/list-all-metrics.sh ;;
        55) clear; source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/_cat/indices/*?v&s=index" ;;
        56) clear; source .env 2>/dev/null && curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" -H 'Content-Type: application/json' -d '{"query":{"range":{"@timestamp":{"gte":"now-1m"}}}}' | jq -r '"Last minute: \(.count) documents"' ;;
        
        # Topology
        60) clear; ./scripts/show-topology.sh ;;
        61) clear; ./scripts/show-topology-live.sh 2>/dev/null || echo "Script not found" ;;
        62) clear; ./scripts/generate-topology-graph.sh 2>/dev/null || echo "Script not found" ;;
        63) clear; ./scripts/export-topology-json.sh 2>/dev/null || echo "Script not found" ;;
        64) clear; ./scripts/status.sh ;;
        
        # Configuration
        70) clear; ./scripts/install-snmp-lldp.sh ;;
        71) clear; ./scripts/create-otel-config-fast-mode.sh; echo ""; echo "Restarting OTEL..."; docker restart clab-ospf-network-otel-collector; echo "Wait 30 seconds..."; sleep 30; echo "✓ Done" ;;
        72) docker restart clab-ospf-network-otel-collector; echo "Restarted. Wait 30 seconds..." ;;
        73) clear; ./scripts/setup-lldp-service.sh ;;
        74) docker restart clab-ospf-network-logstash; echo "Logstash restarted. Wait 30 seconds..." ;;
        75) docker exec clab-ospf-network-logstash /usr/share/logstash/bin/logstash --config.test_and_exit -f /usr/share/logstash/pipeline/netflow.conf ;;
        
        # Cleanup
        80) clear; echo "Destroying lab..."; sudo clab destroy -t ospf-network.clab.yml --cleanup; if systemctl is-active --quiet lldp-export 2>/dev/null; then sudo systemctl stop lldp-export; fi ;;
        
        # Exit
        0) echo "Exiting..."; exit 0 ;;
        
        # Invalid
        *) echo -e "${RED}Invalid option${NC}" ;;
    esac
    
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read -r
    clear
done
