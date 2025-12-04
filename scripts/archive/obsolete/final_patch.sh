#!/bin/bash

echo "=================================================="
echo "  OSPF OTEL Lab - Final Patch v21.4"
echo "=================================================="
echo ""

SCRIPT="connect.sh"
BACKUP="connect.sh.backup.$(date +%Y%m%d-%H%M%S)"

# Backup
echo "📦 Backup: $BACKUP"
cp "$SCRIPT" "$BACKUP"

# Find option 85
LINE_85=$(grep -n "^[[:space:]]*85)" "$SCRIPT" | head -1 | cut -d: -f1)
echo "📍 Option 85: line $LINE_85"

# Find next option
NEXT=$(awk -v start="$LINE_85" 'NR > start && /^[[:space:]]*[0-9]+\)/ {print NR; exit}' "$SCRIPT")
echo "📍 Next option: line $NEXT"

# Extract before
head -n $((LINE_85 - 1)) "$SCRIPT" > "${SCRIPT}.new"

# Write the new option 85 directly (no heredoc)
cat >> "${SCRIPT}.new" << 'ENDOPT85'
        85)
            clear
            TIMESTAMP=$(date +%Y%m%d-%H%M%S)
            EXPORT_DIR="$HOME/ospf-otel-lab/exports/full-$TIMESTAMP"
            mkdir -p "$EXPORT_DIR"/{routers,telemetry,topology,logs}
            
            echo "Exporting configurations..."
            echo ""
            
            echo -n "  Topology... "
            if [ -f "$HOME/ospf-otel-lab/ospf-network.clab.yml" ]; then
                cp "$HOME/ospf-otel-lab/ospf-network.clab.yml" "$EXPORT_DIR/topology/"
                echo "done"
            else
                echo "not found"
            fi
            
            echo -n "  Routers... "
            count=0
            for r in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
                if docker exec clab-ospf-network-$r vtysh -c "show running-config" > "$EXPORT_DIR/routers/$r.conf" 2>/dev/null; then
                    count=$((count + 1))
                fi
            done
            echo "done ($count/7)"
            
            echo -n "  OTEL config... "
            docker exec clab-ospf-network-otel-collector cat /etc/otelcol-contrib/config.yaml > "$EXPORT_DIR/telemetry/otel-collector.yml" 2>/dev/null
            echo "done"
            
            echo -n "  Logstash config... "
            docker exec clab-ospf-network-logstash cat /usr/share/logstash/pipeline/netflow.conf > "$EXPORT_DIR/telemetry/logstash-netflow.conf" 2>/dev/null
            echo "done"
            
            if [ -f "$HOME/ospf-otel-lab/.env" ]; then
                cp "$HOME/ospf-otel-lab/.env" "$EXPORT_DIR/telemetry/"
            fi
            
            docker logs --tail 500 clab-ospf-network-otel-collector > "$EXPORT_DIR/logs/otel.log" 2>/dev/null
            docker logs --tail 500 clab-ospf-network-logstash > "$EXPORT_DIR/logs/logstash.log" 2>/dev/null
            
            echo "OSPF OTEL Lab Export" > "$EXPORT_DIR/README.txt"
            echo "Date: $(date)" >> "$EXPORT_DIR/README.txt"
            echo "" >> "$EXPORT_DIR/README.txt"
            echo "Contents:" >> "$EXPORT_DIR/README.txt"
            echo "- topology/ospf-network.clab.yml" >> "$EXPORT_DIR/README.txt"
            echo "- routers/*.conf (7 routers)" >> "$EXPORT_DIR/README.txt"
            echo "- telemetry/otel-collector.yml" >> "$EXPORT_DIR/README.txt"
            echo "- telemetry/logstash-netflow.conf" >> "$EXPORT_DIR/README.txt"
            echo "- telemetry/.env" >> "$EXPORT_DIR/README.txt"
            echo "- logs/*.log" >> "$EXPORT_DIR/README.txt"
            
            echo ""
            echo "Export complete!"
            echo "Location: $EXPORT_DIR"
            if [ -d "$EXPORT_DIR" ]; then
                echo "Size: $(du -sh "$EXPORT_DIR" 2>/dev/null | cut -f1)"
            fi
            echo ""
            read -p "Press Enter to continue..."
            ;;
ENDOPT85

# Add rest of file
tail -n +$NEXT "$SCRIPT" >> "${SCRIPT}.new"

# Replace
mv "${SCRIPT}.new" "$SCRIPT"

echo ""
echo "✅ Patched!"
echo ""
echo "Testing..."
if bash -n "$SCRIPT"; then
    echo "✅ Syntax OK!"
    echo ""
    echo "Success! Try: ./connect.sh"
else
    echo "❌ Failed"
    bash -n "$SCRIPT" 2>&1 | head -10
    mv "$BACKUP" "$SCRIPT"
    echo "Restored backup"
    exit 1
fi
