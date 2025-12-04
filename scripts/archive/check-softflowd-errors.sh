#!/bin/bash

echo "=================================================="
echo "  softflowd Error Detection"
echo "=================================================="
echo ""

check_router() {
    local router=$1
    echo "=== $router ==="
    
    docker exec clab-ospf-network-$router sh -c '
        # Check if running
        if pgrep softflowd >/dev/null; then
            echo "Status: Running (PID: $(pgrep softflowd))"
            
            # Check for error indicators in dmesg
            dmesg 2>/dev/null | grep -i "softflowd\|flow" | tail -5
            
            # Check system logs if available
            if [ -f /var/log/messages ]; then
                tail -20 /var/log/messages | grep softflowd
            fi
            
            # Try to get statistics via control socket
            if [ -S /var/run/softflowd.ctl ] && command -v softflowctl >/dev/null 2>&1; then
                echo ""
                echo "Statistics:"
                softflowctl statistics 2>/dev/null
            fi
        else
            echo "Status: NOT RUNNING"
            
            # Check if it crashed
            if [ -f /tmp/softflowd.pid ]; then
                OLD_PID=$(cat /tmp/softflowd.pid)
                echo "Old PID file exists: $OLD_PID"
                
                # Check if that process exists
                if kill -0 $OLD_PID 2>/dev/null; then
                    echo "  Process still exists!"
                else
                    echo "  Process died unexpectedly"
                fi
            fi
        fi
    '
    echo ""
}

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    check_router "$router"
done

