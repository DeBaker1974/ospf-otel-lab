#!/bin/bash

echo "=================================================="
echo "  NetFlow Installation for OSPF Lab"
echo "  Target: Logstash @ 172.20.20.1:2055"
echo "=================================================="
echo ""

# Configuration
COLLECTOR_IP="172.20.20.1"
COLLECTOR_PORT="2055"
NETFLOW_VERSION="9"
FLOW_TIMEOUT="60"
IDLE_TIMEOUT="30"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to install NetFlow on a router
install_netflow() {
    local router=$1
    echo "========================================"
    echo "Installing on: $router"
    echo "========================================"
    
    docker exec clab-ospf-network-$router bash -c '
        # Update package list
        echo "  [1/5] Updating package list..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq 2>/dev/null
        
        # Install softflowd
        echo "  [2/5] Installing softflowd..."
        apt-get install -y softflowd -qq 2>/dev/null
        
        if ! which softflowd > /dev/null 2>&1; then
            echo "  ERROR: softflowd installation failed"
            exit 1
        fi
        
        # Kill any existing process
        echo "  [3/5] Stopping old processes..."
        pkill softflowd 2>/dev/null || true
        
        # Create startup script
        echo "  [4/5] Creating startup script..."
        cat > /usr/local/bin/start-netflow.sh << STARTSCRIPT
#!/bin/bash
# NetFlow Startup Script
# Collector: '"$COLLECTOR_IP"':'"$COLLECTOR_PORT"'
# Version: NetFlow v'"$NETFLOW_VERSION"'

pkill softflowd 2>/dev/null || true
sleep 1

softflowd \
    -i any \
    -n '"$COLLECTOR_IP"':'"$COLLECTOR_PORT"' \
    -v '"$NETFLOW_VERSION"' \
    -t maxlife='"$FLOW_TIMEOUT"' \
    -t maxidle='"$IDLE_TIMEOUT"' \
    -d

echo "NetFlow exporter started (PID: \$(pgrep softflowd))"
STARTSCRIPT
        
        chmod +x /usr/local/bin/start-netflow.sh
        
        # Start NetFlow
        echo "  [5/5] Starting NetFlow exporter..."
        /usr/local/bin/start-netflow.sh
        
        # Verify
        sleep 2
        if pgrep softflowd > /dev/null; then
            echo "  ✓ SUCCESS: NetFlow running (PID: $(pgrep softflowd))"
            ps aux | grep softflowd | grep -v grep
            exit 0
        else
            echo "  ✗ FAILED: NetFlow did not start"
            exit 1
        fi
    '
    
    local result=$?
    echo ""
    return $result
}

# Track results
success=0
failed=0
failed_routers=()

# Install on all routers
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker ps | grep -q "clab-ospf-network-$router"; then
        if install_netflow "$router"; then
            ((success++))
        else
            ((failed++))
            failed_routers+=("$router")
        fi
    else
        echo -e "${RED}$router: Not running - skipped${NC}"
        echo ""
        ((failed++))
        failed_routers+=("$router")
    fi
done

# Summary
echo "=================================================="
echo "  INSTALLATION SUMMARY"
echo "=================================================="
echo ""
echo -e "${GREEN}✓ Successful: $success/7${NC}"
if [ $failed -gt 0 ]; then
    echo -e "${RED}✗ Failed: $failed/7${NC}"
    echo "   Failed routers: ${failed_routers[*]}"
fi
echo ""

if [ $success -eq 7 ]; then
    echo "🎉 All routers configured successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Generate traffic: ./generate-netflow-traffic.sh"
    echo "  2. Monitor Logstash: docker logs -f clab-ospf-network-logstash"
    echo "  3. Check status: ./netflow-status.sh"
else
    echo "⚠️  Some routers failed. Check errors above."
    echo ""
    echo "Retry installation:"
    echo "  ./install-netflow-all-routers.sh"
fi

echo ""
echo "=================================================="
