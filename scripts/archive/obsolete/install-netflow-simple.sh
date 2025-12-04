#!/bin/bash

echo "=================================================="
echo "  Simplified NetFlow Installation"
echo "=================================================="
echo ""

LOGSTASH_IP="172.20.20.1"
COLLECTOR_PORT="2055"

install_on_router() {
    local router=$1
    echo "=== Installing on: $router ==="
    
    docker exec clab-ospf-network-$router sh -c '
        # Install if needed
        if ! command -v softflowd >/dev/null 2>&1; then
            apk add --no-cache softflowd >/dev/null 2>&1
        fi
        
        # Kill existing
        pkill -9 softflowd 2>/dev/null || true
        rm -f /tmp/softflowd*.pid 2>/dev/null
        sleep 2
        
        # Create simple startup script
        cat > /usr/local/bin/start-netflow.sh << '\''SCRIPT'\''
#!/bin/sh
pkill -9 softflowd 2>/dev/null || true
rm -f /tmp/softflowd*.pid
sleep 1

# Try monitoring "any" interface (all interfaces)
softflowd -i any -n '"$LOGSTASH_IP"':'"$COLLECTOR_PORT"' -v 9 -p /tmp/softflowd.pid 2>&1 &

sleep 3

if ps | grep -v grep | grep softflowd >/dev/null; then
    echo "✓ NetFlow running on all interfaces"
    ps | grep softflowd | grep -v grep
    exit 0
else
    echo "✗ Failed to start softflowd"
    echo ""
    echo "Trying with explicit interface eth1:"
    softflowd -i eth1 -n '"$LOGSTASH_IP"':'"$COLLECTOR_PORT"' -v 9 -p /tmp/softflowd-eth1.pid 2>&1 &
    sleep 2
    
    if ps | grep -v grep | grep softflowd >/dev/null; then
        echo "✓ NetFlow running on eth1"
        ps | grep softflowd | grep -v grep
        exit 0
    else
        echo "✗ Still failed - checking errors:"
        dmesg | tail -10
        exit 1
    fi
fi
SCRIPT
        
        chmod +x /usr/local/bin/start-netflow.sh
        /usr/local/bin/start-netflow.sh
    '
    
    return $?
}

success=0
failed=0

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if install_on_router "$router"; then
        ((success++))
    else
        ((failed++))
    fi
    echo ""
done

echo "=================================================="
echo "Summary: ✓ $success/7  ✗ $failed/7"
echo "=================================================="
