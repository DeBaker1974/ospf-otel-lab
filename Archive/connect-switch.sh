#!/bin/bash

echo "========================================="
echo "🔌 Connecting to Switch: clab-ospf-network-sw"
echo "========================================="
echo ""

# Check if container exists
if ! docker ps --format "{{.Names}}" | grep -q "clab-ospf-network-sw"; then
    echo "❌ Switch container not found!"
    echo ""
    echo "Available containers:"
    docker ps --format "  - {{.Names}}"
    exit 1
fi

echo "✅ Switch container found!"
echo ""
echo "Container Info:"
docker ps --filter "name=clab-ospf-network-sw" --format "  Name: {{.Names}}\n  Status: {{.Status}}\n  Image: {{.Image}}"

echo ""
echo "IP Address:"
docker inspect -f '{{range .NetworkSettings.Networks}}  {{.IPAddress}}{{end}}' clab-ospf-network-sw

echo ""
echo "========================================="
echo "📋 Quick Commands You Can Run:"
echo "========================================="
echo ""
echo "1. Show network interfaces:"
echo "   ip addr show"
echo ""
echo "2. Show bridge configuration:"
echo "   brctl show"
echo ""
echo "3. Show network statistics:"
echo "   ip -s link"
echo ""
echo "4. Show routing table:"
echo "   ip route"
echo ""
echo "5. Check processes:"
echo "   ps aux"
echo ""
echo "6. Show connected containers:"
echo "   ip neighbor show"
echo ""
echo "========================================="
echo "🚀 Connecting to switch shell..."
echo "========================================="
echo ""
echo "Type 'exit' to return to host"
echo ""

# Connect to the switch
docker exec -it clab-ospf-network-sw sh
