#!/bin/bash

echo "========================================="
echo "EMERGENCY DIAGNOSTIC v11.0"
echo "========================================="
echo ""

# 1. Check OTEL status
echo "1. OTEL Collector Status:"
OTEL_STATUS=$(docker inspect clab-ospf-network-otel-collector --format='{{.State.Status}}' 2>/dev/null)
echo "   Status: ${OTEL_STATUS:-NOT FOUND}"

if [ "$OTEL_STATUS" != "running" ]; then
    echo "✗ OTEL NOT RUNNING!"
    echo ""
    echo "Recent logs:"
    docker logs --tail 30 clab-ospf-network-otel-collector
    exit 1
fi

# 2. Check for OTEL errors
echo ""
echo "2. OTEL Errors (last 2 minutes):"
ERRORS=$(docker logs --since 2m clab-ospf-network-otel-collector 2>&1 | grep -i "error" | head -10)
if [ -z "$ERRORS" ]; then
    echo "✓ No errors"
else
    echo "$ERRORS" | sed 's/^/   /'
fi

# 3. Check if OTEL is generating metrics
echo ""
echo "3. Metrics Generation:"
DATAPOINTS=$(docker logs --since 2m clab-ospf-network-otel-collector 2>&1 | grep "data points" | tail -5)
if [ -z "$DATAPOINTS" ]; then
    echo "✗ NO METRICS BEING GENERATED!"
    echo ""
    echo "   Checking OTEL startup logs:"
    docker logs clab-ospf-network-otel-collector 2>&1 | grep -E "(error|Error|failed|started)" | tail -20
else
    echo "✓ Metrics being generated:"
    echo "$DATAPOINTS" | sed 's/^/   /'
fi

# 4. Check Elasticsearch configuration
echo ""
echo "4. Elasticsearch Configuration:"
if [ -f .env ]; then
    source .env
    if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
        echo "  Endpoint: $ES_ENDPOINT"
        
        # Test connection
        ES_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/" 2>/dev/null)
        if [ "$ES_HEALTH" = "200" ]; then
            echo "✓ Connection successful"
            
            # Check metrics
            DOC_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" 2>/dev/null | jq -r '.count // 0')
            echo "  SNMP metrics: ${DOC_COUNT:-0} documents"
            
            LLDP_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/lldp-topology/_count" 2>/dev/null | jq -r '.count // 0')
            echo "  LLDP topology: ${LLDP_COUNT:-0} documents"
            
            # Check metric types
            METRIC_TYPES=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_search?size=0" -H 'Content-Type: application/json' -d '{
              "aggs": {
                "metric_types": {
                  "cardinality": {"field": "metric.name.keyword"}
                }
              }
            }' 2>/dev/null | jq -r '.aggregations.metric_types.value // 0')
            echo "  Metric types: ${METRIC_TYPES} (Expected: 30-40)"
        else
            echo "✗ Connection failed (HTTP $ES_HEALTH)"
        fi
    else
        echo "✗ Configuration incomplete"
    fi
else
    echo "✗ .env file not found"
    echo "  Run: ./scripts/configure-elasticsearch.sh"
fi

# 5. Check SNMP
echo ""
echo "5. SNMP Status (CSR28):"
SNMP_TEST=$(docker exec clab-ospf-network-csr28 snmpget -v2c -c public localhost 1.3.6.1.2.1.1.5.0 2>&1)
if echo "$SNMP_TEST" | grep -q "SNMPv2-MIB"; then
    echo "✓ SNMP responding"
else
    echo "✗ SNMP not responding"
    echo "   Response: $SNMP_TEST"
fi

# 6. Check LLDP
echo ""
echo "6. LLDP Status:"
LLDP_RUNNING=0
LLDP_NEIGHBORS=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if docker exec clab-ospf-network-$router pgrep lldpd >/dev/null 2>&1; then
        LLDP_RUNNING=$((LLDP_RUNNING + 1))
        COUNT=$(docker exec clab-ospf-network-$router lldpcli show neighbors summary 2>/dev/null | grep -c "Interface:" || echo 0)
        LLDP_NEIGHBORS=$((LLDP_NEIGHBORS + COUNT))
    fi
done
echo "  Daemons running: $LLDP_RUNNING/7"
echo "  Neighbors: $LLDP_NEIGHBORS"

if [ $LLDP_RUNNING -eq 7 ] && [ $LLDP_NEIGHBORS -gt 0 ]; then
    echo "✓ LLDP operational"
else
    echo "⚠ LLDP issues detected"
    echo ""
    echo "  Debug LLDP on CSR28:"
    echo "  docker exec clab-ospf-network-csr28 lldpcli show neighbors"
fi

