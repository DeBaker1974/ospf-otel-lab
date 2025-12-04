#!/bin/bash

echo "========================================="
echo "All Collected Metrics"
echo "========================================="
echo ""

# Load environment
ENV_FILE="$HOME/ospf-otel-lab/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "✗ .env file not found"
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

source "$ENV_FILE"

# Get unique metric names
echo "Fetching unique metric types from Elasticsearch..."
echo ""

METRICS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_search?size=0" -H 'Content-Type: application/json' -d '{
  "aggs": {
    "metric_types": {
      "terms": {"field": "metric.name.keyword", "size": 100}
    }
  }
}' 2>/dev/null | jq -r '.aggregations.metric_types.buckets[] | "\(.key) (\(.doc_count) docs)"')

if [ -z "$METRICS" ]; then
    echo "✗ No metrics found in Elasticsearch"
    echo ""
    echo "Run diagnostics:"
    echo "  ./scripts/emergency-diagnostic.sh"
    exit 1
fi

echo "   Metrics Found:"
echo ""
echo "$METRICS" | sort

# Count total
TOTAL=$(echo "$METRICS" | wc -l)
echo ""
echo "========================================="
echo "Total unique metrics: $TOTAL"
echo "========================================="
echo ""

# Show metrics by category
echo "Metrics by category:"
echo ""

echo "System Metrics:"
echo "$METRICS" | grep "^system\." | sed 's/^/  /'

echo ""
echo "Network Interface Metrics:"
echo "$METRICS" | grep "^network.interface" | sed 's/^/  /'

echo ""
echo "Network Protocol Metrics:"
echo "$METRICS" | grep "^network\." | grep -v "interface" | sed 's/^/  /'

echo ""
echo "Memory Metrics:"
echo "$METRICS" | grep -E "^(mem\.|memory\.)" | sed 's/^/  /'

# Show collection rate
echo ""
echo "  Collection Rate (FAST MODE):"
RECENT_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" -H 'Content-Type: application/json' -d '{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-1m"
      }
    }
  }
}' 2>/dev/null | jq -r '.count')

echo "  Last minute: ${RECENT_COUNT:-0} documents"
if [ "${RECENT_COUNT:-0}" -gt 0 ]; then
    echo "  Hourly rate: ~$((RECENT_COUNT * 60)) docs/hour"
    echo "  Per router: ~$((RECENT_COUNT * 60 / 7)) docs/hour/router"
fi

echo ""
