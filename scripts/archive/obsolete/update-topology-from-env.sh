#!/bin/bash

LAB_DIR="$HOME/ospf-otel-lab"
ENV_FILE="$LAB_DIR/.env"
TOPOLOGY_FILE="$LAB_DIR/ospf-network.clab.yml"

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Please run configure-elasticsearch.sh first"
    exit 1
fi

# Source the .env file
source "$ENV_FILE"

# Check required variables
if [ -z "$FLEET_URL" ] || [ -z "$FLEET_ENROLLMENT_TOKEN" ] || [ -z "$AGENT_VERSION" ]; then
    echo "Error: Required variables not set in .env"
    echo "  FLEET_URL: ${FLEET_URL:-NOT SET}"
    echo "  FLEET_ENROLLMENT_TOKEN: ${FLEET_ENROLLMENT_TOKEN:+SET}"
    echo "  AGENT_VERSION: ${AGENT_VERSION:-NOT SET}"
    exit 1
fi

# Create backup of topology file
BACKUP_FILE="${TOPOLOGY_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$TOPOLOGY_FILE" "$BACKUP_FILE"
echo "Created backup: $BACKUP_FILE"

# Update the topology file using sed
echo "Updating topology file with .env values..."

# Update FLEET_URL
sed -i "s|FLEET_URL:.*|FLEET_URL: ${FLEET_URL}|g" "$TOPOLOGY_FILE"

# Update FLEET_ENROLLMENT_TOKEN
sed -i "s|FLEET_ENROLLMENT_TOKEN:.*|FLEET_ENROLLMENT_TOKEN: ${FLEET_ENROLLMENT_TOKEN}|g" "$TOPOLOGY_FILE"

# Update Elastic Agent version
sed -i "s|image: elastic/elastic-agent:.*|image: elastic/elastic-agent:${AGENT_VERSION}|g" "$TOPOLOGY_FILE"

echo ""
echo "✓ Topology file updated successfully"
echo ""
echo "Updated values:"
echo "  FLEET_URL: $FLEET_URL"
echo "  FLEET_ENROLLMENT_TOKEN: ${FLEET_ENROLLMENT_TOKEN:0:20}..."
echo "  AGENT_VERSION: $AGENT_VERSION"
echo ""
echo "You can now deploy with: sudo clab deploy -t ospf-network.clab.yml"
