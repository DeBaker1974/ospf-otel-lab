#!/bin/bash

# Load environment
ENV_FILE="$HOME/ospf-otel-lab/.env"
source "$ENV_FILE"

# Convert Elasticsearch endpoint to Kibana endpoint
KIBANA_ENDPOINT="${ES_ENDPOINT//.es./.kb.}"
KIBANA_ENDPOINT="${KIBANA_ENDPOINT%:443}"
KIBANA_ENDPOINT="${KIBANA_ENDPOINT}:443"

echo "Uploading dashboards to Kibana..."
echo "Kibana endpoint: $KIBANA_ENDPOINT"
echo ""

for dashboard in configs/kibana/dashboards/*.ndjson; do
    echo "Uploading: $(basename $dashboard)"
    
    curl -X POST "$KIBANA_ENDPOINT/api/saved_objects/_import?overwrite=true" \
        -H "Authorization: ApiKey $ES_API_KEY" \
        -H "kbn-xsrf: true" \
        --form file=@"$dashboard" \
        2>/dev/null | jq '.'
    
    echo ""
done

echo "✓ Dashboards uploaded"
echo ""
echo "Access in Kibana → Analytics → Dashboard"
