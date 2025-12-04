#!/bin/bash

echo "========================================="
echo "Elasticsearch & Fleet Configuration"
echo "  Supports: Serverless & Traditional"
echo "========================================="
echo ""

ENV_FILE="$HOME/ospf-otel-lab/.env"

# Function to check if an Elastic Agent version exists
check_agent_version_exists() {
    local version=$1
    local url="https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${version}-linux-x86_64.tar.gz"
    
    # Use HEAD request to check if the file exists
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I "$url" 2>/dev/null)
    
    if [ "$HTTP_CODE" = "200" ]; then
        return 0  # Version exists
    else
        return 1  # Version doesn't exist
    fi
}

# Function to find the most recent available agent version
find_latest_available_agent_version() {
    local target_version=$1
    local major_minor=$(echo "$target_version" | cut -d. -f1-2)
    local patch=$(echo "$target_version" | cut -d. -f3)
    
    echo "  Checking for Elastic Agent version $target_version..." >&2
    
    # First, try the exact version
    if check_agent_version_exists "$target_version"; then
        echo "  ✓ Version $target_version is available" >&2
        echo "$target_version"
        return 0
    fi
    
    echo "  ✗ Version $target_version not found" >&2
    echo "  Searching for most recent available version..." >&2
    
    # Try previous patch versions (go back up to 10 versions)
    for i in $(seq $((patch - 1)) -1 0); do
        test_version="${major_minor}.${i}"
        echo "  Trying version $test_version..." >&2
        
        if check_agent_version_exists "$test_version"; then
            echo "  ✓ Found available version: $test_version" >&2
            echo "$test_version"
            return 0
        fi
    done
    
    # If we're in 9.x, try common stable versions
    if [[ "$major_minor" == "9."* ]]; then
        echo "  Trying known stable 9.x versions..." >&2
        for stable_ver in "9.2.1" "9.2.0" "9.1.1" "9.1.0" "9.0.0"; do
            echo "  Trying stable version $stable_ver..." >&2
            if check_agent_version_exists "$stable_ver"; then
                echo "  ✓ Found stable version: $stable_ver" >&2
                echo "$stable_ver"
                return 0
            fi
        done
    fi
    
    # If we're in 8.x, try common stable versions
    if [[ "$major_minor" == "8."* ]]; then
        echo "  Trying known stable 8.x versions..." >&2
        for stable_ver in "8.15.3" "8.15.2" "8.15.1" "8.15.0" "8.14.3" "8.14.2" "8.14.1" "8.14.0" "8.13.4"; do
            echo "  Trying stable version $stable_ver..." >&2
            if check_agent_version_exists "$stable_ver"; then
                echo "  ✓ Found stable version: $stable_ver" >&2
                echo "$stable_ver"
                return 0
            fi
        done
    fi
    
    # Last resort: return a known stable version based on major version
    if [[ "$major_minor" == "9."* ]]; then
        echo "  ⚠ Could not find compatible 9.x version, using fallback" >&2
        echo "9.2.1"
    else
        echo "  ⚠ Could not find compatible version, using fallback" >&2
        echo "8.15.3"
    fi
    return 1
}

