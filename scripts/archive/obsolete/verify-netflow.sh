#!/bin/bash

echo "=================================================="
echo "  NetFlow Verification"
echo "=================================================="
echo ""

echo "1. Router Status:"
echo "----------------------------------------"
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    printf "  %-8s: " "$router"
    count=$(docker exec clab-ospf-network-$router ps | grep softflowd | grep -v grep | wc -l)
    if [ $count -gt 0 ]; then
        pid=$(docker exec clab-ospf-network-$router pgrep softflowd)
        echo "✓ Running (PID: $pid)"
    else
        echo "✗ Not running"
    fi
done

echo ""
echo "2. Network Connectivity Test:"
echo "----------------------------------------"
docker exec clab-ospf-network-csr28 sh -c '
    echo "  Testing UDP connection to Logstash..."
    echo "test" | nc -u -w1 172.20.20.1 2055 && echo "  ✓ Reachable" || echo "  ✗ Not reachable"
'

echo ""
echo "3. Logstash Listener Status:"
echo "----------------------------------------"
if docker exec clab-ospf-network-logstash netstat -uln 2>/dev/null | grep -q 2055; then
    echo "  ✓ Logstash listening on UDP 2055"
else
    echo "  ✗ Logstash NOT listening on UDP 2055"
fi

echo ""
echo "4. Recent Logstash Activity (last 30 lines):"
echo "----------------------------------------"
docker logs --tail 30 clab-ospf-network-logstash 2>/dev/null | tail -10

echo ""
echo "=================================================="
