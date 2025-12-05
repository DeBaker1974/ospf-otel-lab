#!/bin/bash

echo "========================================="
echo "Elasticsearch & Fleet Configuration"
echo "  Supports: Cloud, Serverless & On-Premise"
echo "========================================="
echo ""

ENV_FILE="$HOME/ospf-otel-lab/.env"

# Function to check if an Elastic Agent version exists
check_agent_version_exists() {
    local version=$1
    local url="https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${version}-linux-x86_64.tar.gz"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$url" 2>/dev/null)
    [ "$HTTP_CODE" = "200" ]
}

# Function to find the most recent available agent version
find_latest_available_agent_version() {
    local target_version=$1
    local major_minor=$(echo "$target_version" | cut -d. -f1-2)
    local patch=$(echo "$target_version" | cut -d. -f3)
    
    echo "  Checking for Elastic Agent version $target_version..." >&2
    
    if check_agent_version_exists "$target_version"; then
        echo "  ✓ Version $target_version is available" >&2
        echo "$target_version"
        return 0
    fi
    
    echo "  ✗ Version $target_version not found, searching..." >&2
    
    for i in $(seq $((patch - 1)) -1 0); do
        test_version="${major_minor}.${i}"
        if check_agent_version_exists "$test_version"; then
            echo "  ✓ Found: $test_version" >&2
            echo "$test_version"
            return 0
        fi
    done
    
    # Fallback versions
    if [[ "$major_minor" == "9."* ]]; then
        for v in "9.2.1" "9.2.0" "9.1.0"; do
            check_agent_version_exists "$v" && echo "$v" && return 0
        done
        echo "9.2.1"
    else
        for v in "8.15.3" "8.15.2" "8.14.3"; do
            check_agent_version_exists "$v" && echo "$v" && return 0
        done
        echo "8.15.3"
    fi
}

# Function to suggest port based on URL type
suggest_port() {
    local url=$1
    local service=$2  # "elasticsearch" or "fleet"
    
    # Already has port
    [[ $url =~ :[0-9]+$ ]] && return
    
    # Cloud URLs use 443
    if [[ $url =~ elastic.*cloud|\.es\.|\.fleet\. ]]; then
        echo "443"
        return
    fi
    
    # On-premise defaults
    if [ "$service" = "fleet" ]; then
        echo "8220"
    else
        echo "9200"
    fi
}

# Function to test Elasticsearch connection
test_elasticsearch() {
    local endpoint=$1
    local api_key=$2
    local username=$3
    local password=$4
    
    echo "Testing connection to Elasticsearch..."
    
    # Build curl command based on auth type
    local curl_opts="-s -k"
    if [ -n "$api_key" ]; then
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" -H "Authorization: ApiKey $api_key" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts -H "Authorization: ApiKey $api_key" "$endpoint/" 2>/dev/null)
    elif [ -n "$username" ]; then
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" -u "$username:$password" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts -u "$username:$password" "$endpoint/" 2>/dev/null)
    else
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts "$endpoint/" 2>/dev/null)
    fi
    
    if [ "$RESPONSE" = "200" ]; then
        echo "✓ Connection successful!"
        
        VERSION=$(echo "$CLUSTER_INFO" | jq -r '.version.number // "unknown"')
        CLUSTER_NAME=$(echo "$CLUSTER_INFO" | jq -r '.cluster_name // .name // "unknown"')
        BUILD_FLAVOR=$(echo "$CLUSTER_INFO" | jq -r '.version.build_flavor // "unknown"')
        
        echo ""
        echo "Deployment Information:"
        echo "  Name/Cluster: $CLUSTER_NAME"
        echo "  Version:      $VERSION"
        echo "  Build Flavor: $BUILD_FLAVOR"
        
        if [[ "$BUILD_FLAVOR" == "serverless" ]]; then
            echo "  Type:         Serverless"
        elif [[ "$BUILD_FLAVOR" == "default" ]]; then
            echo "  Type:         On-Premise / Self-Managed"
        else
            echo "  Type:         Elastic Cloud"
        fi
        
        # Test write permission
        echo ""
        echo "Testing write permissions..."
        TEST_DOC='{"test":"connection","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'"}'
        
        if [ -n "$api_key" ]; then
            WRITE_RESPONSE=$(curl -s -k -X POST "$endpoint/test-ospf-otel/_doc" \
                -H "Authorization: ApiKey $api_key" -H "Content-Type: application/json" -d "$TEST_DOC" 2>/dev/null)
            curl -s -k -X DELETE "$endpoint/test-ospf-otel" -H "Authorization: ApiKey $api_key" >/dev/null 2>&1
        elif [ -n "$username" ]; then
            WRITE_RESPONSE=$(curl -s -k -X POST "$endpoint/test-ospf-otel/_doc" \
                -u "$username:$password" -H "Content-Type: application/json" -d "$TEST_DOC" 2>/dev/null)
            curl -s -k -X DELETE "$endpoint/test-ospf-otel" -u "$username:$password" >/dev/null 2>&1
        fi
        
        if echo "$WRITE_RESPONSE" | grep -q '"result":"created"'; then
            echo "✓ Write permission confirmed"
        else
            echo "⚠ Write test inconclusive"
        fi
        
        echo "$VERSION"
        return 0
    else
        echo "✗ Connection failed (HTTP $RESPONSE)"
        echo ""
        echo "Common endpoints:"
        echo "  On-Premise:    http(s)://elasticsearch.local:9200"
        echo "  Elastic Cloud: https://xxx.es.region.cloud.es.io:443"
        echo "  Serverless:    https://xxx.es.region.elastic.cloud:443"
        return 1
    fi
}

