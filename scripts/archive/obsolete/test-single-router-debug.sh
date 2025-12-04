#!/bin/bash

ROUTER=${1:-csr28}

echo "=================================================="
echo "  Testing NetFlow on Router: $ROUTER (DEBUG MODE)"
echo "=================================================="
echo ""

echo "This will:"
echo "  1. Stop existing softflowd"
echo "  2. Run softflowd in foreground with debug output"
echo "  3. Generate traffic"
echo "  4. Show if flows are exported"
echo ""
read -p "Press Enter to continue..."

echo ""
echo "Starting softflowd in debug mode..."
echo "Press Ctrl+C to stop"
echo "=================================================="
echo ""

docker exec -it clab-ospf-network-$ROUTER sh -c '
    # Kill existing
    pkill -9 softflowd 2>/dev/null
    rm -f /tmp/softflowd.pid
    sleep 2
    
    # Start in foreground with debug
    echo "Starting softflowd with:"
    echo "  Interface: any"
    echo "  Collector: 172.20.20.1:2055"
    echo "  Version: 9"
    echo "  Debug: ON"
    echo ""
    
    # Run in foreground
    softflowd -i any -n 172.20.20.1:2055 -v 9 -d -D
'

