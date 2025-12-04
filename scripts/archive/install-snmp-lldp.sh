#!/bin/bash

echo "========================================="
echo "Installing SNMP + LLDP on All Routers"
echo "========================================="

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

for router in $ROUTERS; do
  echo ""
  echo "Setting up $router..."
  
  CONTAINER="clab-ospf-network-$router"
  
  # Install SNMP packages
  echo "  Installing SNMP..."
  docker exec $CONTAINER apk update >/dev/null 2>&1
  docker exec $CONTAINER apk add --no-cache net-snmp net-snmp-tools openrc >/dev/null 2>&1
  
  # Install LLDP
  echo "  Installing LLDP..."
  docker exec $CONTAINER apk add --no-cache lldpd >/dev/null 2>&1
  
  # Create necessary directories
  docker exec $CONTAINER mkdir -p /var/agentx /var/log /var/run /run/openrc
  docker exec $CONTAINER touch /run/openrc/softlevel
  docker exec $CONTAINER chmod 755 /var/agentx
  
  # Configure SNMP daemon
  docker exec $CONTAINER sh -c 'cat > /etc/snmp/snmpd.conf << "SNMPEOF"
agentAddress udp:0.0.0.0:161
rocommunity public default
syslocation "OSPF Network Lab"
syscontact "admin@lab.local"
master agentx
agentXSocket /var/agentx/master
view systemview included .1
rocommunity public default -V systemview
dontLogTCPWrappersConnects yes
SNMPEOF'
  
  # Get actual hostname
  HOSTNAME=$(docker exec $CONTAINER hostname)
  
  # Configure LLDP daemon with rx-and-tx (CRITICAL)
  docker exec $CONTAINER sh -c "cat > /etc/lldpd.conf << LLDPEOF
configure lldp status rx-and-tx
configure lldp tx-interval 10
configure lldp tx-hold 4
configure system hostname $HOSTNAME
configure system description \"FRR Router - OSPF Lab\"
configure system ip management pattern 172.20.*
configure lldp portidsubtype macaddress
LLDPEOF"
  
  # Kill any existing processes
  docker exec $CONTAINER killall snmpd 2>/dev/null || true
  docker exec $CONTAINER pkill -9 lldpd 2>/dev/null || true
  sleep 2
  
  # Start SNMP daemon
  docker exec $CONTAINER /usr/sbin/snmpd -Lo -C -c /etc/snmp/snmpd.conf >/dev/null 2>&1
  
  # Start LLDP daemon (without -r flag to allow transmission)
  docker exec -d $CONTAINER lldpd 2>/dev/null
  
  # Verify services are running
  sleep 2
  SNMP_OK=$(docker exec $CONTAINER snmpget -v2c -c public localhost 1.3.6.1.2.1.1.5.0 2>&1 | grep -q "SNMPv2-MIB::sysName.0" && echo "✓" || echo "⚠")
  LLDP_OK=$(docker exec $CONTAINER pgrep lldpd >/dev/null 2>&1 && echo "✓" || echo "⚠")
  
  echo "  $SNMP_OK SNMP | $LLDP_OK LLDP | $router configured"
done

echo ""
echo "Waiting 30 seconds for LLDP discovery..."
sleep 30

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo ""

# Verify LLDP neighbors
TOTAL_NEIGHBORS=0
for router in $ROUTERS; do
    CONTAINER="clab-ospf-network-$router"
    COUNT=$(docker exec $CONTAINER lldpcli show neighbors summary 2>/dev/null | grep -c "Interface:" || echo 0)
    echo "  $router: $COUNT neighbors"
    TOTAL_NEIGHBORS=$((TOTAL_NEIGHBORS + COUNT))
done

echo ""
echo "Total LLDP neighbors discovered: $TOTAL_NEIGHBORS"

if [ $TOTAL_NEIGHBORS -gt 0 ]; then
    echo "✓ LLDP working!"
else
    echo "⚠ No LLDP neighbors discovered yet. Wait a bit longer."
fi

echo ""
echo "Verify SNMP: ./scripts/test-snmp-detailed.sh"
echo "Verify LLDP: ./scripts/show-lldp-neighbors.sh"
echo ""
