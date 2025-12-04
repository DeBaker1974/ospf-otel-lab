#!/bin/bash

echo "========================================="
echo "AGGRESSIVE Cleanup - Full Lab Teardown"
echo "========================================="
echo ""
echo "⚠️  This will remove:"
echo "  - All lab containers"
echo "  - Network interfaces"
echo "  - Persistent agent data"
echo "  - Docker resources"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

cd ~/ospf-otel-lab

# Stop services
echo "Stopping services..."
sudo systemctl stop lldp-export 2>/dev/null || true

# Stop any standalone containers
echo "Stopping standalone containers..."
docker stop elastic-agent-sw2 2>/dev/null || true
docker rm elastic-agent-sw2 2>/dev/null || true

# Clean network interfaces
echo "Cleaning network interfaces..."
sudo ip link del veth-agent-sw2 2>/dev/null || true

# Destroy lab
echo "Destroying containerlab topology..."
sudo clab destroy -t ospf-network.clab.yml --cleanup 2>/dev/null || true

# Wait for cleanup
sleep 10

# Clean up any orphaned containers
echo "Cleaning orphaned containers..."
docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" | while read container; do
    echo "  Removing: $container"
    docker rm -f "$container" 2>/dev/null || true
done

# Clean Docker resources
echo "Pruning Docker resources..."
docker system prune -af 2>/dev/null || true

# Clean persistent data
echo "Cleaning persistent data..."
rm -rf configs/elastic-agent/data/* 2>/dev/null || true
rm -rf configs/elastic-agent/state/* 2>/dev/null || true
rm -rf clab-ospf-network/ 2>/dev/null || true
rm -rf logs/*.log 2>/dev/null || true

echo ""
echo "========================================="
echo "✓ Aggressive Cleanup Complete!"
echo "========================================="
echo ""
echo "Everything has been removed."
echo ""
echo "To redeploy from scratch:"
echo "  cd ~/ospf-otel-lab"
echo "  ./scripts/complete-setup.sh"
echo ""