# Function to test Elasticsearch connection (Serverless compatible)
test_elasticsearch() {
    local endpoint=$1
    local api_key=$2
    
    echo "Testing connection to Elasticsearch..."
    
    # Test basic endpoint (works for both serverless and traditional)
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: ApiKey $api_key" \
        "$endpoint/" 2>/dev/null)
    
    if [ "$RESPONSE" = "200" ]; then
        echo "✓ Connection successful!"
        
        # Get cluster/deployment info
        CLUSTER_INFO=$(curl -s -H "Authorization: ApiKey $api_key" "$endpoint/" 2>/dev/null)
        VERSION=$(echo "$CLUSTER_INFO" | jq -r '.version.number // "unknown"')
        CLUSTER_NAME=$(echo "$CLUSTER_INFO" | jq -r '.cluster_name // .name // "unknown"')
        BUILD_FLAVOR=$(echo "$CLUSTER_INFO" | jq -r '.version.build_flavor // "unknown"')
        
        echo ""
        echo "Deployment Information:"
        echo "  Name/Cluster: $CLUSTER_NAME"
        echo "  Version:      $VERSION"
        echo "  Build Flavor: $BUILD_FLAVOR"
        
        # Detect if serverless
        if [[ "$BUILD_FLAVOR" == "serverless" ]] || [[ "$CLUSTER_NAME" =~ serverless ]]; then
            echo "  Type:         Serverless"
            echo ""
            echo "✓ Serverless deployment detected"
        else
            echo "  Type:         Traditional/Stateful"
        fi
        
        # Test write permission by creating a test index
        echo ""
        echo "Testing write permissions..."
        TEST_DOC='{"test":"connection","timestamp":"'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'"}'
        WRITE_RESPONSE=$(curl -s -X POST "$endpoint/test-ospf-otel/_doc" \
            -H "Authorization: ApiKey $api_key" \
            -H "Content-Type: application/json" \
            -d "$TEST_DOC" 2>/dev/null)
        
        if echo "$WRITE_RESPONSE" | grep -q '"result":"created"'; then
            echo "✓ Write permission confirmed"
            
            # Clean up test index
            curl -s -X DELETE "$endpoint/test-ospf-otel" \
                -H "Authorization: ApiKey $api_key" >/dev/null 2>&1
        else
            echo "⚠ Write test inconclusive (may still work)"
        fi
        
        # Return version for agent compatibility
        echo "$VERSION"
        return 0
    else
        echo "✗ Connection failed (HTTP $RESPONSE)"
        echo ""
        
        # Try to get more details
        ERROR_RESPONSE=$(curl -s \
            -H "Authorization: ApiKey $api_key" \
            "$endpoint/" 2>&1)
        
        if [ -n "$ERROR_RESPONSE" ]; then
            echo "Response details:"
            echo "$ERROR_RESPONSE" | jq '.' 2>/dev/null || echo "$ERROR_RESPONSE" | head -5
            echo ""
        fi
        
        echo "Common issues:"
        echo "  1. Endpoint URL format:"
        echo "     Serverless:   https://your-project.es.region.provider.elastic.cloud:443"
        echo "     Traditional:  https://your-deployment.elastic-cloud.com:443"
        echo ""
        echo "  2. API Key format - Should be base64 encoded string"
        echo ""
        echo "  3. API Key permissions for Serverless:"
        echo "     - Must have 'write' and 'auto_configure' on target indices"
        echo ""
        return 1
    fi
}

