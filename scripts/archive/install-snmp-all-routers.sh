#!/bin/bash

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"
COMMUNITY="public"

echo "==========================================="
echo "Installing SNMP on all FRR routers"
echo "==========================================="
echo ""

for ROUTER in $ROUTERS; do
    echo "Configuring $ROUTER..."
    
    docker exec clab-ospf-network-$ROUTER bash -c '
        set -e
        
        # Update package list
        apt-get update -qq
        
        # Install SNMP daemon and tools
        DEBIAN_FRONTEND=noninteractive apt-get install -y snmpd snmp libsnmp-dev 2>&1 | grep -v "^debconf:"
        
        # Backup original config
        cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak 2>/dev/null || true
        
        # Create new snmpd configuration
        cat > /etc/snmp/snmpd.conf << "SNMPEOF"
###############################################################################
# SNMP Daemon Configuration
###############################################################################

# Listen on all interfaces
agentAddress udp:161,udp6:[::1]:161

# System information
sysLocation    Network Lab - '"$ROUTER"'
sysContact     Admin <admin@example.com>
sysServices    72

# Community string for read-only access
rocommunity '"$COMMUNITY"' default
rocommunity6 '"$COMMUNITY"' default

# Full access to .1 (all MIBs)
view   systemview    included   .1

# Map community to security name
com2sec readonly  default         '"$COMMUNITY"'
com2sec6 readonly  default         '"$COMMUNITY"'

# Map security name to group
group MyROGroup v1         readonly
group MyROGroup v2c        readonly
group MyROGroup usm        readonly

# Define access for the group
access MyROGroup ""      any       noauth    exact  systemview none none

# System information (always accessible)
sysobjectid 1.3.6.1.4.1.8072.3.2.10
sysservices 72

# Process monitoring
proc mountd
proc ntalkd 4

# Disk monitoring
disk / 10000

# Load monitoring
load 12 14 14

# Enable all standard MIBs
includeAllDisks 10%

# AgentX for extending
master agentx
agentXSocket tcp:localhost:705

# Logging
# 0=Emergency, 1=Alert, 2=Critical, 3=Error, 4=Warning, 5=Notice, 6=Info, 7=Debug
# Log to syslog with priority 'info'
[snmpd] logOption f /var/log/snmpd.log
[snmpd] doDebugging 0

SNMPEOF
        
        # Create log directory
        mkdir -p /var/log
        touch /var/log/snmpd.log
        
        # Stop any existing snmpd
        service snmpd stop 2>/dev/null || true
        killall snmpd 2>/dev/null || true
        sleep 1
        
        # Start snmpd
        service snmpd start
        
        # Verify its running
        sleep 2
        if pgrep snmpd > /dev/null; then
            echo "✓ '"$ROUTER"': SNMP daemon started successfully"
            
            # Test locally
            if snmpget -v2c -c '"$COMMUNITY"' localhost .1.3.6.1.2.1.1.5.0 2>&1 | grep -q "SNMPv2-MIB"; then
                echo "✓ '"$ROUTER"': SNMP responding correctly"
            else
                echo "⚠ '"$ROUTER"': SNMP started but test query failed"
            fi
        else
            echo "✗ '"$ROUTER"': Failed to start SNMP daemon"
            tail -20 /var/log/snmpd.log 2>/dev/null || echo "No log available"
        fi
    ' || echo "✗ $ROUTER: Installation failed"
    
    echo ""
done

echo "==========================================="
echo "Installation Complete"
echo "==========================================="
echo ""
echo "Verifying SNMP status on all routers..."
echo ""

for ROUTER in $ROUTERS; do
    STATUS=$(docker exec clab-ospf-network-$ROUTER pgrep snmpd > /dev/null 2>&1 && echo "RUNNING" || echo "NOT RUNNING")
    LISTENING=$(docker exec clab-ospf-network-$ROUTER netstat -ulnp 2>/dev/null | grep ":161 " | grep snmpd > /dev/null 2>&1 && echo "YES" || echo "NO")
    
    if [ "$STATUS" = "RUNNING" ] && [ "$LISTENING" = "YES" ]; then
        echo "  ✓ $ROUTER: SNMP running and listening on port 161"
    elif [ "$STATUS" = "RUNNING" ]; then
        echo "  ⚠ $ROUTER: SNMP running but not listening on port 161"
    else
        echo "  ✗ $ROUTER: SNMP not running"
    fi
done

echo ""
echo "Testing SNMP queries from one router to another..."
docker exec clab-ospf-network-csr23 snmpget -v2c -c $COMMUNITY 172.20.20.4 .1.3.6.1.2.1.1.5.0 2>&1 | head -5

echo ""
echo "Wait 30 seconds for OTEL to start collecting data..."
