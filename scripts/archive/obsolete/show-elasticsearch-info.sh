#!/bin/bash

echo "========================================="
echo "Elasticsearch Configuration Info"
echo "========================================="
echo ""

ENV_FILE="$HOME/ospf-otel-lab/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "✗ No configuration found"
    echo ""
    echo "Configure with: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

source "$ENV_FILE"

echo "Configuration File: $ENV_FILE"
echo "─────────────────────────────────────────"
cat "$ENV_FILE"
echo "─────────────────────────────────────────"
echo ""

echo "Parsed Values:"
echo "  ES_ENDPOINT: ${ES_ENDPOINT:-<not set>}"
echo "  ES_API_KEY:  ${ES_API_KEY:0:30}... (${#ES_API_KEY} chars)"
echo ""

# Show where it's being used
echo "Usage in Configuration:"
echo "─────────────────────────────────────────"

# Check OTEL config
if [ -f configs/otel/otel-collector.yml ]; then
    echo "✓ OTEL Collector Config: configs/otel/otel-collector.yml"
    echo "  Endpoint references:"
    grep -n "ES_ENDPOINT\|$ES_ENDPOINT" configs/otel/otel-collector.yml | head -3 | sed 's/^/    /'
else
    echo "✗ OTEL Collector Config: Not found"
fi

echo ""

# Check LLDP export script
if [ -f scripts/lldp-to-elasticsearch.sh ]; then
    echo "✓ LLDP Export Script: scripts/lldp-to-elasticsearch.sh"
    echo "  Sources .env file for credentials"
else
    echo "✗ LLDP Export Script: Not found"
fi

echo ""

# Check LLDP service
if systemctl list-unit-files | grep -q lldp-export; then
    echo "✓ LLDP Service: Installed"
    SERVICE_FILE="/etc/systemd/system/lldp-export.service"
    if [ -f "$SERVICE_FILE" ]; then
        echo "  Service file: $SERVICE_FILE"
        echo "  Working directory:"
        grep WorkingDirectory "$SERVICE_FILE" | sed 's/^/    /'
    fi
else
    echo "✗ LLDP Service: Not installed"
fi

echo ""
echo "─────────────────────────────────────────"
echo ""

# Test connection
echo "Connection Test:"
./scripts/test-elasticsearch-connection.sh 2>&1 | grep -E "^(✓|✗|  )"

echo ""
echo "Commands:"
echo "  Test connection:     ./scripts/test-elasticsearch-connection.sh"
echo "  Reconfigure:         ./scripts/reconfigure-elasticsearch.sh"
echo "  View status:         ./scripts/status.sh"
echo ""
