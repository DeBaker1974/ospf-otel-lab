#!/bin/bash

echo "=========================================="
echo "CSR23 Bandwidth Hog Demo - Complete Guide"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

cleanup() {
    echo -e "\n${YELLOW}[CLEANUP] Stopping all traffic...${NC}"
    docker exec clab-ospf-network-node1 pkill -f "nc" 2>/dev/null
    docker exec clab-ospf-network-node1 pkill -f "ping" 2>/dev/null
    docker exec clab-ospf-network-node1 pkill -f "dd" 2>/dev/null
    docker exec clab-ospf-network-linux-bottom pkill -f "nc" 2>/dev/null
    docker exec clab-ospf-network-linux-bottom pkill -f "ping" 2>/dev/null
    docker exec clab-ospf-network-win-bottom pkill -f "nc" 2>/dev/null
    docker exec clab-ospf-network-win-bottom pkill -f "ping" 2>/dev/null
    echo -e "${GREEN}[CLEANUP] Complete!${NC}"
}
trap cleanup EXIT

echo -e "\n${GREEN}[INFO] This demo simulates:${NC}"
echo "  1. Normal business traffic (HTTP, DB, Monitoring)"
echo "  2. Bandwidth hog (large file transfer)"
echo "  3. Bidirectional flows through CSR23"
echo ""
echo "  Traffic path: node1 → CSR28 → CSR23 → CSR25/27 → bottom network"
echo ""

# Check if containers are running
echo -e "${YELLOW}[CHECK] Verifying containers...${NC}"
for container in node1 linux-bottom win-bottom csr23; do
    if ! docker exec clab-ospf-network-$container echo "OK" &>/dev/null; then
        echo -e "${RED}[ERROR] Container clab-ospf-network-$container not running!${NC}"
        exit 1
    fi
done
echo -e "${GREEN}[CHECK] All containers ready!${NC}"

# Verify NetFlow collector
echo -e "\n${YELLOW}[CHECK] NetFlow collector status...${NC}"
if docker logs clab-ospf-network-logstash 2>&1 | grep -q "Successfully started Logstash"; then
    echo -e "${GREEN}[CHECK] Logstash is running${NC}"
else
    echo -e "${RED}[WARNING] Logstash may not be fully started${NC}"
fi

echo -e "\n${YELLOW}=========================================="
echo "PHASE 1: Baseline (Normal Traffic)"
echo "==========================================${NC}"
echo "Starting lightweight traffic..."

# HTTP requests (small)
docker exec -d clab-ospf-network-node1 sh -c '
  for i in {1..300}; do
    echo "GET / HTTP/1.1" | nc -w 1 -u 192.168.10.10 80 2>/dev/null
    sleep 0.5
  done
' &

# ICMP monitoring
docker exec -d clab-ospf-network-node1 sh -c '
  ping -c 100 -i 0.3 192.168.10.10 > /dev/null 2>&1
' &

# Small DB queries
docker exec -d clab-ospf-network-node1 sh -c '
  for i in {1..200}; do
    echo "SELECT 1" | nc -w 1 192.168.10.20 3306 2>/dev/null
    sleep 1
  done
' &

echo -e "${GREEN}✓ Baseline traffic started${NC}"
echo "  → HTTP to 192.168.10.10:80"
echo "  → ICMP pings to 192.168.10.10"
echo "  → DB queries to 192.168.10.20:3306"
echo ""
echo "[WAITING 30 seconds for baseline to establish...]"
sleep 30

echo -e "\n${RED}=========================================="
echo "PHASE 2: BANDWIDTH HOG INJECTION"
echo "==========================================${NC}"
echo "Starting heavy traffic flows..."

# Bandwidth hog - Large TCP transfers
docker exec -d clab-ospf-network-node1 sh -c '
  for i in {1..10}; do
    dd if=/dev/zero bs=1M count=100 2>/dev/null | nc -w 3 192.168.10.10 8080 2>/dev/null &
    dd if=/dev/urandom bs=512K count=200 2>/dev/null | nc -w 3 192.168.10.20 443 2>/dev/null &
    sleep 2
  done
  wait
' &

# UDP flood (simulating video/voice)
docker exec -d clab-ospf-network-node1 sh -c '
  for i in {1..100}; do
    dd if=/dev/urandom bs=1024 count=100 2>/dev/null | nc -u -w 1 192.168.10.10 5060 2>/dev/null
    sleep 0.1
  done
' &

echo -e "${RED}✓ BANDWIDTH HOG ACTIVE${NC}"
echo "  → 100MB transfers to 192.168.10.10:8080"
echo "  → Random data to 192.168.10.20:443"
echo "  → UDP floods to 192.168.10.10:5060"
echo ""
echo "[RUNNING for 60 seconds...]"
echo ""
echo -e "${YELLOW}>>> NOW CHECK ELASTIC FOR TRAFFIC SPIKES! <<<${NC}"
sleep 60

echo -e "\n${GREEN}=========================================="
echo "PHASE 3: Bidirectional Traffic"
echo "==========================================${NC}"
echo "Adding return traffic from bottom network..."

# Return traffic from linux-bottom
docker exec -d clab-ospf-network-linux-bottom sh -c '
  for i in {1..50}; do
    echo "RESPONSE DATA $(head -c 1024 /dev/urandom | base64)" | nc -w 1 192.168.20.100 12345 2>/dev/null
    sleep 0.5
  done
' &

# Additional load from win-bottom
docker exec -d clab-ospf-network-win-bottom sh -c '
  ping -c 100 -i 0.2 192.168.20.100 > /dev/null 2>&1
' &

echo -e "${GREEN}✓ Bidirectional flows active${NC}"
echo "  → Responses from 192.168.10.20 → 192.168.20.100"
echo "  → Pings from 192.168.10.10 → 192.168.20.100"
echo ""
echo "[RUNNING for 45 seconds...]"
sleep 45

echo -e "\n${GREEN}=========================================="
echo "Demo Complete!"
echo "==========================================${NC}"
echo ""
echo "NetFlow data should now be visible in Elasticsearch."
echo "Wait 30-60 seconds for flow expiration, then check:"
echo ""
echo "  1. Run: docker logs -f clab-ospf-network-logstash"
echo "  2. Look for non-224.0.0.5 destinations"
echo "  3. Execute the analysis queries below"
echo ""
