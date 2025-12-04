#!/bin/bash

echo "=================================================="
echo "  NetFlow Configuration Extractor"
echo "=================================================="
echo ""

OUTPUT_FILE="$HOME/ospf-otel-lab/configs/netflow-extracted-$(date +%Y%m%d-%H%M%S).txt"

echo "Extracting all NetFlow configurations to:"
echo "  $OUTPUT_FILE"
echo ""

{
    echo "# NetFlow Configuration Extract"
    echo "# Generated: $(date)"
    echo "# ============================================"
    echo ""
    
    # Check each router
    for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
        echo ""
        echo "# ============================================"
        echo "# Router: $router"
        echo "# ============================================"
        echo ""
        
        if docker ps | grep -q "clab-ospf-network-$router"; then
            # Get full running config
            echo "## FRRouting Configuration:"
            docker exec clab-ospf-network-$router vtysh -c "show running-config" 2>/dev/null | \
                grep -iE "(flow|netflow)" || echo "# No NetFlow in FRR config"
            
            echo ""
            echo "## Processes:"
            docker exec clab-ospf-network-$router ps aux 2>/dev/null | \
                grep -E "(softflowd|fprobe|pmacct)" | grep -v grep || echo "# No NetFlow processes"
            
            echo ""
            echo "## Startup Scripts:"
            docker exec clab-ospf-network-$router cat /usr/local/bin/start-netflow.sh 2>/dev/null || \
                echo "# No startup script"
            
            echo ""
            echo "## System Configuration:"
            docker exec clab-ospf-network-$router cat /etc/default/softflowd 2>/dev/null || \
                echo "# No /etc/default/softflowd"
            
            echo ""
        else
            echo "# Router not running"
        fi
    done
    
    echo ""
    echo "# ============================================"
    echo "# End of Extract"
    echo "# ============================================"
    
} > "$OUTPUT_FILE"

echo "✓ Extraction complete!"
echo ""
echo "View the file:"
echo "  cat $OUTPUT_FILE"
echo ""
echo "Or open in editor:"
echo "  nano $OUTPUT_FILE"
