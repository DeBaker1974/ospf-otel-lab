#!/bin/bash

echo "=================================================="
echo "  NetFlow Traffic Generator"
echo "=================================================="
echo ""

echo "Generating ICMP traffic between routers..."
echo "This will create NetFlow records..."
echo ""

# Generate ping traffic between different router pairs
docker exec -d clab-ospf-network-csr23 ping -c 100 -i 0.2 172.20.20.28 2>/dev/null
docker exec -d clab-ospf-network-csr24 ping -c 100 -i 0.2 172.20.20.27 2>/dev/null
docker exec -d clab-ospf-network-csr25 ping -c 100 -i 0.2 172.20.20.26 2>/dev/null
docker exec -d clab-ospf-network-csr26 ping -c 100 -i 0.2 172.20.20.29 2>/dev/null

echo "✓ Traffic generation started"
echo ""
echo "Flows will be exported within 60 seconds"
echo ""
echo "Monitor with:"
echo "  docker logs -f --tail 50 clab-ospf-network-logstash"
echo ""
echo "Or wait and check Elasticsearch:"
echo "  sleep 90"
echo "  curl -u elastic:pass https://your-es/_cat/indices/netflow-*"
echo ""
