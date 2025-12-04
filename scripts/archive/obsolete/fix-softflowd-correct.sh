#!/bin/bash

echo "=================================================="
echo "  Configuring softflowd (Correct Syntax)"
echo "=================================================="
echo ""

configure_router() {
    local router=$1
    echo "=== Configuring: $router ==="
    
    docker exec clab-ospf-network-$router sh -c '
        # Kill existing
        pkill -9 softflowd 2>/dev/null || true
        rm -f /tmp/softflowd*.pid
        sleep 2
        
        # Start with proper timeout syntax
        softflowd \
            -i any \
            -n 172.20.20.1:2055 \
            -v 9 \
            -t maxlife=10 \
            -t expint=5 \
            -T full \
            -L 128 \
            -p /tmp/softflowd.pid \
            -d
        
        sleep 2
        
        if pgrep softflowd >/dev/null; then
            echo "  ✓ Started (maxlife=10s, expint=5s)"
            ps | grep softflowd | grep -v grep | head -1
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
    if configure_router "$router"; then
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
    echo "Timeout configuration:"
    echo "  - maxlife: 10 seconds (maximum flow lifetime)"
    echo "  - expint: 5 seconds (export interval)"
    echo ""
    echo "✅ NetFlow should export within 10-15 seconds!"
    echo ""
    echo "Next: Run traffic test with:"
    echo "  ./test-netflow-realtime.sh"
fi

echo "=================================================="
