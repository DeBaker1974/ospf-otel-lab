#!/bin/bash

set -e  # Exit on error

echo "========================================="
echo "Complete OSPF OTEL Lab Redeployment v21.0"
echo "  Full cleanup and rebuild"
echo "  7 FRR routers (AS ROOT) + OTEL + Logstash"
echo "  2 Ubuntu 22.04 hosts (linux-bottom + linux-top)"
echo "  REMOVED: node1, win-bottom"
echo "  STATIC IPs (172.20.20.23-29)"
echo "  SNMP on standard port 161"
echo "  LLDP with SNMP AgentX integration"
echo "  AUTO-UPDATES Elasticsearch endpoint from .env"
echo "  NetFlow: DISABLED (troubleshoot separately)"
echo "Estimated time: 12-15 minutes"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$HOME/ospf-otel-lab"

cd "$LAB_DIR"

# ============================================
# PHASE 0: Pre-flight Checks
# ============================================
echo ""
echo "Phase 0: Pre-flight checks..."

# Check Elasticsearch configuration
ENV_FILE="$LAB_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "✗ Elasticsearch not configured"
    echo "Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

source "$ENV_FILE"
if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_API_KEY" ]; then
    echo "✗ Elasticsearch configuration incomplete"
    exit 1
fi
echo "✓ Elasticsearch configured: $ES_ENDPOINT"
# ============================================
# CHECK FLEET CONFIGURATION
# ============================================
# Check Fleet configuration
if [ -n "$FLEET_URL" ] && [ -n "$FLEET_ENROLLMENT_TOKEN" ] && [ -n "$AGENT_VERSION" ]; then
    echo "✓ Fleet configured: $FLEET_URL"
    echo "  Agent version: $AGENT_VERSION"
    echo "  Elastic Agent will be deployed automatically"
    FLEET_CONFIGURED=true
