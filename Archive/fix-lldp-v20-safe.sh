#!/bin/bash

# Script to revert OTEL LLDP configuration to working v20.0 style
# This fixes the "metric OID attribute value is blank" errors

set -e

cd ~/ospf-otel-lab
CONFIG_FILE="configs/otel/otel-collector.yml"
BACKUP_FILE="${CONFIG_FILE}.backup-v21-broken-$(date +%s)"

echo "=========================================="
echo "OTEL LLDP Configuration Fixer v2.0"
echo "Reverting to v20.0 LLDP style"
echo "=========================================="
echo ""

# Check if file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Backup the current configuration
echo "📦 Creating backup: $BACKUP_FILE"
cp "$CONFIG_FILE" "$BACKUP_FILE"

# Create Python script in a temporary file to avoid heredoc issues
cat > /tmp/fix_lldp.py << 'ENDPYTHON'
import re
import sys

config_file = "configs/otel/otel-collector.yml"

print(f"Reading configuration from: {config_file}")

with open(config_file, 'r') as f:
    content = f.read()

# Define all routers and their IPs
all_routers = {
    '23': '172.20.20.23',
    '24': '172.20.20.24',
    '25': '172.20.20.25',
    '26': '172.20.20.26',
    '27': '172.20.20.27',
    '28': '172.20.20.28',
    '29': '172.20.20.29',
}

def create_v20_lldp_receiver(router_num, endpoint):
    """Create a v20.0-style LLDP receiver"""
    template = '''  snmp/csr{router}_lldp:
    endpoint: {ep}
    version: v2c
    community: public
    collection_interval: 30s
    timeout: 10s
    resource_attributes:
      host.name: {{{{ scalar_oid: "1.3.6.1.2.1.1.5.0" }}}}
    attributes:
      network.lldp.rem.sysname: {{{{ oid: "1.0.8802.1.1.2.1.4.1.1.9" }}}}
    metrics:
      network.lldp.neighbors:
        unit: "1"
        gauge: {{{{ value_type: int }}}}
        column_oids:
          - oid: "1.0.8802.1.1.2.1.4.1.1.4"
            attributes: [ {{{{ name: network.lldp.rem.sysname }}}} ]
            resource_attributes: ["host.name"]
'''
    return template.format(router=router_num, ep=endpoint)

# Find and remove all existing LLDP receivers
lldp_sections = []
for router_num in all_routers.keys():
    pattern = rf'  snmp/csr{router_num}_lldp:.*?(?=\n  snmp/|\nprocessors:)'
    matches = list(re.finditer(pattern, content, re.DOTALL))
    if matches:
        print(f"Found existing LLDP receiver for csr{router_num}")
        lldp_sections.extend(matches)

# Sort sections by position (reverse order to remove from end first)
lldp_sections.sort(key=lambda x: x.start(), reverse=True)

# Remove all LLDP sections
for match in lldp_sections:
    content = content[:match.start()] + content[match.end():]

print(f"\nRemoved {len(lldp_sections)} existing LLDP receivers")

# Find insertion point (after last combined receiver, before processors)
# Look for the last snmp receiver before processors
last_receiver_pattern = r'(  snmp/csr\d+_\w+:.*?)(\nprocessors:)'
match = list(re.finditer(last_receiver_pattern, content, re.DOTALL))[-1]
insert_pos = match.end(1)

# Generate new LLDP receivers for all routers
print(f"\nAdding LLDP receivers for all {len(all_routers)} routers...")
new_receivers = '\n'
for router_num in sorted(all_routers.keys()):
    endpoint = f"udp://{all_routers[router_num]}:161"
    new_receivers += '\n' + create_v20_lldp_receiver(router_num, endpoint)

# Insert new receivers
content = content[:insert_pos] + new_receivers + content[insert_pos:]

# Update the LLDP pipeline to include all routers
pipeline_pattern = r'(    metrics/lldp:\s+receivers:)(.*?)(      processors:)'

def update_lldp_pipeline(match):
    """Update the LLDP pipeline receivers list"""
    prefix = match.group(1)
    suffix = match.group(3)
    
    new_receivers = '\n'
    for router_num in sorted(all_routers.keys()):
        new_receivers += f'        - snmp/csr{router_num}_lldp\n'
    new_receivers += '      '
    
    return prefix + new_receivers + suffix

content = re.sub(pipeline_pattern, update_lldp_pipeline, content, flags=re.DOTALL)
print(f"Updated LLDP pipeline with all {len(all_routers)} routers")

# Simplify transform/normalize processor
transform_pattern = r'(  transform/normalize:\s+error_mode: ignore\s+metric_statements:\s+- context: datapoint\s+statements:)(.*?)(  \n  batch:)'

def simplify_transform(match):
    """Keep only uptime transformation"""
    return match.group(1) + '\n          - set(datapoint.value_double, datapoint.value_double / 100.0) where metric.name == "system.uptime"\n  \n' + match.group(3)

content = re.sub(transform_pattern, simplify_transform, content, flags=re.DOTALL)
print("Simplified transform/normalize processor")

# Write updated configuration
print(f"\nWriting updated configuration...")
with open(config_file, 'w') as f:
    f.write(content)

# Final verification
final_lldp_count = len(re.findall(r'snmp/csr\d+_lldp:', content))
print(f"\nSuccess! Total LLDP receivers: {final_lldp_count}")
print("All receivers now use v20.0 format with 'network.lldp.rem.sysname' attribute")

ENDPYTHON

# Run the Python script
echo "🔧 Running configuration updater..."
python3 /tmp/fix_lldp.py

# Clean up
rm /tmp/fix_lldp.py

echo ""
echo "=========================================="
echo "Configuration Update Complete"
echo "=========================================="
echo ""
echo "✅ Changes made:"
echo "   - Reverted ALL LLDP receivers to v20.0 format"
echo "   - Using correct attribute: network.lldp.rem.sysname"
echo "   - Removed problematic attributes (local_port, chassis_id, etc.)"
echo "   - Added LLDP monitoring for ALL 7 routers"
echo ""
echo "📋 View changes:"
echo "   diff $BACKUP_FILE $CONFIG_FILE | head -50"
echo ""
echo "🔄 Restart OTEL Collector:"
echo "   docker restart clab-ospf-network-otel-collector"
echo ""
echo "⏱️  Wait 2 minutes, then check for errors:"
echo "   docker logs --since 2m clab-ospf-network-otel-collector 2>&1 | grep -i lldp | grep -i error"
echo ""
echo "✅ Verify LLDP data:"
echo "   source .env"
echo "   curl -s -H \"Authorization: ApiKey \$ES_API_KEY\" \\"
echo "     \"\$ES_ENDPOINT/metrics-lldp-prod/_count\" | jq '.count'"
echo ""
echo "🔙 Rollback if needed:"
echo "   cp $BACKUP_FILE $CONFIG_FILE"
echo "   docker restart clab-ospf-network-otel-collector"
echo ""
