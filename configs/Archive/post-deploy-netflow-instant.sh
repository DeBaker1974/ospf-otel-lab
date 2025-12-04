#!/bin/bash
# Instant NetFlow startup - no blocking, no waiting

LOGSTASH_IP="172.20.20.2"

echo "Starting NetFlow on all routers..."
echo ""

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-${router}"
    
    # Quick check
    running=$(docker exec "$container" pgrep softflowd 2>/dev/null | wc -l)
    
    if [ "$running" -gt 0 ]; then
        echo "  ✓ $router: already running ($running processes)"
    else
        echo "  ⟳ $router: starting..."
        # Completely detached - no waiting at all
        nohup docker exec "$container" sh -c '
            command -v softflowd >/dev/null 2>&1 || apk add --no-cache softflowd >/dev/null 2>&1
            pkill softflowd 2>/dev/null || true
            sleep 1
            for iface in eth1 eth2 eth3 eth4 eth5; do
                ip link show $iface >/dev/null 2>&1 && \
                softflowd -i $iface -n 172.20.20.2:2055 -v 9 -t maxlife=30 -d -p /tmp/softflowd-${iface}.pid 2>/dev/null
            done
        ' >/dev/null 2>&1 &
        disown
    fi
done

echo ""
echo "✓ NetFlow startup initiated (backgrounded)"
echo ""
echo "Check status in 10 seconds with:"
echo "  for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do"
echo "    echo -n \"\$r: \"; docker exec clab-ospf-network-\$r pgrep softflowd | wc -l"
echo "  done"
