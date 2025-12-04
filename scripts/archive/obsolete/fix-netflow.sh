#!/bin/bash

echo "=================================================="
echo "  Fixing NetFlow Configuration"
echo "=================================================="
echo ""

fix_router() {
    local router=$1
    echo "=== Fixing: $router ==="
    
    docker exec clab-ospf-network-$router sh -c '
        # Kill everything
        pkill -9 softflowd 2>/dev/null || true
        rm -f /tmp/softflowd*.pid
        sleep 3
        
        # Verify interfaces are up
        echo "  Checking interfaces..."
        ip link show | grep -E "eth[0-9]:" | grep "state UP" || {
            echo "  ✗ No interfaces UP"
            exit 1
        }
        
        # Start with explicit NetFlow v9
        echo "  Starting softflowd with NetFlow v9..."
        softflowd \
            -i any \
            -n 172.20.20.1:2055 \
            -v 9 \
            -t maxlife=60 \
            -t maxidle=30 \
            -L 128 \
            -T full \
            -p /tmp/softflowd.pid
        
        sleep 3
        
        # Verify
        if pgrep softflowd >/dev/null 2>&1; then
            pid=$(pgrep softflowd)
            echo "  ✓ Running (PID: $pid)"
            
            # Show full command
            ps | grep softflowd | grep -v grep
            
            return 0
        else
            echo "  ✗ Failed to start"
            return 1
        fi
    '
}

success=0
failed=0

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if fix_router "$router"; then
        ((success++))
    else
        ((failed++))
    fi
    echo ""
done

echo "=================================================="
echo "Summary: ✓ $success/7  ✗ $failed/7"
echo ""

if [ $success -eq 7 ]; then
    echo "Waiting 30 seconds for flows to start..."
    sleep 30
    
    echo ""
    echo "Generating test traffic..."
    docker exec -d clab-ospf-network-csr23 ping -c 100 172.20.20.28 2>/dev/null
    docker exec -d clab-ospf-network-csr24 ping -c 100 172.20.20.27 2>/dev/null
    
    echo ""
    echo "Waiting 60 seconds for flow export..."
    sleep 60
    
    echo ""
    echo "Checking Logstash logs..."
    docker logs --tail 50 clab-ospf-network-logstash | grep -v "v29797"
fi

echo "=================================================="
