#!/bin/bash

echo "=================================================="
echo "  NetFlow Traffic Monitor"
echo "=================================================="
echo ""

echo "Starting 3-way monitoring:"
echo "  1. tcpdump on host (UDP 2055)"
echo "  2. tcpdump inside Logstash container"
echo "  3. Traffic generation from router"
echo ""

# Start tcpdump on host
echo "1. Starting host capture..."
sudo timeout 60 tcpdump -i any -nn 'udp port 2055' -c 20 -vvv 2>&1 | tee /tmp/netflow-host.log &
HOST_PID=$!

sleep 2

# Start tcpdump in Logstash container
echo "2. Starting Logstash container capture..."
docker exec clab-ospf-network-logstash timeout 60 tcpdump -i any -nn 'udp port 2055' -c 20 -vvv 2>&1 | tee /tmp/netflow-logstash.log &
LOGSTASH_PID=$!

sleep 2

# Generate traffic from router
echo "3. Generating traffic from csr28..."
docker exec clab-ospf-network-csr28 sh -c '
    echo "Checking softflowd status..."
    if ! pgrep softflowd >/dev/null; then
        echo "Starting softflowd..."
        softflowd -i any -n 172.20.20.1:2055 -v 9 -d
        sleep 3
    fi
    
    echo "Generating diverse traffic..."
    
    # Multiple destinations
    for target in 172.20.20.1 172.20.20.23 172.20.20.24 8.8.8.8; do
        ping -c 20 -i 0.5 $target >/dev/null 2>&1 &
    done
    
    wait
    echo "Traffic generation complete"
'

echo ""
echo "4. Waiting 30 seconds for flow export..."
sleep 30

echo ""
echo "=================================================="
echo "  Results"
echo "=================================================="
echo ""

# Check host capture
echo "=== Host Capture Results ==="
if [ -f /tmp/netflow-host.log ]; then
    if grep -q "UDP" /tmp/netflow-host.log; then
        echo "✓ NetFlow packets captured on host"
        grep "UDP" /tmp/netflow-host.log | head -5
    else
        echo "✗ No NetFlow packets on host"
    fi
else
    echo "✗ No host capture log"
fi

echo ""

# Check Logstash capture
echo "=== Logstash Container Capture Results ==="
if [ -f /tmp/netflow-logstash.log ]; then
    if grep -q "UDP" /tmp/netflow-logstash.log; then
        echo "✓ NetFlow packets reached Logstash"
        grep "UDP" /tmp/netflow-logstash.log | head -5
    else
        echo "✗ No NetFlow packets in Logstash"
    fi
else
    echo "✗ No Logstash capture log"
fi

echo ""
echo "Full logs saved to:"
echo "  /tmp/netflow-host.log"
echo "  /tmp/netflow-logstash.log"
echo ""

