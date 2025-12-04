#!/bin/bash

echo "Adding NetFlow startup to topology..."

# Backup original
cp clab-configs/ospf-network.clab.yml clab-configs/ospf-network.clab.yml.backup

# Add startup exec to each router
python3 <<'PYTHON'
import yaml

with open('clab-configs/ospf-network.clab.yml', 'r') as f:
    topo = yaml.safe_load(f)

# Add exec commands to all FRR routers
for node_name, node_config in topo['topology']['nodes'].items():
    if node_config.get('kind') == 'linux' and 'frr' in node_config.get('image', ''):
        if 'exec' not in node_config:
            node_config['exec'] = []
        
        # Add NetFlow startup command
        netflow_cmd = 'sleep 10 && /etc/netflow/start-netflow.sh &'
        if netflow_cmd not in node_config['exec']:
            node_config['exec'].append(netflow_cmd)
        
        # Mount the startup script
        if 'binds' not in node_config:
            node_config['binds'] = []
        
        bind = './configs/start-netflow.sh:/etc/netflow/start-netflow.sh:ro'
        if bind not in node_config['binds']:
            node_config['binds'].append(bind)

with open('clab-configs/ospf-network.clab.yml', 'w') as f:
    yaml.dump(topo, f, default_flow_style=False, sort_keys=False)

print("✓ Topology updated")
PYTHON

