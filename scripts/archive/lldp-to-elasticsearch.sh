#!/bin/bash

# ========================================
# LLDP to Elasticsearch Exporter
# Parses plain text format (VERIFIED WORKING)
# Collection interval: 10 seconds
# ========================================

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"
INDEX_NAME="lldp-topology"
INTERVAL=10

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Load environment variables
ENV_FILE="$HOME/ospf-otel-lab/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}✗ .env file not found${NC}"
    echo ""
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

source "$ENV_FILE"

if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_API_KEY" ]; then
    echo -e "${RED}✗ Elasticsearch configuration missing${NC}"
    echo ""
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

ES_HOST="$ES_ENDPOINT"

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ✗ $1${NC}"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

echo "========================================="
echo "LLDP to Elasticsearch Exporter"
echo "  Plain Text Parser (VERIFIED)"
echo "  Serverless Compatible"
echo "========================================="
echo ""
echo "Configuration:"
echo "  Interval:      ${INTERVAL}s"
echo "  Routers:       7"
echo "  Elasticsearch: $ES_HOST"
echo "  Index:         $INDEX_NAME"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Test connection first
log "Testing Elasticsearch connection..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey $ES_API_KEY" "$ES_HOST/" 2>/dev/null)

if [ "$TEST_RESPONSE" != "200" ]; then
    log_error "Cannot connect to Elasticsearch (HTTP $TEST_RESPONSE)"
    exit 1
fi

log_success "Connected to Elasticsearch"
log "Index will auto-create on first document (Serverless)"
echo ""

# Collection function
collect_lldp() {
    local TOTAL_DOCS=0
    local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    
    for router in $ROUTERS; do
        CONTAINER="clab-ospf-network-$router"
        
        # Check if lldpd is running
        if ! docker exec $CONTAINER pgrep lldpd >/dev/null 2>&1; then
            continue
        fi
        
        # Get management IP
        MGMT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
        
        # Get LLDP neighbors in plain text format
        LLDP_OUTPUT=$(docker exec $CONTAINER lldpcli show neighbors 2>/dev/null)
        
        if [ -z "$LLDP_OUTPUT" ]; then
            continue
        fi
        
        # Parse the output
        LOCAL_IFACE=""
        CHASSIS_ID=""
        SYSNAME=""
        SYSDESCR=""
        MGMT_IP_NEIGHBOR=""
        PORT_ID=""
        PORT_DESCR=""
        
        while IFS= read -r line; do
            # Remove leading/trailing whitespace
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Match patterns
            if [[ $line =~ ^Interface:[[:space:]]+([^,]+) ]]; then
                # Save previous entry if complete
                if [ -n "$LOCAL_IFACE" ] && [ -n "$CHASSIS_ID" ]; then
                    # Create document
                    ES_DOC=$(cat <<ESDOC
{
  "@timestamp": "$TIMESTAMP",
  "router": "$router",
  "router_ip": "$MGMT_IP",
  "local_interface": "$LOCAL_IFACE",
  "neighbor_chassis_id": "$CHASSIS_ID",
  "neighbor_sysname": "$SYSNAME",
  "neighbor_description": "$SYSDESCR",
  "neighbor_mgmt_ip": "$MGMT_IP_NEIGHBOR",
  "neighbor_port_id": "$PORT_ID",
  "neighbor_port_descr": "$PORT_DESCR",
  "discovery_method": "lldp"
}
ESDOC
)
                    
                    # Send to Elasticsearch
                    RESPONSE=$(curl -s -X POST "$ES_HOST/$INDEX_NAME/_doc" \
                        -H "Authorization: ApiKey $ES_API_KEY" \
                        -H 'Content-Type: application/json' \
                        -d "$ES_DOC" 2>&1)
                    
                    if echo "$RESPONSE" | grep -q '"result":"created"'; then
                        TOTAL_DOCS=$((TOTAL_DOCS + 1))
                    fi
                fi
                
                # Start new entry
                LOCAL_IFACE="${BASH_REMATCH[1]}"
                CHASSIS_ID=""
                SYSNAME=""
                SYSDESCR=""
                MGMT_IP_NEIGHBOR=""
                PORT_ID=""
                PORT_DESCR=""
                
            elif [[ $line =~ ^ChassisID:[[:space:]]+mac[[:space:]]+(.+)$ ]]; then
                CHASSIS_ID="${BASH_REMATCH[1]}"
                
            elif [[ $line =~ ^SysName:[[:space:]]+(.+)$ ]]; then
                SYSNAME="${BASH_REMATCH[1]}"
                
            elif [[ $line =~ ^SysDescr:[[:space:]]+(.+)$ ]]; then
                SYSDESCR="${BASH_REMATCH[1]}"
                
            elif [[ $line =~ ^MgmtIP:[[:space:]]+(.+)$ ]]; then
                MGMT_IP_NEIGHBOR="${BASH_REMATCH[1]}"
                
            elif [[ $line =~ ^PortID:[[:space:]]+mac[[:space:]]+(.+)$ ]]; then
                PORT_ID="${BASH_REMATCH[1]}"
                
            elif [[ $line =~ ^PortDescr:[[:space:]]+(.+)$ ]]; then
                PORT_DESCR="${BASH_REMATCH[1]}"
            fi
            
        done <<< "$LLDP_OUTPUT"
        
        # Don't forget the last entry
        if [ -n "$LOCAL_IFACE" ] && [ -n "$CHASSIS_ID" ]; then
            ES_DOC=$(cat <<ESDOC
{
  "@timestamp": "$TIMESTAMP",
  "router": "$router",
  "router_ip": "$MGMT_IP",
  "local_interface": "$LOCAL_IFACE",
  "neighbor_chassis_id": "$CHASSIS_ID",
  "neighbor_sysname": "$SYSNAME",
  "neighbor_description": "$SYSDESCR",
  "neighbor_mgmt_ip": "$MGMT_IP_NEIGHBOR",
  "neighbor_port_id": "$PORT_ID",
  "neighbor_port_descr": "$PORT_DESCR",
  "discovery_method": "lldp"
}
ESDOC
)
            
            RESPONSE=$(curl -s -X POST "$ES_HOST/$INDEX_NAME/_doc" \
                -H "Authorization: ApiKey $ES_API_KEY" \
                -H 'Content-Type: application/json' \
                -d "$ES_DOC" 2>&1)
            
            if echo "$RESPONSE" | grep -q '"result":"created"'; then
                TOTAL_DOCS=$((TOTAL_DOCS + 1))
            fi
        fi
    done
    
    echo "$TOTAL_DOCS"
}

# Main loop
trap 'echo ""; log "Stopping..."; exit 0' INT TERM

ITERATION=0
START_TIME=$(date +%s)
TOTAL=0

while true; do
    ITERATION=$((ITERATION + 1))
    DOCS=$(collect_lldp)
    TOTAL=$((TOTAL + DOCS))
    
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ $ELAPSED -gt 0 ]; then
        RATE=$((TOTAL * 3600 / ELAPSED))
        AVG=$((TOTAL / ITERATION))
        log_success "Iteration $ITERATION | Docs: $DOCS | Total: $TOTAL | Avg: $AVG/cycle | Rate: ~$RATE/hour"
    else
        log_success "Iteration $ITERATION | Docs: $DOCS"
    fi
    
    sleep $INTERVAL
done
