#!/bin/bash

echo "=================================================="
echo "  Restarting NetFlow on All Routers"
echo "=================================================="
echo ""

for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    echo -n "$router: "
    if docker ps | grep -q "clab-ospf-network-$router"; then
        docker exec clab-ospf-network-$router /usr/local/bin/start-netflow.sh >/dev/null 2>&1
        count=$(docker exec clab-ospf-network-$router ps | grep softflowd | grep -v grep | wc -l)
        if [ $count -gt 0 ]; then
            echo "✓ Restarted ($count processes)"
        else
            echo "✗ Failed"
        fi
    else
        echo "✗ Offline"
    fi
done

echo ""
echo "Done! Check status with: ./netflow-status-alpine.sh"