# 7. Check LLDP export service
echo ""
echo "7. LLDP Export Service:"
if systemctl is-active --quiet lldp-export 2>/dev/null; then
    echo "✓ Service running"
    
    # Check recent logs
    if [ -f ~/ospf-otel-lab/logs/lldp-export.log ]; then
        RECENT_LINES=$(tail -n 3 ~/ospf-otel-lab/logs/lldp-export.log 2>/dev/null)
        if [ -n "$RECENT_LINES" ]; then
            echo "  Recent activity:"
            echo "$RECENT_LINES" | sed 's/^/    /'
        fi
    fi
else
    echo "✗ Service not running"
    echo "  Start: sudo systemctl start lldp-export"
fi

# 8. Check config file
echo ""
echo "8. OTEL Config File:"
if [ -f ~/ospf-otel-lab/configs/otel/otel-collector.yml ]; then
    LINES=$(wc -l < ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    SIZE=$(du -h ~/ospf-otel-lab/configs/otel/otel-collector.yml | cut -f1)
    echo "   Size: $SIZE ($LINES lines)"
    
    RECEIVER_COUNT=$(grep "^  snmp/" ~/ospf-otel-lab/configs/otel/otel-collector.yml | wc -l)
    echo "   SNMP receivers: $RECEIVER_COUNT (Expected: 21)"
    
    # Check for all metric types
    HAS_INTERFACE=$(grep -c "network.interface.in.bytes" ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    HAS_TCP=$(grep -c "network.tcp" ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    HAS_UDP=$(grep -c "network.udp" ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    HAS_ARP=$(grep -c "network.arp" ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    HAS_LLDP=$(grep -c "network.lldp" ~/ospf-otel-lab/configs/otel/otel-collector.yml)
    
    echo "   Metric types configured:"
    echo "     Interface: $HAS_INTERFACE"
    echo "     TCP: $HAS_TCP"
    echo "     UDP: $HAS_UDP"
    echo "     ARP: $HAS_ARP"
    echo "     LLDP (SNMP): $HAS_LLDP"
else
    echo "✗ CONFIG FILE NOT FOUND!"
fi

echo ""
echo "========================================="
echo "DIAGNOSIS COMPLETE"
echo "========================================="
echo ""

# Provide recommendations
if [ "$OTEL_STATUS" != "running" ]; then
    echo "❌ ISSUE: OTEL Collector not running"
    echo ""
    echo "FIX: docker restart clab-ospf-network-otel-collector"
elif [ -z "$ES_ENDPOINT" ]; then
    echo "❌ ISSUE: Elasticsearch not configured"
    echo ""
    echo "FIX: ./scripts/configure-elasticsearch.sh"
elif [ "$ES_HEALTH" != "200" ]; then
    echo "❌ ISSUE: Cannot connect to Elasticsearch"
    echo ""
    echo "FIX: Check credentials with ./scripts/configure-elasticsearch.sh"
elif [ "${DOC_COUNT:-0}" -eq 0 ]; then
    echo "⚠ ISSUE: No SNMP metrics in Elasticsearch"
    echo ""
    echo "FIX:"
    echo "  ./scripts/install-snmp-lldp.sh"
    echo "  ./scripts/create-otel-config-fast-mode.sh"
    echo "  docker restart clab-ospf-network-otel-collector"
elif [ "${METRIC_TYPES:-0}" -lt 20 ]; then
    echo "⚠ ISSUE: Not all metrics being collected"
    echo "  Found: ${METRIC_TYPES} metrics"
    echo "  Expected: 30-40 metrics"
    echo ""
    echo "FIX: Regenerate config with all metrics"
    echo "  ./scripts/create-otel-config-fast-mode.sh"
    echo "  docker restart clab-ospf-network-otel-collector"
elif [ $LLDP_RUNNING -lt 7 ]; then
    echo "⚠ ISSUE: LLDP daemons not running on all routers"
    echo ""
    echo "FIX: ./scripts/install-snmp-lldp.sh"
elif [ $LLDP_NEIGHBORS -eq 0 ]; then
    echo "⚠ ISSUE: LLDP daemons running but no neighbors"
    echo ""
    echo "Check LLDP configuration:"
    echo "  docker exec clab-ospf-network-csr28 cat /etc/lldpd.conf"
    echo "  docker exec clab-ospf-network-csr28 lldpcli show neighbors"
elif ! systemctl is-active --quiet lldp-export 2>/dev/null; then
    echo "⚠ ISSUE: LLDP export service not running"
    echo ""
    echo "FIX: ./scripts/setup-lldp-service.sh"
else
    echo "✅ System appears healthy"
    echo ""
    echo "SNMP metrics: ${DOC_COUNT:-0} (${METRIC_TYPES:-0} types)"
    echo "LLDP topology: ${LLDP_COUNT:-0}"
    echo "LLDP neighbors: ${LLDP_NEIGHBORS}"
fi

echo ""
