#!/bin/bash

echo "=================================================="
echo "  Elastic Agent NetFlow Configuration Check"
echo "=================================================="
echo ""

# Find Elastic Agent process
echo "1. Checking Elastic Agent Status..."
if systemctl is-active --quiet elastic-agent; then
    echo "   ✓ Elastic Agent service is running"
    systemctl status elastic-agent --no-pager | head -10
elif pgrep -f elastic-agent >/dev/null; then
    echo "   ✓ Elastic Agent process found"
    ps aux | grep elastic-agent | grep -v grep | head -3
else
    echo "   ✗ Elastic Agent not running"
    echo ""
    echo "   To check installation:"
    echo "     sudo elastic-agent status"
    exit 1
fi

echo ""

# Check if UDP 2055 is listening
echo "2. Checking UDP Port 2055..."
if sudo netstat -uln | grep -q ":2055"; then
    echo "   ✓ UDP 2055 is listening"
    sudo netstat -uln | grep 2055
else
    echo "   ✗ UDP 2055 is NOT listening"
    echo "   NetFlow integration may not be configured"
fi

echo ""

# Check Elastic Agent configuration
echo "3. Elastic Agent Configuration..."
if [ -f /opt/Elastic/Agent/elastic-agent.yml ]; then
    echo "   Config file: /opt/Elastic/Agent/elastic-agent.yml"
    sudo cat /opt/Elastic/Agent/elastic-agent.yml | grep -A 10 "netflow\|udp.*2055" || echo "   No NetFlow config found"
elif [ -f /etc/elastic-agent/elastic-agent.yml ]; then
    echo "   Config file: /etc/elastic-agent/elastic-agent.yml"
    sudo cat /etc/elastic-agent/elastic-agent.yml | grep -A 10 "netflow\|udp.*2055" || echo "   No NetFlow config found"
else
    echo "   ⚠ Config file not found in standard locations"
fi

echo ""

# Check agent policies
echo "4. Fleet-managed Policies..."
if command -v elastic-agent >/dev/null 2>&1; then
    sudo elastic-agent status 2>/dev/null | head -20
else
    echo "   elastic-agent command not in PATH"
    echo "   Try: /opt/Elastic/Agent/elastic-agent status"
fi

echo ""

# Check data stream
echo "5. NetFlow Data Stream..."
AGENT_DATA_DIR="/opt/Elastic/Agent/data"
if [ -d "$AGENT_DATA_DIR" ]; then
    echo "   Agent data directory exists"
    sudo find "$AGENT_DATA_DIR" -type f -name "*netflow*" 2>/dev/null | head -5
else
    echo "   Agent data directory not found"
fi

echo ""

# Check firewall
echo "6. Firewall Status..."
if command -v ufw >/dev/null 2>&1; then
    echo "   UFW Status:"
    sudo ufw status | grep -E "2055|Status"
elif command -v firewall-cmd >/dev/null 2>&1; then
    echo "   Firewalld Status:"
    sudo firewall-cmd --list-ports 2>/dev/null | grep 2055 || echo "   Port 2055 not explicitly allowed"
else
    echo "   ⚠ No firewall manager found (iptables may be in use)"
fi

echo ""

# Check logs
echo "7. Recent Agent Logs..."
if [ -f /opt/Elastic/Agent/data/elastic-agent-*/logs/elastic-agent-json.log ]; then
    echo "   Recent log entries:"
    sudo tail -20 /opt/Elastic/Agent/data/elastic-agent-*/logs/elastic-agent-json.log | grep -i "netflow\|udp.*2055" | tail -5
fi

echo ""
echo "=================================================="
echo "  Network Connectivity Test"
echo "=================================================="
echo ""

# Get host IP that containers can reach
HOST_IP=$(ip -4 addr show docker0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "127.0.0.1" | head -1)
fi

echo "Host IP (from container perspective): $HOST_IP"

echo ""
echo "8. Test connectivity from router to host..."
docker exec clab-ospf-network-csr28 sh -c "
    echo 'Pinging host at $HOST_IP...'
    ping -c 3 -W 2 $HOST_IP 2>&1 | tail -2
    
    echo ''
    echo 'Checking route to host...'
    ip route get $HOST_IP 2>/dev/null
"

echo ""
echo "=================================================="

