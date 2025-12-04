#!/bin/bash

echo "=================================================="
echo "  Common NetFlow Issues Checker"
echo "=================================================="
echo ""

echo "1. Check if Logstash is listening on UDP 2055..."
docker exec clab-ospf-network-logstash netstat -uln 2>/dev/null | grep 2055
if [ $? -eq 0 ]; then
    echo "   ✓ Logstash listening"
else
    echo "   ✗ Logstash NOT listening - restart pipeline!"
fi

echo ""
echo "2. Check container network connectivity..."
docker exec clab-ospf-network-csr28 ping -c 3 172.20.20.1 | tail -2

echo ""
echo "3. Check if softflowd can resolve collector..."
docker exec clab-ospf-network-csr28 nslookup 172.20.20.1 2>/dev/null || echo "   DNS check skipped"

echo ""
echo "4. Check time sync (flows need proper timestamps)..."
docker exec clab-ospf-network-csr28 date
docker exec clab-ospf-network-logstash date

echo ""
echo "5. Check for interface issues..."
docker exec clab-ospf-network-csr28 ip link show | grep -E "state UP|state DOWN"

echo ""
echo "=================================================="