# Function to configure Elasticsearch
configure_elasticsearch() {
    echo "========================================="
    echo "Elasticsearch Configuration"
    echo "========================================="
    echo ""
    echo "Supported deployments:"
    echo "  • On-Premise:    http(s)://host:9200"
    echo "  • Elastic Cloud: https://xxx.es.region.cloud.es.io:443"
    echo "  • Serverless:    https://xxx.es.region.elastic.cloud:443"
    echo ""

    while true; do
        read -p "Elasticsearch Endpoint: " ES_ENDPOINT
        
        [ -z "$ES_ENDPOINT" ] && echo "✗ Cannot be empty" && continue
        [[ ! $ES_ENDPOINT =~ ^https?:// ]] && echo "✗ Must start with http:// or https://" && continue
        
        # Suggest port if missing
        SUGGESTED_PORT=$(suggest_port "$ES_ENDPOINT" "elasticsearch")
        if [ -n "$SUGGESTED_PORT" ]; then
            echo ""
            echo "⚠ No port specified. Common ports:"
            echo "   On-Premise: 9200 | Cloud: 443"
            read -p "Add :$SUGGESTED_PORT to endpoint? (Y/n): " add_port
            [[ ! $add_port =~ ^[Nn]$ ]] && ES_ENDPOINT="${ES_ENDPOINT}:${SUGGESTED_PORT}" && echo "  Updated: $ES_ENDPOINT"
        fi
        break
    done

    echo ""
    echo "Authentication:"
    echo "  1) API Key (Cloud/Serverless/On-Prem)"
    echo "  2) Username/Password (On-Premise)"
    read -p "Select [1/2] (default: 1): " auth_method
    
    ES_USERNAME=""
    ES_PASSWORD=""
    ES_API_KEY=""
    
    if [[ "$auth_method" == "2" ]]; then
        read -p "Username: " ES_USERNAME
        read -sp "Password: " ES_PASSWORD
        echo ""
    else
        echo ""
        echo "Create API Key in Kibana → Stack Management → Security → API Keys"
        read -sp "API Key (base64 encoded): " ES_API_KEY
        echo ""
    fi

    echo ""
    DETECTED_VERSION=$(test_elasticsearch "$ES_ENDPOINT" "$ES_API_KEY" "$ES_USERNAME" "$ES_PASSWORD" | tail -1)

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Elasticsearch connection validated"
        
        echo ""
        echo "Determining Elastic Agent version..."
        if [[ "$DETECTED_VERSION" =~ ^[89]\. ]]; then
            AGENT_VERSION=$(find_latest_available_agent_version "$DETECTED_VERSION")
        else
            AGENT_VERSION=$(find_latest_available_agent_version "8.15.3")
        fi
        echo "✓ Agent version: $AGENT_VERSION"
        return 0
    else
        echo "✗ Elasticsearch connection failed"
        return 1
    fi
}

# Function to configure Fleet
configure_fleet() {
    echo ""
    echo "========================================="
    echo "Fleet Configuration"
    echo "========================================="
    echo ""
    echo "Fleet Server URLs:"
    echo "  • On-Premise:    https://fleet-server:8220"
    echo "  • Elastic Cloud: https://xxx.fleet.region.cloud.es.io:443"
    echo ""
    
    read -p "Fleet Server URL (Enter to skip): " FLEET_URL
    
    if [ -z "$FLEET_URL" ]; then
        echo "⚠ Fleet configuration skipped"
        FLEET_URL=""
        FLEET_ENROLLMENT_TOKEN=""
        return 1
    fi
    
    [[ ! $FLEET_URL =~ ^https?:// ]] && echo "✗ Must start with http:// or https://" && return 1
    
    # Suggest port if missing
    SUGGESTED_PORT=$(suggest_port "$FLEET_URL" "fleet")
    if [ -n "$SUGGESTED_PORT" ]; then
        echo ""
        echo "⚠ No port specified. Common ports:"
        echo "   On-Premise: 8220 | Cloud: 443"
        read -p "Add :$SUGGESTED_PORT to URL? (Y/n): " add_port
        [[ ! $add_port =~ ^[Nn]$ ]] && FLEET_URL="${FLEET_URL}:${SUGGESTED_PORT}" && echo "  Updated: $FLEET_URL"
    fi
    
    echo ""
    read -sp "Fleet Enrollment Token: " FLEET_ENROLLMENT_TOKEN
    echo ""
    
    if [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
        echo "✗ Token required"
        FLEET_URL=""
        return 1
    fi
    
    echo "✓ Fleet configured: $FLEET_URL"
    return 0
}

# Function to update Logstash pipeline
update_logstash_pipeline() {
    local endpoint=$1
    local api_key=$2
    
    PIPELINE_FILE="$HOME/ospf-otel-lab/configs/logstash/pipeline/snmp-traps.conf"
    
    echo ""
    echo "Updating Logstash pipeline..."
    
    mkdir -p "$(dirname $PIPELINE_FILE)"
    [ -f "$PIPELINE_FILE" ] && cp "$PIPELINE_FILE" "${PIPELINE_FILE}.backup-$(date +%s)"
    
    cat > "$PIPELINE_FILE" << 'PIPELINE_EOF'
input {
  snmptrap {
    host => "0.0.0.0"
    port => 1062
    community => ["public"]
  }
}

filter {
  if [host] == "172.20.20.23" {
    mutate { add_field => { "host.name" => "csr23" "host.ip" => "172.20.20.23" } }
  }
  
  if [oid] == "1.3.6.1.6.3.1.1.5.3" {
    mutate { add_tag => ["interface_down"] add_field => { "event.action" => "interface-down" } }
  } else if [oid] == "1.3.6.1.6.3.1.1.5.4" {
    mutate { add_tag => ["interface_up"] add_field => { "event.action" => "interface-up" } }
  }
  
  mutate {
    add_field => {
      "data_stream.type" => "logs"
      "data_stream.dataset" => "snmp.trap"
      "data_stream.namespace" => "prod"
    }
  }
}

output {
  stdout { codec => rubydebug }
  elasticsearch {
    hosts => ["ENDPOINT_PLACEHOLDER"]
    api_key => "API_KEY_PLACEHOLDER"
    data_stream => true
    data_stream_type => "logs"
    data_stream_dataset => "snmp.trap"
    data_stream_namespace => "prod"
  }
}
PIPELINE_EOF

    sed -i "s|ENDPOINT_PLACEHOLDER|$endpoint|g" "$PIPELINE_FILE"
    sed -i "s|API_KEY_PLACEHOLDER|$api_key|g" "$PIPELINE_FILE"
    
    echo "✓ Logstash pipeline updated"
    
    if docker ps --format '{{.Names}}' | grep -q "clab-ospf-network-logstash"; then
        read -p "Restart Logstash? (Y/n): " restart
        [[ ! $restart =~ ^[Nn]$ ]] && docker restart clab-ospf-network-logstash >/dev/null 2>&1 && echo "✓ Logstash restarted"
    fi
}

# ===========================================
# MAIN SCRIPT
# ===========================================

# Check existing config
if [ -f "$ENV_FILE" ]; then
    echo "Existing configuration found."
    source "$ENV_FILE"
    
    if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
        echo "  Endpoint: $ES_ENDPOINT"
        echo "  API Key:  ${ES_API_KEY:0:20}..."
        [ -n "$FLEET_URL" ] && echo "  Fleet:    $FLEET_URL"
        echo ""
        
        read -p "Update configuration? (y/N): " update_config
        if [[ ! $update_config =~ ^[Yy]$ ]]; then
            echo "Keeping existing configuration."
            exit 0
        fi
    fi
fi

# Configure Elasticsearch
if ! configure_elasticsearch; then
    echo "✗ Configuration failed"
    exit 1
fi

# Configure Fleet
echo ""
read -p "Configure Fleet for agent deployment? (y/N): " config_fleet
[[ $config_fleet =~ ^[Yy]$ ]] && configure_fleet

# Save configuration
echo ""
echo "Saving configuration..."

cat > "$ENV_FILE" << ENVEOF
# Elasticsearch Configuration - $(date)
ES_ENDPOINT=$ES_ENDPOINT
ES_API_KEY=$ES_API_KEY
ES_USERNAME=$ES_USERNAME
ES_PASSWORD=$ES_PASSWORD
ES_VERSION=$DETECTED_VERSION
AGENT_VERSION=$AGENT_VERSION
ENVEOF

if [ -n "$FLEET_URL" ]; then
    cat >> "$ENV_FILE" << ENVEOF

# Fleet Configuration
FLEET_URL=$FLEET_URL
FLEET_ENROLLMENT_TOKEN=$FLEET_ENROLLMENT_TOKEN
ENVEOF
fi

chmod 600 "$ENV_FILE"

echo ""
echo "========================================="
echo "✓ Configuration Saved"
echo "========================================="
echo "  Endpoint:      $ES_ENDPOINT"
echo "  ES Version:    $DETECTED_VERSION"
echo "  Agent Version: $AGENT_VERSION"
[ -n "$FLEET_URL" ] && echo "  Fleet URL:     $FLEET_URL"
echo ""

# Update Logstash
update_logstash_pipeline "$ES_ENDPOINT" "$ES_API_KEY"

# Update topology if script exists
if [ -f "$HOME/ospf-otel-lab/scripts/update-topology-from-env.sh" ]; then
    echo ""
    echo "Updating topology file..."
    bash "$HOME/ospf-otel-lab/scripts/update-topology-from-env.sh"
fi

echo ""
echo "Next: ./scripts/complete-setup.sh"