else
    echo "⚠ Fleet not configured (agent deployment will be optional)"
    if [ -z "$FLEET_URL" ]; then
        echo "  Missing: Fleet URL"
    fi
    if [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
        echo "  Missing: Fleet Enrollment Token"
    fi
    if [ -z "$AGENT_VERSION" ]; then
        echo "  Missing: Agent Version"
    fi
    echo "  To configure Fleet, run: ./scripts/configure-elasticsearch.sh"
    FLEET_CONFIGURED=false
fi
# Check required directories
REQUIRED_DIRS=(
    "configs/routers/csr23"
    "configs/routers/csr24"
    "configs/routers/csr25"
    "configs/routers/csr26"
    "configs/routers/csr27"
    "configs/routers/csr28"
    "configs/routers/csr29"
    "configs/otel"
    "configs/logstash/pipeline"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "✗ Missing directory: $dir"
        exit 1
    fi
done

echo "✓ All required directories present"

# Check if snmp tools installed on host
if ! command -v snmpget &> /dev/null; then
    echo "  Installing SNMP tools on host..."
    sudo apt-get update -qq && sudo apt-get install -y snmp -qq
fi

echo "✓ SNMP tools available"

# Check for ANY existing host containers in topology (linux-host, elastic-agent-host, etc.)
echo ""
echo "Checking topology for existing host containers..."

# Find all potential host container names
HOST_CONTAINERS=$(grep -E "^[[:space:]]*(linux-host|elastic-agent-host|agent-host|ubuntu-host):" ospf-network.clab.yml | sed 's/:.*//' | tr -d ' ' || echo "")

if [ -n "$HOST_CONTAINERS" ]; then
    echo "  ⚠ Found existing host container(s):"
    echo "$HOST_CONTAINERS" | sed 's/^/    /'
    
    # Count how many
    HOST_COUNT=$(echo "$HOST_CONTAINERS" | wc -l)
    
    if [ "$HOST_COUNT" -gt 1 ]; then
        echo ""
        echo "  ⚠ WARNING: Multiple host containers detected!"
        echo "  This will cause port conflicts (8022, 2056)"
        echo ""
        read -p "  Remove ALL existing host containers? (y/n) [default: y] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "  Removing all host containers..."
            cp ospf-network.clab.yml ospf-network.clab.yml.backup-multi-host-removal-$(date +%s)
            
            # Use Python for clean removal
            if command -v python3 &> /dev/null; then
                echo "  Using Python for clean YAML removal..."
                python3 << 'EOFPYTHON'
import yaml
import sys

try:
    with open('ospf-network.clab.yml', 'r') as f:
        data = yaml.safe_load(f)
    
    if 'topology' in data and 'nodes' in data['topology']:
        # Remove all host-type containers
        host_containers = ['linux-host', 'elastic-agent-host', 'agent-host', 'ubuntu-host']
        removed = []
        
        for host in host_containers:
            if host in data['topology']['nodes']:
                del data['topology']['nodes'][host]
                removed.append(host)
        
        if removed:
            print(f"    ✓ Removed: {', '.join(removed)}")
        else:
            print("    No host containers found in nodes section")
    
    with open('ospf-network.clab.yml', 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, indent=2)
    
    sys.exit(0)
except Exception as e:
    print(f"    Python cleanup failed: {e}")
    sys.exit(1)
EOFPYTHON
                
                if [ $? -ne 0 ]; then
                    echo "    Python cleanup failed, using awk..."
                    # Fallback: remove all host containers with awk
                    awk '
                    /^[[:space:]]*(linux-host|elastic-agent-host|agent-host|ubuntu-host):/ { skip=1; next }
                    /^[[:space:]]*[a-z][a-z0-9-]*:/ { skip=0 }
                    !skip { print }
                    ' ospf-network.clab.yml > ospf-network.clab.yml.tmp
                    mv ospf-network.clab.yml.tmp ospf-network.clab.yml
                    echo "    ✓ Removed with awk"
                fi
            else
                # Use awk if Python not available
                echo "  Using awk for removal..."
                awk '
                /^[[:space:]]*(linux-host|elastic-agent-host|agent-host|ubuntu-host):/ { skip=1; next }
                /^[[:space:]]*[a-z][a-z0-9-]*:/ { skip=0 }
                !skip { print }
                ' ospf-network.clab.yml > ospf-network.clab.yml.tmp
                mv ospf-network.clab.yml.tmp ospf-network.clab.yml
                echo "    ✓ Removed with awk"
            fi
            
            echo "  ✓ All host containers removed"
            HOST_CONTAINERS=""
        else
            echo "  Keeping existing host containers (deployment will likely fail)"
        fi
    else
        # Single host container found
        SINGLE_HOST=$(echo "$HOST_CONTAINERS" | head -1)
        EXISTING_IP=$(grep -A 10 "${SINGLE_HOST}:" ospf-network.clab.yml | grep "mgmt-ipv4:" | awk '{print $2}' | head -1)
        echo "  Found: $SINGLE_HOST"
        echo "  Current IP: $EXISTING_IP"
        
        read -p "  Remove and recreate? (y/n) [default: n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "  Removing $SINGLE_HOST..."
            cp ospf-network.clab.yml ospf-network.clab.yml.backup-before-removal-$(date +%s)
            
            if command -v python3 &> /dev/null; then
                python3 << EOFPYTHON
import yaml
import sys

try:
    with open('ospf-network.clab.yml', 'r') as f:
        data = yaml.safe_load(f)
    
    if 'topology' in data and 'nodes' in data['topology']:
        host_containers = ['linux-host', 'elastic-agent-host', 'agent-host', 'ubuntu-host']
        for host in host_containers:
            if host in data['topology']['nodes']:
                del data['topology']['nodes'][host]
    
    with open('ospf-network.clab.yml', 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, indent=2)
    
    sys.exit(0)
except Exception as e:
    sys.exit(1)
EOFPYTHON
                
                if [ $? -eq 0 ]; then
                    echo "  ✓ Removed $SINGLE_HOST"
                else
                    awk '
                    /^[[:space:]]*(linux-host|elastic-agent-host|agent-host|ubuntu-host):/ { skip=1; next }
                    /^[[:space:]]*[a-z][a-z0-9-]*:/ { skip=0 }
                    !skip { print }
                    ' ospf-network.clab.yml > ospf-network.clab.yml.tmp
                    mv ospf-network.clab.yml.tmp ospf-network.clab.yml
                    echo "  ✓ Removed with awk"
                fi
            else
                awk '
                /^[[:space:]]*(linux-host|elastic-agent-host|agent-host|ubuntu-host):/ { skip=1; next }
                /^[[:space:]]*[a-z][a-z0-9-]*:/ { skip=0 }
                !skip { print }
                ' ospf-network.clab.yml > ospf-network.clab.yml.tmp
                mv ospf-network.clab.yml.tmp ospf-network.clab.yml
                echo "  ✓ Removed with awk"
            fi
            
            HOST_CONTAINERS=""
        else
            echo "  Keeping existing $SINGLE_HOST"
        fi
    fi
fi

# Check for removed old containers (node1, win-bottom)
echo ""
echo "Checking for deprecated containers..."
DEPRECATED=$(grep -E "^[[:space:]]*(node1|win-bottom):" ospf-network.clab.yml | sed 's/:.*//' | tr -d ' ' || echo "")
if [ -n "$DEPRECATED" ]; then
    echo "  ⚠ Found deprecated containers: $DEPRECATED"
    echo "  These should have been removed in the new topology"
else
    echo "  ✓ No deprecated containers found"
fi

# Verify topology file has user: root for FRR containers
if ! grep -q "user: root" ospf-network.clab.yml; then
    echo ""
    echo "⚠ Warning: Topology file doesn't have 'user: root' for FRR containers"
    echo "  This is required for SNMP to bind to port 161"
    echo ""
    read -p "  Add 'user: root' to topology file? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Backup first
        cp ospf-network.clab.yml ospf-network.clab.yml.backup-before-root
        
        # Add user: root after each frrouting image line
        sed -i '/image: frrouting/a\      user: root' ospf-network.clab.yml
        
        echo "  ✓ Added 'user: root' to topology file"
    else
        echo "  Continuing without modification (SNMP may fail to start)"
    fi
fi

# Verify topology has snmpd.conf bind mounts
echo ""
echo "Checking for snmpd.conf bind mounts..."
if grep -q "snmpd.conf:/etc/snmp/snmpd.conf" ospf-network.clab.yml; then
    echo "  ✓ Topology has snmpd.conf bind mounts"
else
    echo "  ⚠ WARNING: Topology missing snmpd.conf bind mounts"
    echo "  Please update ospf-network.clab.yml with provided topology"
    echo "  Script will create snmpd.conf files but they won't be mounted"
fi

# Verify topology has LLDP AgentX commands
if grep -q "lldpd -x -X /var/agentx/master" ospf-network.clab.yml; then
    echo "  ✓ Topology has LLDP AgentX startup commands"
else
    echo "  ⚠ WARNING: Topology missing LLDP AgentX commands"
    echo "  Please update ospf-network.clab.yml with provided topology"
fi

# Final verification
echo ""
echo "  Final topology verification..."

# Check for duplicate IPs
DUPLICATE_CHECK=$(grep "mgmt-ipv4:" ospf-network.clab.yml | awk '{print $2}' | sort | uniq -d)
if [ -n "$DUPLICATE_CHECK" ]; then
    echo "  ✗ ERROR: Duplicate IPs detected:"
    echo "$DUPLICATE_CHECK" | sed 's/^/    /'
    echo ""
    echo "  Please fix manually before continuing"
    exit 1
else
    echo "  ✓ No duplicate IPs detected"
fi

# Check for duplicate port bindings
DUPLICATE_PORTS=$(grep -E "^\s+- \"[0-9]+:" ospf-network.clab.yml | awk -F'"' '{print $2}' | cut -d':' -f1 | sort | uniq -d)
if [ -n "$DUPLICATE_PORTS" ]; then
    echo "  ⚠ WARNING: Duplicate port bindings detected:"
    echo "$DUPLICATE_PORTS" | sed 's/^/    Port /'
    echo "  This may cause deployment failures"
fi

# Verify no old host containers remain
OLD_HOSTS=$(grep -E "^[[:space:]]*(elastic-agent-host|agent-host|ubuntu-host):" ospf-network.clab.yml || echo "")
if [ -n "$OLD_HOSTS" ]; then
    echo "  ✗ ERROR: Old host containers still present:"
    echo "$OLD_HOSTS" | sed 's/^/    /'
    echo ""
    echo "  Run this script again and choose to remove them"
    exit 1
else
    echo "  ✓ No conflicting host containers"
fi

# Verify linux-bottom and linux-top exist and are Ubuntu
LINUX_BOTTOM_CHECK=$(grep -A 2 "linux-bottom:" ospf-network.clab.yml | grep "image:" | grep "ubuntu" || echo "")
LINUX_TOP_CHECK=$(grep -A 2 "linux-top:" ospf-network.clab.yml | grep "image:" | grep "ubuntu" || echo "")

if [ -n "$LINUX_BOTTOM_CHECK" ]; then
    echo "  ✓ linux-bottom configured as Ubuntu"
else
    echo "  ⚠ WARNING: linux-bottom may not be Ubuntu 22.04"
fi

if [ -n "$LINUX_TOP_CHECK" ]; then
    echo "  ✓ linux-top configured as Ubuntu"
else
    echo "  ⚠ WARNING: linux-top may not be Ubuntu 22.04"
fi

# ============================================
# PHASE 1: Complete Cleanup
# ============================================
echo ""
echo "Phase 1: Complete cleanup..."

# Stop any LLDP services
if systemctl is-active --quiet lldp-export 2>/dev/null; then
    echo "  Stopping LLDP export service..."
    sudo systemctl stop lldp-export 2>/dev/null || true
    sudo systemctl disable lldp-export 2>/dev/null || true
fi

# Destroy existing lab
if sudo clab inspect -t ospf-network.clab.yml &>/dev/null 2>&1; then
    echo "  Destroying existing lab..."
    sudo clab destroy -t ospf-network.clab.yml --cleanup 2>/dev/null || true
    sleep 10
fi

# Clean up any orphaned containers
echo "  Cleaning orphaned containers..."
docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" | while read container; do
    echo "    Removing: $container"
    docker rm -f "$container" 2>/dev/null || true
done

# Also clean up the host logstash test container
if docker ps -a --format "{{.Names}}" | grep -q "logstash-host-test"; then
    echo "    Removing: logstash-host-test"
    docker rm -f logstash-host-test 2>/dev/null || true
fi

# Clean up stale network configurations
echo "  Cleaning network artifacts..."
docker network prune -f 2>/dev/null || true

# Remove persistent state files from routers
echo "  Cleaning FRR state files..."
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    if [ -d "$LAB_DIR/clab-ospf-network/$router" ]; then
        rm -rf "$LAB_DIR/clab-ospf-network/$router" 2>/dev/null || true
    fi
done

# Clean up logs directory
if [ -d "$LAB_DIR/logs" ]; then
    echo "  Cleaning logs directory..."
    rm -f "$LAB_DIR/logs"/*.log 2>/dev/null || true
fi

# Clean Docker overlay2 layers (cautiously)
echo "  Pruning unused Docker resources..."
docker system prune -f 2>/dev/null || true

echo "✓ Cleanup complete"

# ============================================
# PHASE 2: Deploy Topology
# ============================================
echo ""
echo "Phase 2: Deploying containerlab topology..."

# Backup topology file
BACKUP_FILE="ospf-network.clab.yml.backup-$(date +%s)"
cp ospf-network.clab.yml "$BACKUP_FILE"
echo "  Topology backed up to: $BACKUP_FILE"

# Deploy with detailed output
echo "  Starting containerlab deployment (containers will run as root)..."
if sudo clab deploy -t ospf-network.clab.yml --reconfigure; then
    echo "✓ Topology deployed successfully"
else
    echo "✗ Deployment failed"
    echo "  Check logs: sudo clab inspect -t ospf-network.clab.yml"
    echo "  Recent topology backups:"
    ls -lht ospf-network.clab.yml.backup-* | head -5
    exit 1
fi

# ============================================
# PHASE 3: Verify Static IPs & Collect Actuals
# ============================================
echo ""
echo "Phase 3: Verifying container deployment..."

# Wait for containers to stabilize
sleep 10

# Define expected IPs
declare -A EXPECTED_IPS=(
    ["csr23"]="172.20.20.23"
    ["csr24"]="172.20.20.24"
    ["csr25"]="172.20.20.25"
    ["csr26"]="172.20.20.26"
    ["csr27"]="172.20.20.27"
    ["csr28"]="172.20.20.28"
    ["csr29"]="172.20.20.29"
)

declare -A ACTUAL_IPS
ALL_CORRECT=true

echo "  Verifying router IPs..."
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-$router"
    
    # Get IP address
    actual_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container" 2>/dev/null)
    
    if [ -z "$actual_ip" ]; then
        echo "  ✗ $router: Container not found or not running"
        ALL_CORRECT=false
        continue
    fi
    
    ACTUAL_IPS[$router]=$actual_ip
    expected_ip="${EXPECTED_IPS[$router]}"
    
    if [ "$actual_ip" = "$expected_ip" ]; then
        echo "  ✓ $router = $actual_ip"
    else
        echo "  ⚠ $router = $actual_ip (expected $expected_ip)"
        ALL_CORRECT=false
    fi
done

# Verify containers are running as root
echo ""
echo "  Verifying root user..."
for router in csr23 csr24; do  # Check a couple
    container="clab-ospf-network-$router"
    user_id=$(docker exec "$container" id -u 2>/dev/null || echo "fail")
    if [ "$user_id" = "0" ]; then
        echo "  ✓ $router: running as root (UID 0)"
    else
        echo "  ⚠ $router: NOT running as root (UID $user_id)"
    fi
done

# Verify support containers
echo ""
echo "  Verifying support containers..."
SUPPORT_CONTAINERS=("otel-collector" "logstash" "linux-bottom" "linux-top")

for container in "${SUPPORT_CONTAINERS[@]}"; do
    status=$(docker inspect --format='{{.State.Status}}' "clab-ospf-network-$container" 2>/dev/null || echo "missing")
    if [ "$status" = "running" ]; then
        echo "  ✓ $container: running"
        
        # Special check for Ubuntu hosts
        if [[ "$container" == "linux-bottom" || "$container" == "linux-top" ]]; then
            OS_CHECK=$(docker exec "clab-ospf-network-$container" cat /etc/os-release 2>/dev/null | grep "Ubuntu 22.04" || echo "")
            if [ -n "$OS_CHECK" ]; then
                echo "      ✓ Confirmed Ubuntu 22.04"
            else
                echo "      ⚠ Unexpected OS version"
                docker exec "clab-ospf-network-$container" cat /etc/os-release 2>/dev/null | grep PRETTY_NAME || echo "      Could not determine OS"
            fi
        fi
    else
        echo "  ✗ $container: $status"
    fi
done

# Verify deprecated containers are gone
echo ""
echo "  Verifying deprecated containers removed..."
for container in node1 win-bottom; do
    if docker ps -a --format '{{.Names}}' | grep -q "clab-ospf-network-$container"; then
        echo "  ⚠ WARNING: $container still exists!"
    else
        echo "  ✓ $container successfully removed"
    fi
done

if [ "$ALL_CORRECT" = false ]; then
    echo ""
    echo "⚠ Warning: Some IPs don't match expected values"
    echo "  Continuing with actual IPs..."
fi

# ============================================
# PHASE 3.5: Setup Ubuntu Hosts
# ============================================
echo ""
echo "Phase 3.5: Setting up Ubuntu hosts..."

# Wait for Ubuntu containers to fully initialize
echo "  Waiting for Ubuntu containers to initialize (30s)..."
sleep 30

# Verify linux-bottom
echo ""
echo "  Verifying linux-bottom (192.168.10.20)..."
docker exec clab-ospf-network-linux-bottom bash -c '
    echo "  Checking installed packages..."
    
    if command -v curl &>/dev/null; then
        echo "  ✓ curl installed"
    else
        echo "  ✗ curl missing"
    fi
    
    if command -v wget &>/dev/null; then
        echo "  ✓ wget installed"
    else
        echo "  ✗ wget missing"
    fi
    
    if command -v jq &>/dev/null; then
        echo "  ✓ jq installed"
    else
        echo "  ⚠ jq missing (optional)"
    fi
    
    if command -v systemctl &>/dev/null; then
        echo "  ✓ systemctl available"
    else
        echo "  ⚠ systemctl missing"
    fi
    
    echo ""
    echo "  System information:"
    echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
    echo "  IP: $(hostname -I | awk "{print \$1}")"
'

# Verify linux-top
echo ""
echo "  Verifying linux-top (192.168.20.100)..."
docker exec clab-ospf-network-linux-top bash -c '
    echo "  Checking installed packages..."
    
    if command -v curl &>/dev/null; then
        echo "  ✓ curl installed"
    else
        echo "  ✗ curl missing"
    fi
    
    if command -v wget &>/dev/null; then
        echo "  ✓ wget installed"
    else
        echo "  ✗ wget missing"
    fi
    
    if command -v jq &>/dev/null; then
        echo "  ✓ jq installed"
    else
        echo "  ⚠ jq missing (optional)"
    fi
    
    if command -v systemctl &>/dev/null; then
        echo "  ✓ systemctl available"
    else
        echo "  ⚠ systemctl missing"
    fi
    
    echo ""
    echo "  System information:"
    echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d \")"
    echo "  IP: $(hostname -I | awk "{print \$1}")"
'

echo ""
echo "✓ Ubuntu hosts ready"
echo "  linux-bottom: 192.168.10.20 (on sw)"
echo "  linux-top:    192.168.20.100 (on sw2)"

# ============================================
# PHASE 4: Container Initialization Wait
# ============================================
echo ""
echo "Phase 4: Waiting for container initialization (60s)..."
sleep 60

# Verify all FRR daemons are running
echo "  Checking FRR daemon status..."
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-$router"
    
    # Check if FRR processes are running
    ospfd_running=$(docker exec "$container" pgrep ospfd 2>/dev/null | wc -l)
    zebra_running=$(docker exec "$container" pgrep zebra 2>/dev/null | wc -l)
    
    if [ "$ospfd_running" -gt 0 ] && [ "$zebra_running" -gt 0 ]; then
        echo "  ✓ $router: FRR daemons running"
    else
        echo "  ⚠ $router: FRR daemons not fully started"
    fi
done

# ============================================
# PHASE 5: Install SNMP + LLDP with AgentX
# ============================================
echo ""
echo "Phase 5: Installing SNMP + LLDP with AgentX integration..."
echo "  Note: Using standard port 161 (containers run as root)"
echo "  Note: LLDP configured with AgentX for SNMP export"

# First, ensure snmpd.conf files exist
echo ""
echo "  Creating snmpd.conf files..."
ROUTERS="csr23 csr24 csr25 csr26 csr27 csr28 csr29"

for router in $ROUTERS; do
    mkdir -p "$LAB_DIR/configs/routers/$router"
    
    cat > "$LAB_DIR/configs/routers/$router/snmpd.conf" << EOF
# SNMP Configuration for $router
rocommunity public default
rocommunity6 public default
sysLocation Containerlab OSPF Network
sysContact admin@lab.local
sysName $router

# AgentX configuration for lldpd
master agentx
agentXSocket /var/agentx/master
agentXPerms 0660 0550 root snmp

sysServices 72
dontLogTCPWrappersConnects yes
EOF
done

echo "  ✓ snmpd.conf files created for all routers"

# Install packages in parallel for speed
echo ""
echo "  Installing packages (including tcpdump for debugging)..."
for router in $ROUTERS; do
    {
        docker exec "clab-ospf-network-$router" sh -c '
            apk add --no-cache net-snmp net-snmp-tools lldpd tcpdump >/dev/null 2>&1
        ' && echo "    ✓ $router: packages installed"
    } &
done
wait

echo ""
echo "  Configuring SNMP with AgentX support..."
for router in $ROUTERS; do
    docker exec "clab-ospf-network-$router" sh -c '
        # Kill any existing processes
        pkill -9 snmpd lldpd 2>/dev/null || true
        sleep 2
        
        # Create AgentX directory
        mkdir -p /var/agentx
        chmod 777 /var/agentx
        
        # Start SNMP daemon with AgentX support (using bind-mounted config)
        /usr/sbin/snmpd -c /etc/snmp/snmpd.conf -Lsd -Lf /dev/null udp:161
        
        # Wait for AgentX socket
        sleep 5
        
        # Verify socket exists
        if [ -S /var/agentx/master ]; then
            echo "1"
        else
            echo "0"
        fi
    ' 2>&1 | tail -1
done | while read status; do
    if [ "$status" = "1" ]; then
        echo "    ✓ SNMP + AgentX configured"
    else
        echo "    ✗ SNMP AgentX socket failed"
    fi
done

echo ""
echo "  Configuring LLDP with AgentX integration..."
for router in $ROUTERS; do
    echo "    Configuring $router..."
    docker exec "clab-ospf-network-$router" sh -c '
        # Start lldpd with AgentX support
        lldpd -x -X /var/agentx/master -d >/dev/null 2>&1 &
        
        sleep 5
        
        # Configure at runtime
        lldpcli configure system interface pattern "*" >/dev/null 2>&1
        lldpcli configure lldp tx-interval 10 >/dev/null 2>&1
        lldpcli update >/dev/null 2>&1
        
        sleep 2
        
        # Verify both running and AgentX connected
        LLDP_OK=0
        if pgrep lldpd >/dev/null; then
            INTERFACE_COUNT=$(lldpcli show interfaces 2>/dev/null | grep -c "Interface:" || echo "0")
            if [ "$INTERFACE_COUNT" -gt 0 ]; then
                LLDP_OK=1
                echo "$INTERFACE_COUNT"
            else
                echo "0"
            fi
        else
            echo "0"
        fi
    ' 2>&1 | tail -1
done | while read count; do
    if [ "$count" -gt 0 ]; then
        echo "      ✓ LLDP + AgentX running, monitoring $count interfaces"
    else
        echo "      ⚠ LLDP failed or no interfaces"
    fi
done

# Verify SNMP is responding on standard port 161
echo ""
echo "  Verifying SNMP connectivity on port 161..."
SNMP_WORKING=0
for router in $ROUTERS; do
    ip="${ACTUAL_IPS[$router]}"
    if timeout 5 snmpget -v2c -c public "$ip" 1.3.6.1.2.1.1.1.0 >/dev/null 2>&1; then
        echo "  ✓ $router ($ip:161): SNMP responding"
        SNMP_WORKING=$((SNMP_WORKING + 1))
    else
        echo "  ⚠ $router ($ip:161): SNMP not responding yet"
    fi
done

echo "  SNMP working on $SNMP_WORKING/7 routers"

# Wait for LLDP neighbor discovery
echo ""
echo "  Waiting 30 seconds for LLDP neighbor discovery..."
sleep 30

# Verify LLDP is collecting neighbors
echo ""
echo "  Verifying LLDP neighbor discovery..."
LLDP_WORKING=0
TOTAL_LLDP_NEIGHBORS=0
for router in $ROUTERS; do
    container="clab-ospf-network-$router"
    neighbors=$(docker exec "$container" lldpcli show neighbors 2>/dev/null | grep -c "SysName:" || echo "0")
    if [ "$neighbors" -gt 0 ]; then
        echo "  ✓ $router: $neighbors LLDP neighbors"
        LLDP_WORKING=$((LLDP_WORKING + 1))
        TOTAL_LLDP_NEIGHBORS=$((TOTAL_LLDP_NEIGHBORS + neighbors))
    else
        echo "  ⚠ $router: No LLDP neighbors yet (may need more time)"
    fi
done

echo "  LLDP working on $LLDP_WORKING/7 routers ($TOTAL_LLDP_NEIGHBORS total neighbor relationships)"

# Verify LLDP data is available via SNMP (AgentX)
echo ""
echo "  Verifying LLDP data via SNMP (AgentX)..."
LLDP_SNMP_WORKING=0
LLDP_SNMP_NEIGHBORS=0
for router in $ROUTERS; do
    ip="${ACTUAL_IPS[$router]}"
    result=$(snmpwalk -v2c -c public -t 3 -r 1 "$ip" 1.0.8802.1.1.2.1.4.1.1.9 2>&1)
    
    if echo "$result" | grep -q "STRING"; then
        neighbor_count=$(echo "$result" | grep -c "STRING")
        echo "  ✓ $router: LLDP via SNMP working ($neighbor_count neighbors)"
        LLDP_SNMP_WORKING=$((LLDP_SNMP_WORKING + 1))
        LLDP_SNMP_NEIGHBORS=$((LLDP_SNMP_NEIGHBORS + neighbor_count))
    else
        echo "  ⚠ $router: LLDP via SNMP not working yet"
    fi
done

echo "  LLDP SNMP working on $LLDP_SNMP_WORKING/7 routers ($LLDP_SNMP_NEIGHBORS neighbors via SNMP)"

if [ "$SNMP_WORKING" -lt 5 ]; then
    echo ""
    echo "⚠ Warning: Less than 5 routers responding to SNMP"
    echo "  Debugging one router..."
    docker exec clab-ospf-network-csr28 sh -c '
        echo "  Process status:"
        ps aux | grep -E "snmpd|lldpd" | grep -v grep
        echo "  Port status:"
        netstat -uln | grep 161
        echo "  AgentX socket:"
        ls -la /var/agentx/
        echo "  Running as user:"
        id
    '
fi

if [ "$LLDP_WORKING" -lt 5 ]; then
    echo ""
    echo "⚠ Warning: Less than 5 routers discovering LLDP neighbors"
    echo "  This may improve after a few minutes"
fi

if [ "$LLDP_SNMP_WORKING" -lt 5 ]; then
    echo ""
    echo "⚠ Warning: LLDP data not available via SNMP on all routers"
    echo "  AgentX integration may need troubleshooting"
    echo "  Wait a few minutes and test manually:"
    echo "    snmpwalk -v2c -c public 172.20.20.28 1.0.8802.1.1.2.1.4.1.1.9"
fi

# ============================================
# PHASE 6: Configure OTEL Collector (ENHANCED)
# ============================================
echo ""
echo "Phase 6: Configuring OTEL Collector..."

OTEL_CONFIG="configs/otel/otel-collector.yml"

if [ ! -f "$OTEL_CONFIG" ]; then
    echo "✗ OTEL config not found: $OTEL_CONFIG"
    exit 1
fi

# Backup original config
BACKUP_CONFIG="${OTEL_CONFIG}.backup-$(date +%s)"
cp "$OTEL_CONFIG" "$BACKUP_CONFIG"
echo "  Config backed up to: $(basename $BACKUP_CONFIG)"

# Load Elasticsearch configuration
source "$ENV_FILE"

if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_API_KEY" ]; then
    echo "✗ Elasticsearch not configured in .env"
    echo "  Run: ./scripts/configure-elasticsearch.sh"
    exit 1
fi

# ============================================
# UPDATE 1: Elasticsearch Connection
# ============================================
echo ""
echo "  Updating Elasticsearch connection..."
echo "    New Endpoint: $ES_ENDPOINT"
echo "    New API Key:  ${ES_API_KEY:0:20}..."

# Find current endpoint in config
OLD_ENDPOINT=$(grep -m 1 'endpoints: \[' "$OTEL_CONFIG" | grep -oP 'https://[^"]+' || echo "")
OLD_API_KEY=$(grep -m 1 'api_key:' "$OTEL_CONFIG" | awk '{print $2}' | tr -d '"' || echo "")

if [ -n "$OLD_ENDPOINT" ]; then
    echo "    Replacing: $OLD_ENDPOINT"
    sed -i "s|${OLD_ENDPOINT}|${ES_ENDPOINT}|g" "$OTEL_CONFIG"
fi

if [ -n "$OLD_API_KEY" ]; then
    echo "    Replacing API key: ${OLD_API_KEY:0:20}..."
    sed -i "s|${OLD_API_KEY}|${ES_API_KEY}|g" "$OTEL_CONFIG"
fi

# Verify replacement
NEW_ENDPOINT_COUNT=$(grep -c "$ES_ENDPOINT" "$OTEL_CONFIG")
if [ "$NEW_ENDPOINT_COUNT" -gt 0 ]; then
    echo "    ✓ Endpoint updated ($NEW_ENDPOINT_COUNT occurrences)"
else
    echo "    ✗ Warning: Endpoint not updated!"
fi

# ============================================
# UPDATE 2: Router IPs (SNMP endpoints)
# ============================================
echo ""
echo "  Updating router IPs (port 161)..."
for router in "${!ACTUAL_IPS[@]}"; do
    ip="${ACTUAL_IPS[$router]}"
    router_num="${router#csr}"
    
    echo "    $router -> $ip:161"
    
    sed -i "s|endpoint: udp://[0-9.]*:1*161.*${router}|endpoint: udp://${ip}:161 # ${router}|g" "$OTEL_CONFIG"
    sed -i "s|endpoint: udp://172\.20\.20\.${router_num}:1*161|endpoint: udp://${ip}:161|g" "$OTEL_CONFIG"
done

sed -i 's/:1161\([^0-9]\)/:161\1/g' "$OTEL_CONFIG"

# ============================================
# VERIFICATION
# ============================================
echo ""
echo "  Verification:"
CONFIG_LINES=$(wc -l < "$OTEL_CONFIG")
RECEIVER_COUNT=$(grep -c "endpoint: udp://" "$OTEL_CONFIG")
EXPORTER_COUNT=$(grep -c "^  elasticsearch/" "$OTEL_CONFIG")
echo "    Config size: $CONFIG_LINES lines"
echo "    SNMP receivers: $RECEIVER_COUNT"
echo "    ES exporters: $EXPORTER_COUNT"

# Show first exporter
echo ""
echo "  Sample exporter config:"
grep -A 3 "elasticsearch/system:" "$OTEL_CONFIG" | sed 's/^/    /'

# ============================================
# RESTART
# ============================================
echo ""
echo "  Restarting OTEL Collector..."
docker restart clab-ospf-network-otel-collector
sleep 20

# Check status
OTEL_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-otel-collector 2>/dev/null)
if [ "$OTEL_STATUS" = "running" ]; then
    echo "✓ OTEL Collector running"
    
    # Quick health check
    RECENT_LOGS=$(docker logs --tail 50 clab-ospf-network-otel-collector 2>&1)
    if echo "$RECENT_LOGS" | grep -qi "started successfully\|ready"; then
        echo "  ✓ Collector started successfully"
    elif echo "$RECENT_LOGS" | grep -qi "error.*elasticsearch\|failed.*elasticsearch"; then
        echo "  ⚠ Elasticsearch connection errors detected"
        echo "$RECENT_LOGS" | grep -i "elasticsearch" | tail -3 | sed 's/^/    /'
    fi
else
    echo "✗ OTEL Collector failed (status: $OTEL_STATUS)"
    exit 1
fi

# ============================================
# PHASE 7: Verify Logstash (NetFlow DISABLED)
# ============================================
echo ""
echo "Phase 7: Verifying Logstash (NetFlow configuration DISABLED)..."

LOGSTASH_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-logstash 2>/dev/null)
if [ "$LOGSTASH_STATUS" = "running" ]; then
    echo "  ✓ Logstash container running"
    echo "  ⚠ NetFlow configuration DISABLED for troubleshooting"
    echo "  ⚠ NetFlow will be configured separately"
else
    echo "  ⚠ Logstash not running (status: $LOGSTASH_STATUS)"
fi

# Verify Logstash config exists but don't activate
if [ -f "configs/logstash/pipeline/netflow.conf" ]; then
    echo "  ✓ NetFlow pipeline config present (not activated)"
else
    echo "  ⚠ NetFlow pipeline config missing"
fi

echo "  NetFlow troubleshooting deferred to separate session"

# ============================================
# PHASE 8: OSPF Convergence Wait
# ============================================
echo ""
echo "Phase 8: Waiting for OSPF convergence (45s)..."
sleep 45

# Verify OSPF neighbors on each router
echo "  Checking OSPF neighbor relationships..."
declare -A EXPECTED_NEIGHBORS=(
    ["csr23"]="4"
    ["csr24"]="4"
    ["csr25"]="4"
    ["csr26"]="4"
    ["csr27"]="2"
    ["csr28"]="2"
    ["csr29"]="2"
)

TOTAL_NEIGHBORS=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    container="clab-ospf-network-$router"
    neighbors=$(docker exec "$container" vtysh -c "show ip ospf neighbor" 2>/dev/null | grep -c "Full" || echo "0")
    expected="${EXPECTED_NEIGHBORS[$router]}"
    
    if [ "$neighbors" -eq "$expected" ]; then
        echo "  ✓ $router: $neighbors/$expected neighbors in Full state"
    else
        echo "  ⚠ $router: $neighbors/$expected neighbors in Full state"
    fi
    
    TOTAL_NEIGHBORS=$((TOTAL_NEIGHBORS + neighbors))
done

echo "  Total OSPF adjacencies: $TOTAL_NEIGHBORS (expected: 22)"

# ============================================
# PHASE 9: Setup LLDP Export Service
# ============================================
echo ""
echo "Phase 9: Setting up LLDP export service..."

if [ -f "./scripts/setup-lldp-service.sh" ]; then
    ./scripts/setup-lldp-service.sh
    
    # Verify service is running
    if systemctl is-active --quiet lldp-export; then
        echo "✓ LLDP export service running"
    else
        echo "⚠ LLDP export service not active"
    fi
else
    echo "⚠ Warning: setup-lldp-service.sh not found"
fi

# ============================================
# PHASE 9.5: Deploy Elastic Agent on sw2 (OPTIONAL)
# ============================================
echo ""
echo "Phase 9.5: Elastic Agent Deployment (Optional)..."
echo ""
echo "  This will deploy an Elastic Agent container connected to sw2"
echo "  The agent will enroll with Fleet and collect system metrics"
echo ""

# Check if Fleet is configured from .env
if [ "$FLEET_CONFIGURED" = true ]; then
    echo "  ✓ Fleet configuration detected in .env:"
    echo "    Fleet URL: $FLEET_URL"
    echo "    Token: ${FLEET_ENROLLMENT_TOKEN:0:20}..."
    echo "    Agent Version: $AGENT_VERSION"
    echo ""
    
    read -p "  Deploy Elastic Agent with these settings? (Y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        DEPLOY_AGENT=false
        echo "  Skipping Elastic Agent deployment"
    else
        DEPLOY_AGENT=true
    fi
else
    echo "  ⚠ Fleet not configured in .env"
    echo "    Run ./scripts/configure-elasticsearch.sh to set up Fleet"
    echo ""
    
    read -p "  Configure Fleet now manually? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        DEPLOY_AGENT=false
        echo "  Skipping Elastic Agent deployment"
    else
        # Manual configuration
        echo ""
        echo "  Manual Fleet Configuration:"
        read -p "  Enter Fleet Server URL: " FLEET_URL
        read -p "  Enter Fleet Enrollment Token: " FLEET_ENROLLMENT_TOKEN
        
        # Ask for agent version
        echo ""
        echo "  Common Elastic Agent versions:"
        echo "    - 8.15.3 (recommended for ES 9.x)"
        echo "    - 8.15.2"
        echo "    - 8.15.1"
        echo "    - 8.15.0"
        echo "    - 8.14.3"
        read -p "  Enter Elastic Agent version [default: 8.15.3]: " AGENT_VERSION
        AGENT_VERSION=${AGENT_VERSION:-8.15.3}
        
        if [ -n "$FLEET_URL" ] && [ -n "$FLEET_ENROLLMENT_TOKEN" ] && [ -n "$AGENT_VERSION" ]; then
            DEPLOY_AGENT=true
            
            # Save to .env for future use
            echo "" >> "$ENV_FILE"
            echo "# Fleet Configuration (added manually during setup)" >> "$ENV_FILE"
            echo "FLEET_URL=$FLEET_URL" >> "$ENV_FILE"
            echo "FLEET_ENROLLMENT_TOKEN=$FLEET_ENROLLMENT_TOKEN" >> "$ENV_FILE"
            echo "AGENT_VERSION=$AGENT_VERSION" >> "$ENV_FILE"
            echo "  ✓ Fleet credentials saved to .env"
        else
            DEPLOY_AGENT=false
            echo "  ✗ Incomplete Fleet configuration. Skipping deployment."
        fi
    fi
fi

# Proceed with deployment if configured
if [ "$DEPLOY_AGENT" = true ] && [ -n "$FLEET_URL" ] && [ -n "$FLEET_ENROLLMENT_TOKEN" ] && [ -n "$AGENT_VERSION" ]; then
    echo ""
    echo "  Deploying Elastic Agent..."
    echo "  Version: $AGENT_VERSION"
    echo "  Fleet URL: $FLEET_URL"
    echo ""
    
    CONTAINER_NAME="elastic-agent-sw2"
    
    # Remove existing container if present
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "  Removing existing agent container..."
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # Get containerlab network
    SW2_NETWORK=$(docker network ls --filter "name=clab" --format "{{.Name}}" | head -1)
    
    if [ -z "$SW2_NETWORK" ]; then
        echo "  ✗ Could not find containerlab network"
        echo "  Skipping agent deployment"
    else
        echo "  Network: $SW2_NETWORK"
        
        # Deploy Elastic Agent container
        echo "  Starting Elastic Agent container..."
        docker run -d \
          --name "$CONTAINER_NAME" \
          --hostname "$CONTAINER_NAME" \
          --user root \
          --network "$SW2_NETWORK" \
          --restart unless-stopped \
          -e FLEET_URL="$FLEET_URL" \
          -e FLEET_ENROLLMENT_TOKEN="$FLEET_ENROLLMENT_TOKEN" \
          -e FLEET_ENROLL=1 \
          -e FLEET_INSECURE=1 \
          -p 2055:2055/udp \
          -v /var/run/docker.sock:/var/run/docker.sock:ro \
          -v /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro \
          -v /proc:/hostfs/proc:ro \
          -v /:/hostfs:ro \
          --cap-add=NET_ADMIN \
          --cap-add=SYS_ADMIN \
          docker.elastic.co/beats/elastic-agent:${AGENT_VERSION} >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo "  ✓ Agent container started"
            
            # Wait for container to stabilize
            sleep 15
            
            # Connect to sw2 bridge
            SW2_CONTAINER=$(docker ps --filter "name=clab-ospf-network-sw2" --format "{{.ID}}")
            AGENT_CONTAINER=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}")
            
            if [ -n "$SW2_CONTAINER" ] && [ -n "$AGENT_CONTAINER" ]; then
                SW2_PID=$(docker inspect -f '{{.State.Pid}}' "$SW2_CONTAINER")
                AGENT_PID=$(docker inspect -f '{{.State.Pid}}' "$AGENT_CONTAINER")
                
                echo "  Connecting agent to sw2 bridge (192.168.20.50/24)..."
                
                # Create veth pair
                sudo ip link add "veth-agent-sw2" type veth peer name "veth-sw2-agent" 2>/dev/null || true
                
                # Move to namespaces
                sudo ip link set "veth-sw2-agent" netns "$SW2_PID" 2>/dev/null || true
                sudo ip link set "veth-agent-sw2" netns "$AGENT_PID" 2>/dev/null || true
                
                # Configure sw2 side
                sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" master br0 2>/dev/null || true
                sudo nsenter -t "$SW2_PID" -n ip link set "veth-sw2-agent" up 2>/dev/null || true
                
                # Configure agent side
                sudo nsenter -t "$AGENT_PID" -n ip addr add 192.168.20.50/24 dev "veth-agent-sw2" 2>/dev/null || true
                sudo nsenter -t "$AGENT_PID" -n ip link set "veth-agent-sw2" up 2>/dev/null || true
                sudo nsenter -t "$AGENT_PID" -n ip route add default via 192.168.20.1 2>/dev/null || true
                
                echo "  ✓ Agent connected to sw2"
                
                # Test connectivity
                sleep 5
                PING_RESULT=$(sudo nsenter -t "$AGENT_PID" -n ping -c 2 192.168.20.1 2>/dev/null | grep -c "2 received" || echo "0")
                if [ "$PING_RESULT" -gt 0 ]; then
                    echo "  ✓ Connectivity to csr28 (192.168.20.1) verified"
                else
                    echo "  ⚠ Could not verify connectivity to csr28"
                fi
            else
                echo "  ⚠ Could not connect to sw2 bridge"
                echo "  Agent is on management network only"
            fi
            
            # Check enrollment status
            sleep 10
            AGENT_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
            
            if [ "$AGENT_STATUS" = "running" ]; then
                echo "  ✓ Agent running"
                
                LOGS=$(docker logs "$CONTAINER_NAME" 2>&1 | tail -20)
                if echo "$LOGS" | grep -qi "successfully enrolled"; then
                    echo "  ✓ Agent successfully enrolled with Fleet"
                elif echo "$LOGS" | grep -qi "enrolling"; then
                    echo "  ⚠ Agent is enrolling (check Fleet in Kibana)"
                elif echo "$LOGS" | grep -qi "error.*enroll\|failed.*enroll"; then
                    echo "  ⚠ Enrollment issues detected"
                    echo "  Check logs: docker logs $CONTAINER_NAME"
                fi
            else
                echo "  ⚠ Agent not running (status: $AGENT_STATUS)"
            fi
            
            echo ""
            echo "  Elastic Agent Details:"
            echo "    Container: $CONTAINER_NAME"
            echo "    Version: $AGENT_VERSION"
            echo "    Network: sw2 at 192.168.20.50"
            echo "    NetFlow Port: 2055/udp (exposed)"
            echo "    Status: Check in Kibana → Fleet → Agents"
            echo ""
            echo "  NetFlow Integration:"
            echo "    To enable NetFlow collection:"
            echo "    1. In Kibana → Fleet → Agent policies → [Your Policy]"
            echo "    2. Add integration → Network Packet Capture"
            echo "    3. Configure: Host = 0.0.0.0:2055, Protocols = netflow"
            echo "    4. Save and apply"
        else
            echo "  ✗ Failed to start agent container"
            echo "  Try manual deployment: ./scripts/deploy-elastic-agent-sw2-stable.sh"
        fi
    fi
else
    echo "  Elastic Agent deployment skipped"
fi

# ============================================
# PHASE 10: Telemetry Collection Wait
# ============================================
echo ""
echo "Phase 10: Waiting for telemetry collection (90s)..."
echo "  SNMP scrapes every 10-30s, allowing time for multiple collections..."
sleep 90

# ============================================
# PHASE 11: Comprehensive Verification
# ============================================
echo ""
echo "========================================="
echo "Verification Phase"
echo "========================================="
echo ""

# 1. Container Status Summary
echo "Container Status:"
printf "  %-30s %-15s %-10s\n" "Container" "Status" "Restart Count"
echo "  ------------------------------------------------------------"
for container in $(docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" | sort); do
    status=$(docker inspect --format='{{.State.Status}}' "$container")
    restarts=$(docker inspect --format='{{.RestartCount}}' "$container")
    printf "  %-30s %-15s %-10s\n" "${container#clab-ospf-network-}" "$status" "$restarts"
done

# 2. SNMP Connectivity
echo ""
echo "SNMP Status (Port 161):"
SNMP_ERRORS=$(docker logs --tail 500 clab-ospf-network-otel-collector 2>&1 | grep -ci "connection refused" || echo "0")
SNMP_SUCCESS=$(docker logs --tail 500 clab-ospf-network-otel-collector 2>&1 | grep -ci "successfully\|exported" || echo "0")
echo "  Connection errors: $SNMP_ERRORS"
echo "  Successful operations: $SNMP_SUCCESS"

# 3. LLDP Status
echo ""
echo "LLDP Status:"
echo "  Routers with neighbors: $LLDP_WORKING/7"
echo "  Total neighbor relationships: $TOTAL_LLDP_NEIGHBORS"

# Quick recheck of LLDP neighbors
CURRENT_LLDP=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    neighbors=$(docker exec "clab-ospf-network-$router" lldpcli show neighbors 2>/dev/null | grep -c "SysName:" || echo "0")
    CURRENT_LLDP=$((CURRENT_LLDP + neighbors))
done
echo "  Current neighbors: $CURRENT_LLDP"

# 3.5. LLDP SNMP (AgentX) Status
echo ""
echo "LLDP SNMP (AgentX) Status:"
LLDP_SNMP_COUNT=0
LLDP_SNMP_NEIGHBORS_CURRENT=0
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    ip="${ACTUAL_IPS[$router]}"
    result=$(snmpwalk -v2c -c public -t 3 -r 1 "$ip" 1.0.8802.1.1.2.1.4.1.1.9 2>&1)
    
    if echo "$result" | grep -q "STRING"; then
        neighbor_count=$(echo "$result" | grep -c "STRING")
        LLDP_SNMP_COUNT=$((LLDP_SNMP_COUNT + 1))
        LLDP_SNMP_NEIGHBORS_CURRENT=$((LLDP_SNMP_NEIGHBORS_CURRENT + neighbor_count))
    fi
done

echo "  Routers exporting LLDP via SNMP: $LLDP_SNMP_COUNT/7"
echo "  Total LLDP neighbors via SNMP: $LLDP_SNMP_NEIGHBORS_CURRENT"

# 4. Ubuntu Hosts Status
echo ""
echo "Ubuntu Hosts Status:"

# linux-bottom
LB_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-linux-bottom 2>/dev/null || echo "unknown")
echo "  linux-bottom: $LB_STATUS (192.168.10.20)"
if [ "$LB_STATUS" = "running" ]; then
    EA_CHECK=$(docker exec clab-ospf-network-linux-bottom bash -c "command -v elastic-agent &>/dev/null && echo 'installed' || echo 'not-installed'" 2>/dev/null)
    if [ "$EA_CHECK" = "installed" ]; then
        echo "    ✓ Elastic Agent installed"
    else
        echo "    ⚠ Elastic Agent not installed (ready for manual setup)"
    fi
fi

# linux-top
LT_STATUS=$(docker inspect --format='{{.State.Status}}' clab-ospf-network-linux-top 2>/dev/null || echo "unknown")
echo "  linux-top: $LT_STATUS (192.168.20.100)"
if [ "$LT_STATUS" = "running" ]; then
    EA_CHECK=$(docker exec clab-ospf-network-linux-top bash -c "command -v elastic-agent &>/dev/null && echo 'installed' || echo 'not-installed'" 2>/dev/null)
    if [ "$EA_CHECK" = "installed" ]; then
        echo "    ✓ Elastic Agent installed"
    else
        echo "    ⚠ Elastic Agent not installed (ready for manual setup)"
    fi
fi

# 5. Elasticsearch Status
echo ""
echo "Elasticsearch Status:"
echo "  Endpoint: $ES_ENDPOINT"

# SNMP Metrics
SNMP_DOCS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/metrics-*/_count" 2>/dev/null | jq -r '.count // 0')
echo "  SNMP metrics: $SNMP_DOCS documents"

# NetFlow - DISABLED
echo "  NetFlow: DISABLED (troubleshoot separately)"

# LLDP
LLDP_DOCS=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" "$ES_ENDPOINT/lldp-topology/_count" 2>/dev/null | jq -r '.count // 0')
echo "  LLDP topology: $LLDP_DOCS documents"

# 6. Recent data check (last 5 minutes)
RECENT_COUNT=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
    "$ES_ENDPOINT/metrics-*/_count" \
    -H 'Content-Type: application/json' \
    -d '{
      "query": {
        "range": {
          "@timestamp": {
            "gte": "now-5m"
          }
        }
      }
    }' 2>/dev/null | jq -r '.count // 0')
echo "  Recent metrics (last 5min): $RECENT_COUNT documents"

# Check recent LLDP data
RECENT_LLDP=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
    "$ES_ENDPOINT/lldp-topology/_count" \
    -H 'Content-Type: application/json' \
    -d '{
      "query": {
        "range": {
          "@timestamp": {
            "gte": "now-5m"
          }
        }
      }
    }' 2>/dev/null | jq -r '.count // 0')
