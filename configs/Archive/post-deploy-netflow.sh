#!/bin/bash
# Post-deploy NetFlow startup - run after 'clab deploy'

LOGSTASH_IP="172.20.20.2"

echo "Starting NetFlow on all routers..."

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
    
    # Copy and run the startup script
    if [ -f ~/ospf-otel-lab/configs/routers/${router}/start-netflow.sh ]; then
        docker cp ~/ospf-otel-lab/configs/routers/${router}/start-netflow.sh \
                  "$container:/tmp/start-netflow.sh" 2>/dev/null
        
        docker exec "$container" sh -c "chmod +x /tmp/start-netflow.sh && /tmp/start-netflow.sh" 2>/dev/null
        
        # Check if running
        sleep 2
        count=$(docker exec "$container" pgrep softflowd 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            printf "  ✓ %-10s %d processes started\n" "$router:" "$count"
        else
            echo "  ✗ $router: failed to start"
        fi
    else
        echo "  ✗ $router: startup script not found"
    fi
done

echo "NetFlow startup complete!"
