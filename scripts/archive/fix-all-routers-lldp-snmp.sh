#!/bin/bash
# fix-all-routers-lldp-snmp.sh

cd ~/ospf-otel-lab

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Fixing LLDP SNMP on All Routers (Final)           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

for router in $ROUTERS; do
  container="clab-ospf-network-$router"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $router"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Stop all existing processes
  docker exec "$container" pkill -9 snmpd 2>/dev/null
  docker exec "$container" pkill -9 lldpd 2>/dev/null
  sleep 2
  
  # Ensure AgentX config exists (append if not present)
  docker exec "$container" bash -c "
    if ! grep -q 'master agentx' /etc/snmp/snmpd.conf 2>/dev/null; then
      cat >> /etc/snmp/snmpd.conf << 'EOF'

# AgentX configuration for lldpd
master agentx
agentXSocket /var/agentx/master
agentXPerms 0660 0550 root snmp
EOF
      echo '  ✓ Added AgentX config'
    else
      echo '  ✓ AgentX config exists'
    fi
  "
  
  # Create directory
  docker exec "$container" mkdir -p /var/agentx
  docker exec "$container" chmod 777 /var/agentx
  
  # Start snmpd
  docker exec "$container" /usr/sbin/snmpd -c /etc/snmp/snmpd.conf -Lsd -Lf /dev/null udp:161
  sleep 4  # Wait for socket creation
  
  # Check if socket was created
  if docker exec "$container" test -S /var/agentx/master; then
    echo "  ✅ AgentX socket created"
  else
    echo "  ❌ Socket not found - waiting 3 more seconds..."
    sleep 3
    if docker exec "$container" test -S /var/agentx/master; then
      echo "  ✅ Socket now present"
    else
      echo "  ❌ Socket still missing - SKIPPING"
      continue
    fi
  fi
  
  # Start lldpd with AgentX
  docker exec "$container" lldpd -x -X /var/agentx/master 2>&1 | grep -E "(INFO|WARN)" | head -3
  sleep 3
  
  # Verify both are running
  snmpd_running=$(docker exec "$container" ps aux | grep -c "[s]nmpd")
  lldpd_running=$(docker exec "$container" ps aux | grep -c "[l]ldpd")
  
  if [ "$snmpd_running" -gt 0 ] && [ "$lldpd_running" -gt 0 ]; then
    echo "  ✅ Both snmpd and lldpd running"
  else
    echo "  ⚠️  Process check: snmpd=$snmpd_running, lldpd=$lldpd_running"
  fi
  
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Waiting 20 seconds for LLDP neighbor discovery..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
sleep 20

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║            Testing SNMP LLDP on All Routers               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

SUCCESS=0
FAILURE=0
TOTAL_NEIGHBORS=0

for i in 23 24 25 26 27 28 29; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  csr$i (172.20.20.$i)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  result=$(snmpwalk -v2c -c public -t 4 -r 1 172.20.20.$i 1.0.8802.1.1.2.1.4.1.1.9 2>&1)
  
  if echo "$result" | grep -q "STRING"; then
    neighbor_count=$(echo "$result" | grep -c "STRING")
    echo "  ✅ SUCCESS! ($neighbor_count neighbors discovered)"
    echo "$result" | head -6 | sed 's/^/    /'
    ((SUCCESS++))
    TOTAL_NEIGHBORS=$((TOTAL_NEIGHBORS + neighbor_count))
  else
    echo "  ❌ FAILED"
    echo "$result" | head -2 | sed 's/^/    /'
    ((FAILURE++))
  fi
  echo ""
done

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                        SUMMARY                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Routers working:     $SUCCESS / 7"
echo "  Routers failed:      $FAILURE / 7"
echo "  Total neighbors:     $TOTAL_NEIGHBORS"
echo ""

if [ $SUCCESS -eq 7 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🎉 PERFECT! All 7 routers are reporting LLDP via SNMP!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Next steps:"
  echo "  1. Restart OTEL collector:"
  echo "     docker restart clab-ospf-network-otel-collector"
  echo ""
  echo "  2. Wait 2 minutes for data collection"
  echo ""
  echo "  3. Check Elasticsearch for lldp-topology index"
  echo ""
elif [ $SUCCESS -gt 0 ]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ⚠️  Partial success: $SUCCESS routers working"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Routers that failed need manual troubleshooting."
  echo "Still worth restarting OTEL collector to collect from working routers."
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ❌ No routers working - troubleshooting needed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "Script completed at $(date)"