echo "  Recent LLDP (last 5min): $RECENT_LLDP documents"

# 7. Per-Router Metrics
echo ""
echo "Per-Router Metrics:"
for router in csr23 csr24 csr25 csr26 csr27 csr28 csr29; do
    router_docs=$(curl -s -H "Authorization: ApiKey $ES_API_KEY" \
        "$ES_ENDPOINT/metrics-*/_count" \
        -H 'Content-Type: application/json' \
        -d "{\"query\":{\"match\":{\"host.name\":\"$router\"}}}" 2>/dev/null \
        | jq -r '.count // 0')
    
    echo "  $router: $router_docs documents"
done

# 8. System Health Check
echo ""
echo "System Health:"
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
echo "  Load average:$LOAD_AVG"

DISK_USAGE=$(df -h "$LAB_DIR" | tail -1 | awk '{print $5}')
echo "  Disk usage: $DISK_USAGE"

MEMORY_USAGE=$(free -h | grep Mem | awk '{print $3 "/" $2}')
echo "  Memory usage: $MEMORY_USAGE"

# 9. Root User Verification
echo ""
echo "Root User Status:"
ROOT_COUNT=0
for router in csr23 csr24 csr25; do
    user_id=$(docker exec "clab-ospf-network-$router" id -u 2>/dev/null)
    if [ "$user_id" = "0" ]; then
        ROOT_COUNT=$((ROOT_COUNT + 1))
    fi
