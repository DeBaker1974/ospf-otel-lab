#!/bin/bash

echo "=================================================="
echo "  Configuring softflowd for Faster Export"
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
        
        # Start with aggressive timeouts
        softflowd \
            -i any \
            -n 172.20.20.1:2055 \
            -v 9 \
            -t maxlife=10 \
            -t expint=5 \
            -t maxidle=5 \
            -T full \
            -L 128 \
            -p /tmp/softflowd.pid \
            -d
        
        sleep 2
        
        if pgrep softflowd >/dev/null; then
            echo "  ✓ Started with 10s flow timeout"
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
    echo "Configuration changes:"
    echo "  - maxlife: 10 seconds (flow max lifetime)"
    echo "  - expint: 5 seconds (export interval)"  
    echo "  - maxidle: 5 seconds (idle timeout)"
    echo ""
    echo "NetFlow packets should appear within 10-15 seconds!"
fi

echo "=================================================="
