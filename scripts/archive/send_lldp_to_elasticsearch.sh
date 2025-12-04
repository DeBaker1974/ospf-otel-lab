#!/bin/bash

# Load environment variables
if [ -f /home/patrick_boulanger/ospf-otel-lab/.env ]; then
    source /home/patrick_boulanger/ospf-otel-lab/.env
else
    echo "Error: .env file not found"
    exit 1
fi

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

for router in $ROUTERS; do
    echo "Collecting LLDP data from $router..."
    
    # Collect all documents for this router into a temp file
    docker exec clab-ospf-network-${router} lldpctl -f json 2>/dev/null | \
    jq --arg host "$router" --arg ts "$TIMESTAMP" -c '
        .lldp.interface[] |
        to_entries[] |
        {
            "@timestamp": $ts,
            "data_stream": {
                "type": "metrics",
                "dataset": "lldp",
                "namespace": "prod"
            },
            "host": {
                "name": $host
            },
            "network": {
                "lldp": {
                    "local": {
                        "interface": .key
                    },
                    "remote": {
                        "sysname": (.value.chassis | keys[0]),
                        "mgmt_ip": (.value.chassis | to_entries[0].value."mgmt-ip"[0] // "unknown"),
                        "port": .value.port.descr
                    }
                }
            },
            "lldp_neighbor_count": 1
        }
    ' > /tmp/lldp_${router}.json
    
    # Send each line to Elasticsearch
    while IFS= read -r line; do
        curl -s -X POST \
            -H "Authorization: ApiKey ${ES_API_KEY}" \
            -H "Content-Type: application/json" \
            "${ES_ENDPOINT}/metrics-lldp-prod/_doc" \
            -d "$line" > /dev/null
    done < /tmp/lldp_${router}.json
    
    rm -f /tmp/lldp_${router}.json
done

echo "LLDP data collection completed at $TIMESTAMP"