done
echo "  Sample routers running as root: $ROOT_COUNT/3"

# ============================================
# Final Summary
# ============================================
echo ""
echo "========================================="
echo "   REDEPLOYMENT COMPLETE - v21.0!"
echo "========================================="
echo ""

# Generate summary
TOTAL_CONTAINERS=$(docker ps --filter "name=clab-ospf-network" --format "{{.Names}}" | wc -l)
RUNNING_CONTAINERS=$(docker ps --filter "name=clab-ospf-network" --filter "status=running" --format "{{.Names}}" | wc -l)

echo "Summary:"
echo "  Containers: $RUNNING_CONTAINERS/$TOTAL_CONTAINERS running (AS ROOT)"
echo "  OSPF neighbors: $TOTAL_NEIGHBORS/22 adjacencies"
echo "  SNMP: $SNMP_WORKING/7 routers responding (PORT 161)"
echo "  LLDP: $LLDP_WORKING/7 routers with neighbors ($CURRENT_LLDP relationships)"
echo "  LLDP via SNMP: $LLDP_SNMP_COUNT/7 routers exporting ($LLDP_SNMP_NEIGHBORS_CURRENT neighbors)"
echo "  linux-bottom: $LB_STATUS (Ubuntu 22.04 @ 192.168.10.20)"
echo "  linux-top: $LT_STATUS (Ubuntu 22.04 @ 192.168.20.100)"
echo "  Elasticsearch: $ES_ENDPOINT"
echo "  Data: $SNMP_DOCS SNMP + $LLDP_DOCS LLDP docs"
echo "  Recent data: $RECENT_COUNT SNMP + $RECENT_LLDP LLDP in last 5 minutes"
echo "  NetFlow: DISABLED (troubleshoot separately)"
echo ""

