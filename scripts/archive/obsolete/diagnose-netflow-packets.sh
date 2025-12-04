#!/bin/bash

echo "=================================================="
echo "  NetFlow Packet Diagnosis"
echo "=================================================="
echo ""

router="csr28"

echo "1. Check softflowd command line:"
echo "----------------------------------------"
docker exec clab-ospf-network-$router ps | grep softflowd | grep -v grep

echo ""
echo "2. Verify softflowd is actually running:"
echo "----------------------------------------"
docker exec clab-ospf-network-$router sh -c '
    if [ -f /tmp/softflowd.pid ]; then
        pid=$(cat /tmp/softflowd.pid)
        echo "  PID from file: $pid"
        if kill -0 $pid 2>/dev/null; then
            echo "  ✓ Process is alive"
        else
            echo "  ✗ Process is dead"
        fi
    else
        echo "  No PID file found"
    fi
'

echo ""
echo "3. Test NetFlow export manually:"
echo "----------------------------------------"
echo "  Stopping existing softflowd and testing..."

docker exec clab-ospf-network-$router sh -c '
    pkill softflowd
    sleep 2
    
    # Start with verbose output
    echo "  Starting softflowd with debug..."
    softflowd -i eth1 -n 172.20.20.1:2055 -v 9 -d -D 2>&1 | head -20 &
    SFPID=$!
    
    sleep 5
    
    echo ""
    echo "  Generating test traffic..."
    ping -c 10 172.20.20.24 >/dev/null 2>&1 &
    
    sleep 10
    
    echo ""
    echo "  Checking if flows are being captured..."
    kill $SFPID 2>/dev/null
'

echo ""
echo "4. Capture actual packets being sent:"
echo "----------------------------------------"
echo "  Starting packet capture on host..."

# Capture on the host for 30 seconds
timeout 30 tcpdump -i any -nn udp port 2055 -c 10 -v 2>&1 | head -50 &
TCPDUMP_PID=$!

echo "  Restarting softflowd and generating traffic..."

docker exec clab-ospf-network-$router sh -c '
    pkill softflowd
    sleep 2
    softflowd -i any -n 172.20.20.1:2055 -v 9 -p /tmp/softflowd.pid 2>&1 &
    sleep 3
    ping -c 50 172.20.20.24 >/dev/null 2>&1 &
'

echo "  Waiting for capture..."
wait $TCPDUMP_PID

echo ""
echo "=================================================="
