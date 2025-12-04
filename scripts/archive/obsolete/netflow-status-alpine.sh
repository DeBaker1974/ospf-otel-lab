#!/bin/bash

echo "=================================================="
echo "  NetFlow Status - Alpine Routers"
echo "=================================================="
echo ""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Router Status:"
echo "----------------------------------------"
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    printf "  %-8s: " "$router"
    if docker ps | grep -q "clab-ospf-network-$router"; then
        # Count softflowd processes (one per interface)
        count=$(docker exec clab-ospf-network-$router ps | grep softflowd | grep -v grep | wc -l)
        if [ $count -gt 0 ]; then
            echo -e "${GREEN}✓ Running${NC} ($count processes)"
            # Show details
            docker exec clab-ospf-network-$router ps | grep softflowd | grep -v grep | sed 's/^/            /'
        else
            echo -e "${RED}✗ Not running${NC}"
        fi
    else
        echo -e "${RED}✗ Router offline${NC}"
    fi
done

echo ""
echo "Interface Details (csr28 example):"
echo "----------------------------------------"
if docker ps | grep -q "clab-ospf-network-csr28"; then
    docker exec clab-ospf-network-csr28 sh -c '
        for iface in eth1 eth2 eth3 eth4 eth5; do
            if ip link show $iface >/dev/null 2>&1; then
                status=$(ip link show $iface | grep "state UP" && echo "UP" || echo "DOWN")
                pid=$(cat /tmp/softflowd-${iface}.pid 2>/dev/null || echo "none")
                printf "  %-6s: %s (PID: %s)\n" "$iface" "$status" "$pid"
            fi
        done
    '
fi

echo ""
echo "Logstash Status:"
echo "----------------------------------------"
if docker ps | grep -q logstash; then
    echo -e "  ${GREEN}✓ Running${NC}"
    echo "  Port: $(docker port clab-ospf-network-logstash 2055 2>/dev/null || echo 'Not mapped')"
else
    echo -e "  ${RED}✗ Not running${NC}"
fi

echo ""
echo "Recent NetFlow Activity:"
echo "----------------------------------------"
docker logs --tail 30 clab-ospf-network-logstash 2>/dev/null | \
    grep -i "netflow\|flow\|2055" | tail -10 || \
    echo "  No recent NetFlow messages"

echo ""
echo "=================================================="
echo "Commands:"
echo "  Restart all:    ./restart-netflow-alpine.sh"
echo "  Generate test:  ./generate-netflow-traffic.sh"
echo "  Watch Logstash: docker logs -f clab-ospf-network-logstash"
echo "=================================================="