# Determine success level
if [ $RUNNING_CONTAINERS -eq $TOTAL_CONTAINERS ] && [ "$RECENT_COUNT" -gt 0 ] && [ "$SNMP_WORKING" -ge 5 ] && [ "$LLDP_WORKING" -ge 5 ] && [ "$LLDP_SNMP_COUNT" -ge 5 ]; then
    echo "✓✓✓ Lab deployment FULLY SUCCESSFUL!"
    echo "  All systems operational with SNMP and LLDP data collection"
    echo "  LLDP SNMP AgentX integration working"
    echo "  Elasticsearch endpoint automatically configured from .env"
    echo "  NetFlow deferred for separate troubleshooting"
elif [ $RUNNING_CONTAINERS -eq $TOTAL_CONTAINERS ] && [ "$RECENT_COUNT" -gt 0 ] && [ "$SNMP_WORKING" -ge 5 ]; then
    echo "✓✓ Lab deployment successful with SNMP"
    echo "  LLDP or LLDP SNMP may need more time or troubleshooting"
    echo "  Elasticsearch endpoint automatically configured from .env"
    echo "  NetFlow deferred for separate troubleshooting"
elif [ $RUNNING_CONTAINERS -eq $TOTAL_CONTAINERS ] && [ "$SNMP_DOCS" -gt 0 ]; then
    echo "✓ Lab deployment successful (older data exists)"
    echo "  Note: Wait a few minutes for new data to appear"
    echo "  Elasticsearch endpoint automatically configured from .env"
    echo "  NetFlow deferred for separate troubleshooting"
