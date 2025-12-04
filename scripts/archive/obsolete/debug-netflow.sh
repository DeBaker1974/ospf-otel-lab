#!/bin/bash

echo "=================================================="
echo "  NetFlow Deep Diagnostic"
echo "=================================================="
echo ""

router="csr28"

echo "=== Testing on: $router ==="
echo ""

docker exec clab-ospf-network-$router sh -c '
    echo "1. Check softflowd installation:"
    which softflowd
    softflowd -v 2>&1 || echo "Version command failed"
    echo ""
    
    echo "2. Check available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk "{print \$2}" | sed "s/:$//"
    echo ""
    
    echo "3. Check interface status:"
    for iface in eth0 eth1 eth2 eth3 eth4 eth5; do
        if ip link show $iface >/dev/null 2>&1; then
            state=$(ip link show $iface | grep -oP "state \K\w+")
            printf "  %-8s: %s\n" "$iface" "$state"
        fi
    done
    echo ""
    
    echo "4. Test softflowd manually on eth1:"
    softflowd -i eth1 -n 172.20.20.1:2055 -v 9 -D 2>&1
    echo ""
    
    echo "5. Check for permission issues:"
    ls -la /tmp/softflowd*.pid 2>/dev/null || echo "  No pid files"
    echo ""
    
    echo "6. Try running in foreground (debug mode):"
    timeout 5 softflowd -i eth1 -n 172.20.20.1:2055 -v 9 -d -D 2>&1 || echo "  Command timed out or failed"
    echo ""
    
    echo "7. Check if pcap is working:"
    timeout 2 tcpdump -i eth1 -c 5 2>&1 || echo "  tcpdump failed"
    echo ""
    
    echo "8. Check network connectivity to Logstash:"
    ping -c 3 172.20.20.1 2>&1
    echo ""
    
    echo "9. Test UDP connectivity:"
    echo "test" | nc -u -w1 172.20.20.1 2055 2>&1
    echo ""
'

echo "=================================================="
