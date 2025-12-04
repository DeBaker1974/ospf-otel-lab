#!/bin/bash

echo "=================================================="
echo "  Restart All NetFlow Exporters"
echo "=================================================="
echo ""

restart_router() {
    local router=$1
    echo "=== $router ==="
    
    docker exec clab-ospf-network-$router sh -c '
        # Kill all softflowd processes
        pkill -9 softflowd 2>/dev/null
        rm -f /tmp/softflowd*.pid /var/run/softflowd.*
        sleep 2
        
        # Start fresh
        softflowd \
            -i any \
            -n 172.20.20.1:2055 \
            -v 9 \
            -t maxlife=60 \
            -t expint=30 \
            -d \
            -p /tmp/softflowd.pid
        
        sleep 2
        
        # Verify
        if pgrep softflowd >/dev/null; then
            echo "  ✓ Started successfully"
            ps aux | grep softflowd | grep -v grep | head -1
        else
            echo "  ✗ Failed to start"
            return 1
        fi
    '
    
    return $?
}

success=0
failed=0

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if restart_router "$router"; then
        ((success++))
    else
        ((failed++))
    fi
    echo ""
done

echo "=================================================="
echo "Summary: ✓ $success/7  ✗ $failed/7"
echo ""

if [ $success -gt 0 ]; then
    echo "Waiting 30 seconds for flow accumulation..."
    sleep 30
    
    echo ""
    echo "Checking Logstash for new flows..."
    docker logs --tail 30 clab-ospf-network-logstash 2>&1 | grep -E "netflow|source.ip" | tail -10
fi

echo "=================================================="