# Function to configure Elasticsearch credentials
configure_elasticsearch() {
    echo "========================================="
    echo "Elasticsearch Configuration"
    echo "========================================="
    echo ""
    echo "📌 SERVERLESS API Key Setup:"
    echo ""
    echo "In Kibana → Stack Management → Security → API Keys:"
    echo ""
    echo '{
  "name": "ospf-otel-serverless",
  "role_descriptors": {
    "ospf_writer": {
      "indices": [
        {
          "names": ["metrics-*", "lldp-topology", "logs-*"],
          "privileges": ["write", "create_index", "auto_configure"]
        }
      ]
    }
  }
}'
    echo ""
    echo "Copy the ENCODED (base64) API Key"
    echo ""
    echo "========================================="
    echo ""

    while true; do
        read -p "Elasticsearch Endpoint: " ES_ENDPOINT
        
        if [ -z "$ES_ENDPOINT" ]; then
            echo "✗ Endpoint cannot be empty"
            continue
        fi
        
        # Validate URL format
        if [[ ! $ES_ENDPOINT =~ ^https?:// ]]; then
            echo "✗ Endpoint must start with http:// or https://"
            continue
        fi
        
        # Check if port is included
        if [[ ! $ES_ENDPOINT =~ :[0-9]+$ ]] && [[ $ES_ENDPOINT =~ elastic.*cloud ]]; then
            echo ""
            echo "⚠ Warning: Elastic Cloud URLs typically need :443"
            read -p "Add :443 to endpoint? (Y/n): " add_port
            if [[ ! $add_port =~ ^[Nn]$ ]]; then
                ES_ENDPOINT="${ES_ENDPOINT}:443"
                echo "  Updated to: $ES_ENDPOINT"
            fi
        fi
        
        break
    done

    echo ""

    while true; do
        read -sp "API Key (base64 encoded): " ES_API_KEY
        echo ""
        
        if [ -z "$ES_API_KEY" ]; then
            echo "✗ API Key cannot be empty"
            continue
        fi
        
        break
    done

    echo ""
    echo "Testing connection..."
    echo ""

    DETECTED_VERSION=$(test_elasticsearch "$ES_ENDPOINT" "$ES_API_KEY" | tail -1)

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Elasticsearch connection validated"
        
        # Determine agent version based on ES version
        echo ""
        echo "Determining compatible Elastic Agent version..."
        
        if [[ "$DETECTED_VERSION" =~ ^9\. ]]; then
            # ES 9.x detected - use matching 9.x agent
            TARGET_VERSION="$DETECTED_VERSION"
            echo "✓ Detected ES version $DETECTED_VERSION"
            echo "  Targeting Elastic Agent version: $TARGET_VERSION"
            AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
            
        elif [[ "$DETECTED_VERSION" =~ ^8\. ]]; then
            # ES 8.x detected, try to use same version
            TARGET_VERSION="$DETECTED_VERSION"
            echo "✓ Detected ES version $DETECTED_VERSION"
            echo "  Targeting Elastic Agent version: $TARGET_VERSION"
            AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
            
        else
            # Unknown version, use stable default
            TARGET_VERSION="8.15.3"
            echo "⚠ Unknown ES version: $DETECTED_VERSION"
            echo "  Using default stable Elastic Agent version: $TARGET_VERSION"
            AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
        fi
        
        echo ""
        echo "========================================="
        echo "✓ Selected Elastic Agent version: $AGENT_VERSION"
        echo "========================================="
        
        return 0
    else
        echo ""
        echo "✗ Elasticsearch connection failed"
        return 1
    fi
}

# Function to configure Fleet credentials
configure_fleet() {
    echo ""
    echo "========================================="
    echo "Fleet Configuration"
    echo "========================================="
    echo ""
    echo "Fleet allows you to centrally manage Elastic Agents."
    echo ""
    echo "📌 Fleet Server Setup:"
    echo ""
    echo "1. In Kibana → Fleet → Settings → Fleet Server hosts"
    echo "   Copy the Fleet Server URL (e.g., https://xxx.fleet.elastic-cloud.com:443)"
    echo ""
    echo "2. In Kibana → Fleet → Enrollment tokens"
    echo "   Copy an existing token OR create a new one for your policy"
    echo ""
    echo "========================================="
    echo ""
    
    while true; do
        read -p "Fleet Server URL: " FLEET_URL
        
        if [ -z "$FLEET_URL" ]; then
            echo "⚠ Skipping Fleet configuration"
            FLEET_URL=""
            FLEET_ENROLLMENT_TOKEN=""
            return 1
        fi
        
        # Validate URL format
        if [[ ! $FLEET_URL =~ ^https?:// ]]; then
            echo "✗ Fleet URL must start with http:// or https://"
            continue
        fi
        
        # Check if port is included
        if [[ ! $FLEET_URL =~ :[0-9]+$ ]] && [[ $FLEET_URL =~ fleet.*elastic.*cloud ]]; then
            echo ""
            echo "⚠ Warning: Fleet Cloud URLs typically need :443"
            read -p "Add :443 to URL? (Y/n): " add_port
            if [[ ! $add_port =~ ^[Nn]$ ]]; then
                FLEET_URL="${FLEET_URL}:443"
                echo "  Updated to: $FLEET_URL"
            fi
        fi
        
        break
    done
    
    if [ -n "$FLEET_URL" ]; then
        echo ""
        while true; do
            read -sp "Fleet Enrollment Token: " FLEET_ENROLLMENT_TOKEN
            echo ""
            
            if [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
                echo "✗ Token cannot be empty"
                read -p "Skip Fleet configuration? (y/N): " skip_fleet
                if [[ $skip_fleet =~ ^[Yy]$ ]]; then
                    FLEET_URL=""
                    FLEET_ENROLLMENT_TOKEN=""
                    return 1
                fi
                continue
            fi
            
            break
        done
    fi
    
    if [ -n "$FLEET_URL" ] && [ -n "$FLEET_ENROLLMENT_TOKEN" ]; then
        echo ""
        echo "✓ Fleet configuration captured"
        echo "  URL: $FLEET_URL"
        echo "  Token: ${FLEET_ENROLLMENT_TOKEN:0:20}..."
        return 0
    else
        echo ""
        echo "⚠ Fleet configuration skipped"
        FLEET_URL=""
        FLEET_ENROLLMENT_TOKEN=""
        return 1
    fi
}

# Function to update Logstash pipeline configuration
update_logstash_pipeline() {
    local endpoint=$1
    local api_key=$2
    
    PIPELINE_FILE="$HOME/ospf-otel-lab/configs/logstash/pipeline/snmp-traps.conf"
    
    echo ""
    echo "========================================="
    echo "Updating Logstash Pipeline Configuration"
    echo "========================================="
    echo ""
    
    # Backup existing config
    if [ -f "$PIPELINE_FILE" ]; then
        BACKUP_FILE="${PIPELINE_FILE}.backup-$(date +%s)"
        cp "$PIPELINE_FILE" "$BACKUP_FILE"
        echo "  Backup created: $(basename $BACKUP_FILE)"
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname $PIPELINE_FILE)"
    
    # Create new pipeline with hardcoded values
    cat > "$PIPELINE_FILE" << 'PIPELINEEOF'
input {
  snmptrap {
    host => "0.0.0.0"
    port => 1062
    community => ["public"]
  }
}

filter {
  # Add CSR23 hostname
  if [host] == "172.20.20.23" {
    mutate { 
      add_field => { 
        "host.name" => "csr23"
        "host.ip" => "172.20.20.23"
      }
    }
  }

  # Identify trap type by OID
  if [oid] == "1.3.6.1.6.3.1.1.5.3" {
    mutate { 
      add_tag => ["interface_down"]
      add_field => { 
        "event.action" => "interface-down"
        "message" => "Interface down on %{[host.name]}"
      }
    }
  } else if [oid] == "1.3.6.1.6.3.1.1.5.4" {
    mutate { 
      add_tag => ["interface_up"]
      add_field => { 
        "event.action" => "interface-up"
        "message" => "Interface up on %{[host.name]}"
      }
    }
  }

  # Add data stream fields
  mutate {
    add_field => {
      "data_stream.type" => "logs"
      "data_stream.dataset" => "snmp.trap"
      "data_stream.namespace" => "prod"
    }
  }
}

output {
  # Console output for debugging
  stdout {
    codec => rubydebug
  }

  # Send to Elasticsearch with hardcoded credentials
  elasticsearch {
    hosts => ["ENDPOINT_PLACEHOLDER"]
    api_key => "API_KEY_PLACEHOLDER"
    data_stream => true
    data_stream_type => "logs"
    data_stream_dataset => "snmp.trap"
    data_stream_namespace => "prod"
  }
}
PIPELINEEOF

    # Replace placeholders with actual values
    sed -i "s|ENDPOINT_PLACEHOLDER|$endpoint|g" "$PIPELINE_FILE"
    sed -i "s|API_KEY_PLACEHOLDER|$api_key|g" "$PIPELINE_FILE"
    
    echo "  ✓ Pipeline updated: $PIPELINE_FILE"
    echo "  Endpoint: $endpoint"
    echo "  API Key: ${api_key:0:20}..."
    echo ""
    
    # If Logstash container is running, offer to restart it
    if docker ps --format '{{.Names}}' | grep -q "clab-ospf-network-logstash"; then
        echo "  Logstash container is running"
        read -p "  Restart Logstash to apply changes? (Y/n): " restart_logstash
        
        if [[ ! $restart_logstash =~ ^[Nn]$ ]]; then
            echo "  Restarting Logstash..."
            docker restart clab-ospf-network-logstash >/dev/null 2>&1
            echo "  ✓ Logstash restarted"
            echo ""
            echo "  Wait 30 seconds, then check logs:"
            echo "    docker logs clab-ospf-network-logstash --tail 50"
        else
            echo ""
            echo "  ⚠ Remember to restart Logstash manually:"
            echo "    docker restart clab-ospf-network-logstash"
        fi
    else
        echo "  ⓘ Logstash not running yet"
        echo "  Pipeline will be loaded when Logstash starts"
    fi
    
    echo ""
    echo "✓ Logstash pipeline configuration complete"
}

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
    echo "Existing configuration found."
    echo ""
    
    # Source existing config
    source "$ENV_FILE"
    
    if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
        echo "Current Elasticsearch configuration:"
        echo "  Endpoint: $ES_ENDPOINT"
        echo "  API Key:  ${ES_API_KEY:0:20}..."
        
        if [ -n "$FLEET_URL" ]; then
            echo ""
            echo "Current Fleet configuration:"
            echo "  Fleet URL: $FLEET_URL"
            echo "  Fleet Token: ${FLEET_ENROLLMENT_TOKEN:0:20}..."
        fi
        
        if [ -n "$AGENT_VERSION" ]; then
            echo ""
            echo "Current Agent version: $AGENT_VERSION"
        fi
        echo ""
        
        # Test existing Elasticsearch connection
        DETECTED_VERSION=$(test_elasticsearch "$ES_ENDPOINT" "$ES_API_KEY" | tail -1)
        ES_TEST_RESULT=$?
        
        if [ $ES_TEST_RESULT -eq 0 ]; then
            echo ""
            echo "✓ Elasticsearch connection is valid"
            
            # Ask if user wants to update Elasticsearch credentials
            read -p "Update Elasticsearch credentials? (y/N): " update_es
            
            if [[ $update_es =~ ^[Yy]$ ]]; then
                echo ""
                if configure_elasticsearch; then
                    ES_UPDATED=true
                else
                    echo "Failed to update Elasticsearch credentials. Keeping existing."
                    ES_UPDATED=false
                fi
            else
                echo "Keeping existing Elasticsearch configuration."
                ES_UPDATED=false
                
                # Determine agent version from existing ES version
                echo ""
                echo "Determining compatible Elastic Agent version..."
                
                if [[ "$DETECTED_VERSION" =~ ^9\. ]]; then
                    TARGET_VERSION="$DETECTED_VERSION"
                    echo "✓ Detected ES version $DETECTED_VERSION"
                    echo "  Targeting Elastic Agent version: $TARGET_VERSION"
                    AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
                elif [[ "$DETECTED_VERSION" =~ ^8\. ]]; then
                    TARGET_VERSION="$DETECTED_VERSION"
                    echo "✓ Detected ES version $DETECTED_VERSION"
                    echo "  Targeting Elastic Agent version: $TARGET_VERSION"
                    AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
                else
                    TARGET_VERSION="8.15.3"
                    echo "⚠ Unknown ES version: $DETECTED_VERSION"
                    echo "  Using default stable Elastic Agent version: $TARGET_VERSION"
                    AGENT_VERSION=$(find_latest_available_agent_version "$TARGET_VERSION")
                fi
                
                echo ""
                echo "========================================="
                echo "✓ Selected Elastic Agent version: $AGENT_VERSION"
                echo "========================================="
            fi
            
            # Now ask about Fleet credentials
            echo ""
            read -p "Update Fleet credentials? (y/N): " update_fleet
            
            if [[ $update_fleet =~ ^[Yy]$ ]]; then
                if configure_fleet; then
                    FLEET_UPDATED=true
                else
                    echo "Fleet configuration skipped or failed."
                    FLEET_UPDATED=false
                fi
            else
                echo "Keeping existing Fleet configuration."
                FLEET_UPDATED=false
            fi
            
        else
            echo ""
            echo "⚠ Existing Elasticsearch configuration is invalid. Please reconfigure."
            echo ""
            
            if configure_elasticsearch; then
                ES_UPDATED=true
                
                # Ask about Fleet after ES is configured
                echo ""
                read -p "Configure Fleet credentials? (y/N): " config_fleet
                
                if [[ $config_fleet =~ ^[Yy]$ ]]; then
                    if configure_fleet; then
                        FLEET_UPDATED=true
                    else
                        FLEET_UPDATED=false
                    fi
                else
                    FLEET_UPDATED=false
                fi
            else
                echo ""
                echo "========================================="
                echo "✗ Configuration NOT saved"
                echo "========================================="
                exit 1
            fi
        fi
    else
        echo "Incomplete configuration found. Please reconfigure."
        echo ""
        
        if configure_elasticsearch; then
            ES_UPDATED=true
            
            # Ask about Fleet
            echo ""
            read -p "Configure Fleet credentials? (y/N): " config_fleet
            
            if [[ $config_fleet =~ ^[Yy]$ ]]; then
                if configure_fleet; then
                    FLEET_UPDATED=true
                else
                    FLEET_UPDATED=false
                fi
            else
                FLEET_UPDATED=false
            fi
        else
            echo ""
            echo "========================================="
            echo "✗ Configuration NOT saved"
            echo "========================================="
            exit 1
        fi
    fi
    
else
    # No existing config - fresh setup
    echo "No existing configuration found."
    echo ""
    
    if configure_elasticsearch; then
        ES_UPDATED=true
        
        # Ask about Fleet
        echo ""
        read -p "Configure Fleet for Elastic Agent deployment? (y/N): " config_fleet
        
        if [[ $config_fleet =~ ^[Yy]$ ]]; then
            if configure_fleet; then
                FLEET_UPDATED=true
            else
                FLEET_UPDATED=false
            fi
        else
            echo ""
            echo "⚠ Fleet configuration skipped"
            FLEET_URL=""
            FLEET_ENROLLMENT_TOKEN=""
            FLEET_UPDATED=false
        fi
    else
        echo ""
        echo "========================================="
        echo "✗ Configuration NOT saved"
        echo "========================================="
        exit 1
    fi
fi

# Save to .env file
echo ""
echo "Saving configuration..."

cat > "$ENV_FILE" << ENVEOF
# Elasticsearch Configuration
# Generated: $(date)
# Compatible with Serverless and Traditional deployments
ES_ENDPOINT=$ES_ENDPOINT
ES_API_KEY=$ES_API_KEY

# Elastic Stack Version (detected)
ES_VERSION=$DETECTED_VERSION
AGENT_VERSION=$AGENT_VERSION
ENVEOF

# Add Fleet configuration if provided
if [ -n "$FLEET_URL" ] && [ -n "$FLEET_ENROLLMENT_TOKEN" ]; then
    cat >> "$ENV_FILE" << ENVEOF

# Fleet Configuration (Optional)
# For centralized Elastic Agent management
FLEET_URL=$FLEET_URL
FLEET_ENROLLMENT_TOKEN=$FLEET_ENROLLMENT_TOKEN
ENVEOF
fi

chmod 600 "$ENV_FILE"

echo ""
echo "========================================="
echo "✓ Configuration saved to .env"
echo "========================================="
echo ""
echo "Configuration details:"
echo "  File:            $ENV_FILE"
echo "  Endpoint:        $ES_ENDPOINT"
echo "  API Key:         ${ES_API_KEY:0:20}... (${#ES_API_KEY} chars)"
echo "  ES Version:      $DETECTED_VERSION"
echo "  Agent Version:   $AGENT_VERSION"

if [ -n "$FLEET_URL" ]; then
    echo "  Fleet URL:       $FLEET_URL"
    echo "  Fleet Token:     ${FLEET_ENROLLMENT_TOKEN:0:20}..."
    echo ""
    echo "✓ Fleet is configured and ready for agent deployment"
else
    echo ""
    echo "⚠ Fleet not configured"
    echo "  To add Fleet later, run this script again and update Fleet credentials"
fi

echo ""
echo "Next steps:"
echo "  1. Deploy lab:   ./scripts/complete-setup-v22.sh"

if [ -n "$FLEET_URL" ]; then
    echo "  2. Elastic Agent will be deployed automatically during setup"
    echo "  3. Monitor agents in Kibana → Fleet → Agents"
else
    echo "  2. Deploy agent manually (optional): ./scripts/deploy-elastic-agent-sw2-stable.sh"
fi

echo ""

# Update Logstash pipeline configuration
update_logstash_pipeline "$ES_ENDPOINT" "$ES_API_KEY"

echo ""

# Update topology file with new credentials
if [ -f "$HOME/ospf-otel-lab/scripts/update-topology-from-env.sh" ]; then
    echo ""
    echo "Updating topology file..."
    bash "$HOME/ospf-otel-lab/scripts/update-topology-from-env.sh"
fi

