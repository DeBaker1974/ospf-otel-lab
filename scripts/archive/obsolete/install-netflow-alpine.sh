#!/bin/bash

echo "=================================================="
echo "  NetFlow Installation for Alpine-based Routers"
echo "  Target: Logstash @ 172.20.20.1:2055"
echo "=================================================="
echo ""

LOGSTASH_IP="172.20.20.50"  # Updated to match your Docker host
COLLECTOR_PORT="2055"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

install_on_router() {
    local router=$1
    echo "========================================"
    echo "Installing on: $router"
    echo "========================================"
    
    docker exec clab-ospf-network-$router sh -c '
        echo "  [1/5] Checking OS type..."
        if command -v apk >/dev/null 2>&1; then
            echo "  Alpine Linux detected"
        elif command -v apt-get >/dev/null 2>&1; then
            echo "  Debian/Ubuntu detected"
        else
            echo "  Unknown OS"
            exit 1
        fi
        
        echo "  [2/5] Installing softflowd..."
        if command -v apk >/dev/null 2>&1; then
            apk add --no-cache softflowd >/dev/null 2>&1
        else
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y softflowd >/dev/null 2>&1
        fi
        
        if ! command -v softflowd >/dev/null 2>&1; then
            echo "  ERROR: softflowd installation failed"
            exit 1
        fi
        
        echo "  [3/5] Creating startup script..."
        cat > /usr/local/bin/start-netflow.sh << '\''STARTSCRIPT'\''
#!/bin/sh
# NetFlow startup script - monitor all interfaces

LOGSTASH_IP="172.20.20.50"
COLLECTOR_PORT="'"$COLLECTOR_PORT"'"

# Kill any existing instances
pkill softflowd 2>/dev/null || true
sleep 1

# Start softflowd on each data interface
for iface in eth1 eth2 eth3 eth4 eth5; do
  if ip link show $iface >/dev/null 2>&1; then
    softflowd -i $iface \
              -n ${LOGSTASH_IP}:${COLLECTOR_PORT} \
              -v 9 \
              -t maxlife=30 \
              -t maxidle=15 \
              -d \
              -p /tmp/softflowd-${iface}.pid 2>/dev/null
    
    if [ $? -eq 0 ]; then
      echo "✓ NetFlow started on $iface -> ${LOGSTASH_IP}:${COLLECTOR_PORT}"
    else
      echo "✗ Failed to start on $iface"
    fi
  fi
done

# Show running processes
echo ""
echo "Active NetFlow processes:"
ps | grep softflowd | grep -v grep
STARTSCRIPT
        
        chmod +x /usr/local/bin/start-netflow.sh
        
        echo "  [4/5] Stopping old processes..."
        pkill softflowd 2>/dev/null || true
        sleep 1
        
        echo "  [5/5] Starting NetFlow exporters..."
        /usr/local/bin/start-netflow.sh
        
        sleep 2
        
        # Verify
        running_count=$(ps | grep softflowd | grep -v grep | wc -l)
        if [ $running_count -gt 0 ]; then
            echo "  ✓ SUCCESS: $running_count NetFlow process(es) running"
            ps | grep softflowd | grep -v grep
            return 0
        else
            echo "  ✗ FAILED: No NetFlow processes started"
            return 1
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
        if install_on_router "$router"; then
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
    echo "  1. Check status: ./netflow-status-alpine.sh"
    echo "  2. Generate traffic: ./generate-netflow-traffic.sh"
    echo "  3. Monitor Logstash: docker logs -f clab-ospf-network-logstash"
else
    echo "⚠️  Some routers failed. Check errors above."
fi

echo ""
echo "=================================================="