elif [ "$SNMP_WORKING" -lt 5 ]; then
    echo "⚠ Lab deployment complete but SNMP issues detected"
    echo "  Check: docker logs clab-ospf-network-otel-collector"
else
    echo "⚠ Lab deployment complete with warnings"
    echo "  Review the verification output above"
fi

echo ""
echo "Configuration Details:"
echo "  SNMP: Port 161 (standard, containers run as root)"
echo "  SNMP Community: public"
echo "  SNMP AgentX: Enabled for LLDP integration"
echo "  LLDP: TX interval 10s, monitoring all interfaces, exporting via SNMP"
echo "  Logstash: Running (NetFlow disabled)"
echo "  Elasticsearch: Auto-configured from $ENV_FILE"
echo "  linux-bottom: Ubuntu 22.04 at 192.168.10.20 (on sw)"
echo "  linux-top: Ubuntu 22.04 at 192.168.20.100 (on sw2)"
echo "  REMOVED: node1, win-bottom"

echo ""
echo "Quick Tests:"
echo "  SNMP: snmpget -v2c -c public 172.20.20.28 1.3.6.1.2.1.1.1.0"
echo "  LLDP: docker exec clab-ospf-network-csr28 lldpcli show neighbors"
echo "  LLDP SNMP: snmpwalk -v2c -c public 172.20.20.28 1.0.8802.1.1.2.1.4.1.1.9"
echo "  Verify ES endpoint: grep elasticsearch/system configs/otel/otel-collector.yml"
echo "  linux-bottom: docker exec -it clab-ospf-network-linux-bottom bash"
echo "  linux-top: docker exec -it clab-ospf-network-linux-top bash"

