#!/bin/bash

# LLDP Topology Collector
# Collects LLDP neighbor information from all routers
# Sends to Elasticsearch lldp-topology index

ES_ENDPOINT="${ES_ENDPOINT}"
ES_API_KEY="${ES_API_KEY}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

for router in $ROUTERS; do
    CONTAINER="clab-ospf-network-$router"
    
    # Get LLDP neighbors in JSON format
    LLDP_JSON=$(docker exec $CONTAINER lldpcli show neighbors -f json 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$LLDP_JSON" ]; then
        # Parse and send each neighbor relationship
        echo "$LLDP_JSON" | jq -c '.lldp[0].interface[]? | 
            {
                "@timestamp": "'$TIMESTAMP'",
                "event": {
                    "dataset": "lldp.topology",
                    "kind": "event",
                    "category": ["network"],
                    "type": ["info"]
                },
                "observer": {
                    "type": "router",
                    "vendor": "frrouting",
                    "product": "frr"
                },
                "local_system": "'$router'",
                "local_port": .name,
                "local_port_desc": .port.descr,
                "remote_system": .chassis.name,
                "remote_port": .port.id.value,
                "remote_port_desc": .port.descr,
                "remote_chassis_id": .chassis.id.value,
                "remote_mgmt_ip": .chassis["mgmt-ip"],
                "ttl": .port.ttl
            }' 2>/dev/null | while read -r doc; do
            
            # Send to Elasticsearch
            curl -s -X POST "$ES_ENDPOINT/lldp-topology/_doc" \
                -H "Authorization: ApiKey $ES_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$doc" > /dev/null 2>&1
        done
    fi
done

# Cleanup old documents (keep last 24 hours)
CUTOFF_DATE=$(date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%S.000Z")
curl -s -X POST "$ES_ENDPOINT/lldp-topology/_delete_by_query" \
    -H "Authorization: ApiKey $ES_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"query\": {
            \"range\": {
                \"@timestamp\": {
                    \"lt\": \"$CUTOFF_DATE\"
                }
            }
        }
    }" > /dev/null 2>&1
