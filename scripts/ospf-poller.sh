#!/bin/bash
# OSPF Poller - Collects OSPF data via vtysh and sends to Logstash HTTP input
# FRR 10.5.0 image lacks ospfd_snmp.so, so we poll via vtysh JSON instead
# Usage: ./ospf-poller.sh        (run once)
#        ./ospf-poller.sh loop    (run forever every 15s)

LOGSTASH_URL="http://172.20.20.31:5044"
ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

poll_ospf() {
  for router in $ROUTERS; do
    # Get OSPF overview
    ospf_json=$(docker exec clab-ospf-network-$router vtysh -c "show ip ospf json" 2>/dev/null)

    if [ -z "$ospf_json" ] || ! echo "$ospf_json" | jq -e . >/dev/null 2>&1; then
      continue
    fi

    router_id=$(echo "$ospf_json" | jq -r '.routerId // empty' 2>/dev/null)
    extern_lsa=$(echo "$ospf_json" | jq -r '.lsaExternalCounter // 0' 2>/dev/null)

    # Get OSPF neighbors
    nbr_json=$(docker exec clab-ospf-network-$router vtysh -c "show ip ospf neighbor json" 2>/dev/null)

    if [ -z "$nbr_json" ] || ! echo "$nbr_json" | jq -e . >/dev/null 2>&1; then
      # Send router-level data even without neighbors
      curl -s -X POST "$LOGSTASH_URL" \
        -H "Content-Type: application/json" \
        -d "{
          \"host\":{\"name\":\"$router\",\"hostname\":\"$router\"},
          \"ospf.router.id\":\"$router_id\",
          \"ospf.admin.status\":1,
          \"ospf.lsa.external.count\":$extern_lsa,
          \"ospf.neighbor.count\":0
        }" >/dev/null 2>&1
      continue
    fi

    # Count total neighbors for this router
    total_nbrs=$(echo "$nbr_json" | jq '[.. | objects | select(has("state")) ] | length' 2>/dev/null || echo "0")

    # Parse each neighbor and send individually
    echo "$nbr_json" | jq -c --arg router "$router" --arg rid "$router_id" --arg lsa "$extern_lsa" --arg total "$total_nbrs" '
      . as $root | to_entries[] | select(.key != "default" and .key != "") |
      .value | to_entries[] |
      .key as $nbr_ip | .value[] |
      {
        "host": {"name": $router, "hostname": $router},
        "ospf.router.id": $rid,
        "ospf.admin.status": 1,
        "ospf.lsa.external.count": ($lsa | tonumber),
        "ospf.neighbor.count": ($total | tonumber),
        "ospf.neighbor.ip": $nbr_ip,
        "ospf.neighbor.router_id": (.nbrRouterId // $nbr_ip),
        "ospf.neighbor.state": (.state // "unknown"),
        "ospf.neighbor.state_code": (if .state == "Full" then 8 elif .state == "2-Way" then 4 elif .state == "Init" then 3 elif .state == "Down" then 1 else 0 end),
        "ospf.neighbor.is_full": (.state == "Full"),
        "ospf.neighbor.dead_timer_ms": (.deadTimeMsecs // 0),
        "ospf.neighbor.retrans_q": (.retransmitCounter // 0),
        "ospf.neighbor.events": (.stateChangeCounter // 0),
        "ospf.interface.name": (.ifaceName // "unknown")
      }
    ' 2>/dev/null | while IFS= read -r doc; do
      curl -s -X POST "$LOGSTASH_URL" \
        -H "Content-Type: application/json" \
        -d "$doc" >/dev/null 2>&1
    done
  done
}

# Main
if [ "$1" = "loop" ]; then
  echo "$(date): OSPF Poller started (loop mode, every 15s)"
  echo "Sending to: $LOGSTASH_URL"
  while true; do
    poll_ospf
    sleep 15
  done
else
  poll_ospf
  echo "OSPF poll complete"
fi