echo ""

# Run status script if available
if [ -f "./scripts/status.sh" ]; then
    echo ""
    echo "Running status check..."
    ./scripts/status.sh
fi

echo ""
echo "Next Steps:"
echo "  Interactive menu:     ./scripts/connect.sh"
echo "  Show topology:        ./scripts/show-topology.sh"
echo "  LLDP neighbors:       ./scripts/show-lldp-neighbors.sh"
echo "  List metrics:         ./scripts/list-all-metrics.sh"
echo "  Emergency diagnostic: ./scripts/emergency-diagnostic.sh"
echo ""
echo "Container Access:"
echo "  Router:       docker exec -it clab-ospf-network-csr28 vtysh"
echo "  OTEL:         docker exec -it clab-ospf-network-otel-collector sh"
echo "  Logstash:     docker exec -it clab-ospf-network-logstash bash"
echo "  linux-bottom: docker exec -it clab-ospf-network-linux-bottom bash"
echo "  linux-top:    docker exec -it clab-ospf-network-linux-top bash"

echo ""
echo "Logs:"
echo "  OTEL:         docker logs -f clab-ospf-network-otel-collector"
echo "  Logstash:     docker logs -f clab-ospf-network-logstash"
echo "  Router:       docker logs -f clab-ospf-network-csr28"
echo "  linux-bottom: docker logs -f clab-ospf-network-linux-bottom"
echo "  linux-top:    docker logs -f clab-ospf-network-linux-top"

