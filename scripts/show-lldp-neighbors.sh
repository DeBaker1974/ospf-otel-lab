#!/bin/bash

echo "========================================="
echo "LLDP Neighbor Discovery"
echo "========================================="
echo ""

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

TOTAL=0
for router in $ROUTERS; do
    CONTAINER="clab-ospf-network-$router"
    
    echo "Router: $router"
    echo "─────────────────────────────────────────"
    
    if ! docker exec $CONTAINER pgrep lldpd >/dev/null 2>&1; then
        echo "  ✗ LLDP daemon not running"
        echo ""
        continue
    fi
    
    # Get neighbors
    NEIGHBORS=$(docker exec $CONTAINER lldpcli show neighbors 2>/dev/null)
    
    if [ -z "$NEIGHBORS" ]; then
        echo "  No neighbors discovered"
        echo ""
        continue
    fi
    
    # Parse and display neighbors
    echo "$NEIGHBORS" | awk '
    BEGIN { interface=""; neighbor="" }
    /^Interface:/ {  
        if (interface != "") print ""
        interface=$2
        gsub(/,/, "", interface)
        printf "  Interface: %s\n", interface
    }
    /SysName:/ {
        neighbor=$2
        printf "    └─ Neighbor: %s\n", neighbor
    }
    /PortDescr:/ {
        port=$2
        printf "       Port: %s\n", port
    }
    /MgmtIP:/ {
        mgmt=$2
        printf "       Mgmt IP: %s\n", mgmt
    }
    '
    
    COUNT=$(echo "$NEIGHBORS" | grep -c "^Interface:" || echo 0)
    TOTAL=$((TOTAL + COUNT))
    
    echo ""
done

echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Total LLDP adjacencies: $TOTAL"
echo ""

if [ $TOTAL -gt 0 ]; then
    echo "✓ LLDP discovery working"
    echo ""
    echo "Next steps:"
    echo "  1. View service status: ./scripts/lldp-status.sh"
    echo "  2. Setup service:       ./scripts/setup-lldp-service.sh"
else
    echo "✗ No LLDP neighbors found"
    echo ""
    echo "Troubleshoot:"
    echo "  1. Check if lldpd is running: docker exec clab-ospf-network-csr28 pgrep lldpd"
    echo "  2. Check lldpd config: docker exec clab-ospf-network-csr28 cat /etc/lldpd.conf"
    echo "  3. Reinstall: ./scripts/install-snmp-lldp.sh"
fi

echo ""
