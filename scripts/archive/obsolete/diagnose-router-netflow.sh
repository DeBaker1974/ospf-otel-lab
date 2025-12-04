#!/bin/bash

echo "=================================================="
echo "  Router NetFlow Diagnostics"
echo "=================================================="
echo ""

diagnose_router() {
    local router=$1
    echo "╔════════════════════════════════════════════════╗"
    echo "║  Router: $router"
    echo "╚════════════════════════════════════════════════╝"
    echo ""
    
    # 1. Check if softflowd is running
    echo "1. Process Status:"
    if docker exec clab-ospf-network-$router pgrep -a softflowd 2>/dev/null; then
        echo "   ✓ softflowd is running"
        
        # Get full command line
        docker exec clab-ospf-network-$router ps aux | grep softflowd | grep -v grep
    else
        echo "   ✗ softflowd is NOT running"
        return 1
    fi
    
    echo ""
    
    # 2. Check process details
    echo "2. Process Details:"
    docker exec clab-ospf-network-$router sh -c '
        if pgrep softflowd >/dev/null; then
            echo "   PID: $(pgrep softflowd)"
            echo "   Command: $(ps -p $(pgrep softflowd) -o args= 2>/dev/null)"
            
            # Check how long it has been running
            if [ -f /tmp/softflowd.pid ]; then
                echo "   PID file exists: /tmp/softflowd.pid"
                echo "   PID in file: $(cat /tmp/softflowd.pid 2>/dev/null)"
            fi
        fi
    '
    
    echo ""
    
    # 3. Test UDP connectivity to Logstash
    echo "3. Network Connectivity Test:"
    docker exec clab-ospf-network-$router sh -c '
        LOGSTASH_IP="172.20.20.1"
        
        # Check if we can reach the IP
        if ping -c 1 -W 1 $LOGSTASH_IP >/dev/null 2>&1; then
            echo "   ✓ Can ping $LOGSTASH_IP"
        else
            echo "   ✗ Cannot ping $LOGSTASH_IP"
        fi
        
        # Check routing
        echo "   Route to $LOGSTASH_IP:"
        ip route get $LOGSTASH_IP 2>/dev/null | head -1 || echo "   No route found"
        
        # Try UDP test if nc is available
        if command -v nc >/dev/null 2>&1; then
            if echo "test" | timeout 2 nc -u -w1 $LOGSTASH_IP 2055 2>/dev/null; then
                echo "   ✓ UDP port 2055 appears reachable"
            else
                echo "   ⚠ UDP test inconclusive (UDP is connectionless)"
            fi
        fi
    '
    
    echo ""
    
    # 4. Check network interfaces
    echo "4. Network Interfaces:"
    docker exec clab-ospf-network-$router ip -br addr show | grep -v "lo\|DOWN" | head -5
    
    echo ""
    
    # 5. Check for recent network activity
    echo "5. Traffic Test (5 second capture):"
    docker exec clab-ospf-network-$router timeout 5 tcpdump -i any -c 10 -n 2>/dev/null | \
        grep -E "IP|packets" | head -10 || echo "   No traffic captured"
    
    echo ""
    
    # 6. Try to send test data
    echo "6. Manual Flow Test:"
    docker exec clab-ospf-network-$router sh -c '
        # Generate some traffic
        ping -c 5 -W 1 172.20.20.1 >/dev/null 2>&1 &
        ping -c 5 -W 1 8.8.8.8 >/dev/null 2>&1 &
        
        sleep 2
        
        # Check if softflowd sees flows
        if [ -S /var/run/softflowd.ctl ]; then
            echo "   Control socket exists"
            # Try softflowctl if available
            if command -v softflowctl >/dev/null 2>&1; then
                softflowctl statistics 2>/dev/null | head -10
            fi
        else
            echo "   No control socket found"
        fi
    '
    
    echo ""
    echo "=================================================="
    echo ""
}

# Test all routers
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    diagnose_router "$router"
    sleep 1
done

echo ""
echo "╔════════════════════════════════════════════════╗"
echo "║  Summary"
echo "╚════════════════════════════════════════════════╝"
echo ""

# Summary statistics
running=0
stopped=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker exec clab-ospf-network-$router pgrep softflowd >/dev/null 2>&1; then
        ((running++))
    else
        ((stopped++))
    fi
done

echo "Routers with softflowd running: $running/7"
echo "Routers with softflowd stopped: $stopped/7"
echo ""

if [ $stopped -gt 0 ]; then
    echo "⚠ Some routers have stopped exporters"
    echo ""
    echo "To restart all:"
    echo "  ./restart-all-netflow-exporters.sh"
fi