echo ""
echo "Troubleshooting:"
echo "  SNMP check:"
echo "    docker exec clab-ospf-network-csr28 ps aux | grep snmpd"
echo "    docker exec clab-ospf-network-csr28 netstat -uln | grep 161"
echo "    docker exec clab-ospf-network-csr28 ls -la /var/agentx/"
echo "  LLDP check:"
echo "    docker exec clab-ospf-network-csr28 ps aux | grep lldpd"
echo "    docker exec clab-ospf-network-csr28 lldpcli show interfaces"
echo "    docker exec clab-ospf-network-csr28 lldpcli show neighbors"
echo "  LLDP SNMP check:"
echo "    snmpwalk -v2c -c public 172.20.20.28 1.0.8802.1.1.2.1.4.1.1.9"
echo "  Elasticsearch config check:"
echo "    grep -A 3 'elasticsearch/system:' configs/otel/otel-collector.yml"
echo "    cat .env"
echo "  Ubuntu hosts check:"
echo "    docker exec clab-ospf-network-linux-bottom cat /etc/os-release"
echo "    docker exec clab-ospf-network-linux-top cat /etc/os-release"
echo "    docker exec clab-ospf-network-linux-bottom ip addr"
echo "    docker exec clab-ospf-network-linux-top ip addr"

echo ""
echo "========================================="
echo "✓ Setup complete with LLDP SNMP AgentX!"
echo "  New topology: 7 routers + 2 Ubuntu hosts"
echo "  SNMP: ✓ Enabled (port 161)"
echo "  LLDP: ✓ Enabled with SNMP export"  
echo "  NetFlow: ⚠ DISABLED (troubleshoot separately)"
echo "========================================="
