#!/bin/bash

echo "========================================="
echo "Quick Cleanup - Destroy Lab"
echo "========================================="
echo ""

cd ~/ospf-otel-lab

# Stop LLDP service if running
if systemctl is-active --quiet lldp-export 2>/dev/null; then
    echo "Stopping LLDP export service..."
    sudo systemctl stop lldp-export
fi

# Stop Elastic Agent if running (standalone, not in ContainerLab)
if docker ps --format '{{.Names}}' | grep -q "^elastic-agent-sw2$"; then
    echo "Stopping standalone Elastic Agent..."
    docker stop elastic-agent-sw2 2>/dev/null || true
    docker rm elastic-agent-sw2 2>/dev/null || true
fi

# Clean up network bridges/veth pairs
echo "Cleaning up network interfaces..."
sudo ip link del veth-agent-sw2 2>/dev/null || true

echo "Destroying containerlab topology..."
sudo clab destroy -t ospf-network.clab.yml --cleanup 2>/dev/null || true

echo ""
echo "Waiting for cleanup..."
sleep 10

# Optional: Clean up Docker resources
echo "Cleaning up Docker resources..."
docker system prune -f 2>/dev/null || true

# Clean up persistent data (optional - comment out if you want to keep data)
# echo "Cleaning persistent agent data..."
# rm -rf configs/elastic-agent/data/* 2>/dev/null || true
# rm -rf configs/elastic-agent/state/* 2>/dev/null || true

echo ""
echo "========================================="
echo "✓ Cleanup Complete!"
echo "========================================="
echo ""
echo "To redeploy:"
echo "  cd ~/ospf-otel-lab"
echo "  ./scripts/complete-setup.sh"
echo ""
echo "To remove LLDP service:"
echo "  sudo systemctl disable lldp-export"
echo "  sudo rm /etc/systemd/system/lldp-export.service"
echo "  sudo systemctl daemon-reload"
echo ""
echo "To clean persistent agent data:"
echo "  rm -rf configs/elastic-agent/data/*"
echo "  rm -rf configs/elastic-agent/state/*"
echo ""
