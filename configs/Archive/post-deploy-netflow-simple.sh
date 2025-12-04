#!/bin/bash
# Simple NetFlow startup - no waiting

LOGSTASH_IP="172.20.20.2"

echo "Starting NetFlow on all routers..."

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-${router}"
    
    # Quick check
    running=$(docker exec "$container" pgrep softflowd 2>/dev/null | wc -l)
    
    if [ "$running" -gt 0 ]; then
        echo "  ✓ $router: already running ($running processes)"
    else
        echo "  Starting $router..."
        # Fire and forget - don't wait
        docker exec "$container" sh -c '
            if ! command -v softflowd >/dev/null 2>&1; then
                apk add --no-cache softflowd >/dev/null 2>&1
            fi
            pkill softflowd 2>/dev/null || true
            sleep 1
            for iface in eth1 eth2 eth3 eth4 eth5; do
                if ip link show $iface >/dev/null 2>&1; then
                    softflowd -i $iface -n 172.20.20.2:2055 -v 9 -t maxlife=30 -d -p /tmp/softflowd-${iface}.pid 2>/dev/null
                fi
            done
        ' >/dev/null 2>&1 &
    fi
done

# Give them a few seconds to start
sleep 5

echo ""
echo "NetFlow processes:"
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    count=$(docker exec "clab-ospf-network-${router}" pgrep softflowd 2>/dev/null | wc -l)
    printf "  %-10s %d\n" "$router:" "$count"
done

echo ""
echo "Done! (processes may still be starting)"
