#!/bin/bash
# Fast post-deploy NetFlow startup

LOGSTASH_IP="172.20.20.2"

echo "Starting NetFlow on all routers (fast mode)..."

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-${router}"
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "  ⚠ $router: container not running"
        continue
    fi
    
    # Check if already running
    running_count=$(docker exec "$container" pgrep softflowd 2>/dev/null | wc -l)
    if [ "$running_count" -gt 0 ]; then
        echo "  ✓ $router: softflowd already running ($running_count processes)"
        continue
    fi
    
    # Start directly without script copy (faster)
    echo "  Starting $router..."
    docker exec "$container" sh -c '
        # Install if needed (with timeout)
        if ! command -v softflowd >/dev/null 2>&1; then
            timeout 20 apk add --no-cache softflowd >/dev/null 2>&1 &
            wait $!
        fi
        
        # Kill existing
        pkill softflowd 2>/dev/null || true
        sleep 1
        
        # Start on all interfaces
        for iface in eth1 eth2 eth3 eth4 eth5; do
            if ip link show $iface >/dev/null 2>&1; then
                softflowd -i $iface -n 172.20.20.2:2055 -v 9 -t maxlife=30 -d -p /tmp/softflowd-${iface}.pid 2>/dev/null
            fi
        done
    ' &
    
    # Don't wait, continue to next router
done

# Wait for all background jobs
wait

echo ""
echo "Verifying NetFlow processes..."
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-${router}"
    count=$(docker exec "$container" pgrep softflowd 2>/dev/null | wc -l)
    printf "  %-10s %d processes\n" "$router:" "$count"
done

echo ""
echo "NetFlow startup complete!"
