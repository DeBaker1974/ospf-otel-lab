#!/bin/bash

LOGSTASH_CONTAINER="clab-ospf-network-logstash"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "  Logstash Pipelines Inspector"
echo "=================================================="
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${LOGSTASH_CONTAINER}$"; then
    echo -e "${RED}✗${NC} Logstash container not running"
    exit 1
fi

echo -e "${GREEN}✓${NC} Logstash container is running"
echo ""

# 1. Check pipeline configuration directory
echo "=== Pipeline Configuration Files ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    PIPELINE_DIR="/usr/share/logstash/pipeline"
    
    if [ -d "$PIPELINE_DIR" ]; then
        echo "Pipeline directory: $PIPELINE_DIR"
        echo ""
        echo "Files found:"
        ls -lah "$PIPELINE_DIR" 2>/dev/null | grep -v "^total" | grep -v "^d"
        echo ""
        
        echo "Configuration files:"
        for conf in "$PIPELINE_DIR"/*.conf; do
            if [ -f "$conf" ]; then
                basename "$conf"
            fi
        done
    else
        echo "Pipeline directory not found"
    fi
'

echo ""
echo "=== Pipeline Contents ==="
echo ""

# 2. Show content of each pipeline
docker exec $LOGSTASH_CONTAINER bash -c '
    PIPELINE_DIR="/usr/share/logstash/pipeline"
    
    for conf in "$PIPELINE_DIR"/*.conf "$PIPELINE_DIR"/*.conf.*; do
        if [ -f "$conf" ]; then
            echo "----------------------------------------"
            echo "File: $(basename $conf)"
            echo "Size: $(stat -f%z "$conf" 2>/dev/null || stat -c%s "$conf" 2>/dev/null) bytes"
            echo "----------------------------------------"
            cat "$conf"
            echo ""
            echo ""
        fi
    done
'

echo ""
echo "=== Logstash Main Configuration ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    if [ -f /usr/share/logstash/config/logstash.yml ]; then
        echo "Logstash settings (logstash.yml):"
        echo "----------------------------------------"
        cat /usr/share/logstash/config/logstash.yml | grep -v "^#" | grep -v "^$"
    fi
'

echo ""
echo "=== Pipeline Settings ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    if [ -f /usr/share/logstash/config/pipelines.yml ]; then
        echo "Pipeline definitions (pipelines.yml):"
        echo "----------------------------------------"
        cat /usr/share/logstash/config/pipelines.yml | grep -v "^#" | grep -v "^$"
    else
        echo "pipelines.yml not found (using default single pipeline)"
    fi
'

echo ""
echo "=== Active Pipeline Statistics (via API) ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    if command -v curl >/dev/null 2>&1; then
        echo "Querying Logstash API..."
        curl -s http://localhost:9600/_node/stats/pipelines?pretty 2>/dev/null | head -100
    else
        echo "curl not available in container"
    fi
'

echo ""
echo "=== Input Plugins Status ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    echo "Active network listeners:"
    netstat -tuln 2>/dev/null | grep -E "LISTEN|udp" | grep -E "2055|5044|9600" || echo "No standard Logstash ports found"
'

echo ""
echo "=== Recent Pipeline Activity ==="
echo ""
docker logs --tail 100 $LOGSTASH_CONTAINER 2>&1 | grep -E "Pipeline|Starting|Stopping|input|output" | tail -20

echo ""
echo "=== Pipeline Performance ==="
echo ""
docker exec $LOGSTASH_CONTAINER bash -c '
    if command -v curl >/dev/null 2>&1; then
        curl -s http://localhost:9600/_node/stats/pipelines?pretty 2>/dev/null | \
        grep -E "\"id\"|events|duration" | head -30
    fi
'

echo ""
echo "=================================================="
echo "  Inspection Complete"
echo "=================================================="
