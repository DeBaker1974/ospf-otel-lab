#!/bin/bash

# This script collects LLDP neighbor data from all routers
# and outputs in a format compatible with OTEL metrics

ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

for router in $ROUTERS; do
    docker exec clab-ospf-network-${router} lldpctl -f json 2>/dev/null | \
    jq --arg host "$router" '
        .lldp.interface[] |
        to_entries[] |
        {
            host: $host,
            local_interface: .key,
            neighbor_name: (.value.chassis | keys[0]),
            neighbor_ip: (.value.chassis | to_entries[0].value."mgmt-ip"[0] // "unknown"),
            neighbor_port: .value.port.descr,
            timestamp: (now | todateiso8601)
        }
    '
done | jq -s '.'
