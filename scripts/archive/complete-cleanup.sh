#!/bin/bash

echo "========================================="
echo "Complete Lab Cleanup Script v1.0"
echo "  Removes ALL lab components"
echo "  Resets to clean state"
echo "========================================="

LAB_DIR="$HOME/ospf-otel-lab"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if we're in the right directory
if [ ! -d "$LAB_DIR" ]; then
    print_error "Lab directory not found: $LAB_DIR"
    exit 1
fi

cd "$LAB_DIR"

echo ""
echo "This will completely clean up:"
echo "  - All Containerlab containers"
echo "  - All Docker networks"
echo "  - All FRR state files"
echo "  - All logs"
echo "  - LLDP export service"
echo "  - Orphaned containers"
echo ""
echo "This will NOT remove:"
echo "  - Configuration files (configs/)"
echo "  - Scripts (scripts/)"
echo "  - Topology file (ospf-network.clab.yml)"
echo "  - Environment file (.env)"
echo ""
read -p "Are you sure you want to proceed? (yes/no) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "========================================="
echo "Starting Cleanup..."
echo "========================================="

# ============================================
# PHASE 1: Stop Services
# ============================================
echo ""
echo "Phase 1: Stopping services..."

# Stop LLDP export service
if systemctl list-units --full --all | grep -q "lldp-export.service"; then
    echo "  Stopping LLDP export service..."
    sudo systemctl stop lldp-export 2>/dev/null || true
    sudo systemctl disable lldp-export 2>/dev/null || true
    
    if [ -f "/etc/systemd/system/lldp-export.service" ]; then
        sudo rm /etc/systemd/system/lldp-export.service
        print_info "LLDP service removed"
    fi
    
    if [ -f "/etc/systemd/system/lldp-export.timer" ]; then
        sudo rm /etc/systemd/system/lldp-export.timer
        print_info "LLDP timer removed"
    fi
    
    sudo systemctl daemon-reload
else
    print_info "No LLDP service to remove"
fi

# ============================================
# PHASE 2: Destroy Containerlab Topology
# ============================================
echo ""
echo "Phase 2: Destroying Containerlab topology..."

if [ -f "ospf-network.clab.yml" ]; then
    if sudo clab inspect -t ospf-network.clab.yml &>/dev/null; then
        echo "  Destroying lab..."
        sudo clab destroy -t ospf-network.clab.yml --cleanup 2>&1 | grep -v "level=warning" || true
        print_info "Lab destroyed"
    else
        print_info "No active lab found"
    fi
else
    print_warn "Topology file not found"
fi

sleep 5

# ============================================
# PHASE 3: Remove ALL Lab Containers
# ============================================
echo ""
echo "Phase 3: Removing all lab containers..."

# Get all containers with clab-ospf-network prefix
CONTAINERS=$(docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" 2>/dev/null || echo "")

if [ -n "$CONTAINERS" ]; then
    echo "  Found containers:"
    echo "$CONTAINERS" | sed 's/^/    /'
    echo ""
    
    for container in $CONTAINERS; do
        echo "  Removing: $container"
        docker rm -f "$container" 2>/dev/null || true
    done
    print_info "All lab containers removed"
else
    print_info "No lab containers found"
fi

# Remove any test containers
TEST_CONTAINERS=$(docker ps -a --filter "name=logstash-host-test" --format "{{.Names}}" 2>/dev/null || echo "")
if [ -n "$TEST_CONTAINERS" ]; then
    echo ""
    echo "  Removing test containers..."
    for container in $TEST_CONTAINERS; do
        echo "    Removing: $container"
        docker rm -f "$container" 2>/dev/null || true
    done
    print_info "Test containers removed"
fi

# ============================================
# PHASE 4: Remove Docker Networks
# ============================================
echo ""
echo "Phase 4: Cleaning Docker networks..."

# Remove clab network specifically
if docker network ls | grep -q "clab"; then
    echo "  Removing clab network..."
    docker network rm clab 2>/dev/null || true
    print_info "Clab network removed"
fi

# Prune unused networks
echo "  Pruning unused networks..."
docker network prune -f 2>&1 | grep -v "Total reclaimed space: 0B" || true
print_info "Networks cleaned"

# ============================================
# PHASE 5: Clean FRR State Files
# ============================================
echo ""
echo "Phase 5: Cleaning FRR state files..."

if [ -d "clab-ospf-network" ]; then
    echo "  Removing clab-ospf-network directory..."
    sudo rm -rf clab-ospf-network 2>/dev/null || true
    print_info "FRR state files removed"
else
    print_info "No state files found"
fi

# ============================================
# PHASE 6: Clean Logs
# ============================================
echo ""
echo "Phase 6: Cleaning logs..."

if [ -d "logs" ]; then
    LOG_COUNT=$(find logs -type f -name "*.log" 2>/dev/null | wc -l)
    if [ "$LOG_COUNT" -gt 0 ]; then
        echo "  Found $LOG_COUNT log files"
        rm -f logs/*.log 2>/dev/null || true
        print_info "Log files cleaned"
    else
        print_info "No log files to clean"
    fi
else
    print_info "No logs directory"
fi

# ============================================
# PHASE 7: Clean Backup Files
# ============================================
echo ""
echo "Phase 7: Cleaning backup files..."

# Count backup files
BACKUP_COUNT=$(find . -maxdepth 1 -name "*.backup-*" -o -name "*.yml.backup*" 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt 0 ]; then
    echo "  Found $BACKUP_COUNT backup files"
    
    # Show recent backups
    echo "  Recent backups:"
    find . -maxdepth 1 -name "*.backup-*" -o -name "*.yml.backup*" | head -5 | sed 's/^/    /'
    
    if [ "$BACKUP_COUNT" -gt 10 ]; then
        echo ""
        read -p "  Remove ALL backup files? (y/n) [default: n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            find . -maxdepth 1 -name "*.backup-*" -delete 2>/dev/null || true
            find . -maxdepth 1 -name "*.yml.backup*" -delete 2>/dev/null || true
            print_info "Backup files removed"
        else
            print_info "Backup files kept"
        fi
    else
        print_info "Backup files kept (reasonable amount)"
    fi
else
    print_info "No backup files found"
fi

# ============================================
# PHASE 8: Clean Temporary Files
# ============================================
echo ""
echo "Phase 8: Cleaning temporary files..."

TEMP_FILES=(
    "/tmp/linux-host-node.yml"
    "/tmp/otel-test.yml"
    "/tmp/topology-test.yml"
)

CLEANED=0
for file in "${TEMP_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file" 2>/dev/null || true
        CLEANED=$((CLEANED + 1))
    fi
done

if [ "$CLEANED" -gt 0 ]; then
    print_info "Cleaned $CLEANED temporary files"
else
    print_info "No temporary files to clean"
fi

# ============================================
# PHASE 9: Docker System Cleanup
# ============================================
echo ""
echo "Phase 9: Docker system cleanup..."

echo "  Pruning stopped containers..."
PRUNED=$(docker container prune -f 2>&1)
echo "$PRUNED" | grep -v "Total reclaimed space: 0B" || true

echo "  Pruning unused images (careful)..."
read -p "  Remove unused Docker images? (y/n) [default: n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker image prune -f 2>&1 | grep -v "Total reclaimed space: 0B" || true
    print_info "Unused images removed"
else
    print_info "Images kept"
fi

echo "  Pruning unused volumes..."
read -p "  Remove unused Docker volumes? (y/n) [default: n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker volume prune -f 2>&1 | grep -v "Total reclaimed space: 0B" || true
    print_info "Unused volumes removed"
else
    print_info "Volumes kept"
fi

echo "  Pruning build cache..."
docker builder prune -f 2>&1 | grep -v "Total: 0B" || true

# ============================================
# PHASE 10: Verify Cleanup
# ============================================
echo ""
echo "========================================="
echo "Verification"
echo "========================================="
echo ""

# Check for remaining containers
REMAINING_CONTAINERS=$(docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" 2>/dev/null | wc -l)
if [ "$REMAINING_CONTAINERS" -eq 0 ]; then
    print_info "No lab containers remaining"
else
    print_warn "$REMAINING_CONTAINERS lab containers still present"
    docker ps -a --filter "name=clab-ospf-network" --format "table {{.Names}}\t{{.Status}}"
fi

# Check for clab network
if docker network ls | grep -q "clab"; then
    print_warn "Clab network still exists (may be in use)"
else
    print_info "Clab network removed"
fi

# Check for state directory
if [ -d "clab-ospf-network" ]; then
    print_warn "State directory still exists"
else
    print_info "State directory removed"
fi

# Check for LLDP service
if systemctl list-units --full --all | grep -q "lldp-export"; then
    print_warn "LLDP service still registered"
else
    print_info "LLDP service removed"
fi

# System resources
echo ""
echo "System Resources:"
DISK_USAGE=$(df -h "$LAB_DIR" | tail -1 | awk '{print $5}')
echo "  Disk usage: $DISK_USAGE"

MEMORY_USAGE=$(free -h | grep Mem | awk '{print $3 "/" $2}')
echo "  Memory usage: $MEMORY_USAGE"

DOCKER_IMAGES=$(docker images | grep -E "frrouting|ubuntu|otelcol|logstash" | wc -l)
echo "  Lab-related images: $DOCKER_IMAGES"

# ============================================
# PHASE 11: Optional Deep Clean
# ============================================
echo ""
echo "========================================="
echo "Optional: Deep Clean"
echo "========================================="
echo ""
echo "This will remove configuration backups and reset to initial state."
echo "WARNING: This cannot be undone!"
echo ""
read -p "Perform deep clean? (yes/no) [default: no] " -r
echo

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo ""
    echo "Performing deep clean..."
    
    # Remove ALL backups
    echo "  Removing all backup files..."
    find . -maxdepth 1 -name "*.backup-*" -delete 2>/dev/null || true
    find . -maxdepth 1 -name "*.yml.backup*" -delete 2>/dev/null || true
    print_info "All backups removed"
    
    # Clean OTEL config backups
    if [ -d "configs/otel" ]; then
        OTEL_BACKUPS=$(find configs/otel -name "*.backup-*" 2>/dev/null | wc -l)
        if [ "$OTEL_BACKUPS" -gt 0 ]; then
            find configs/otel -name "*.backup-*" -delete 2>/dev/null || true
            print_info "OTEL config backups removed"
        fi
    fi
    
    # Clean Logstash config backups
    if [ -d "configs/logstash" ]; then
        LOGSTASH_BACKUPS=$(find configs/logstash -name "*.backup-*" 2>/dev/null | wc -l)
        if [ "$LOGSTASH_BACKUPS" -gt 0 ]; then
            find configs/logstash -name "*.backup-*" -delete 2>/dev/null || true
            print_info "Logstash config backups removed"
        fi
    fi
    
    # Remove logs directory entirely
    if [ -d "logs" ]; then
        rm -rf logs
        mkdir -p logs
        print_info "Logs directory reset"
    fi
    
    echo ""
    print_info "Deep clean complete!"
else
    print_info "Deep clean skipped"
fi

# ============================================
# Final Summary
# ============================================
echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
echo ""

# Generate summary
TOTAL_CONTAINERS=$(docker ps -a --filter "name=clab-ospf-network" --format "{{.Names}}" | wc -l)
TOTAL_NETWORKS=$(docker network ls | grep -c "clab" || echo "0")
BACKUP_COUNT=$(find . -maxdepth 1 -name "*.backup-*" -o -name "*.yml.backup*" 2>/dev/null | wc -l)

echo "Summary:"
echo "  Lab containers: $TOTAL_CONTAINERS"
echo "  Lab networks: $TOTAL_NETWORKS"
echo "  Backup files: $BACKUP_COUNT"
echo "  Disk usage: $DISK_USAGE"
echo ""

if [ "$TOTAL_CONTAINERS" -eq 0 ] && [ "$TOTAL_NETWORKS" -eq 0 ]; then
    echo "✓✓✓ Cleanup FULLY SUCCESSFUL!"
    echo ""
    echo "The lab is now in a clean state."
    echo "You can redeploy with: ./scripts/complete-setup.sh"
elif [ "$TOTAL_CONTAINERS" -eq 0 ]; then
    echo "✓✓ Cleanup mostly successful"
    echo "  Note: Some networks may persist (this is normal)"
    echo ""
    echo "You can redeploy with: ./scripts/complete-setup.sh"
else
    echo "⚠ Cleanup completed with warnings"
    echo "  Some containers may still be running"
    echo "  Manual cleanup may be required"
    echo ""
    echo "Check remaining containers:"
    echo "  docker ps -a --filter name=clab-ospf-network"
fi

echo ""
echo "Configuration files preserved:"
echo "  ✓ configs/ directory"
echo "  ✓ scripts/ directory"
echo "  ✓ ospf-network.clab.yml"
echo "  ✓ .env (Elasticsearch credentials)"
echo ""

echo "Next steps:"
echo "  1. Review topology file: cat ospf-network.clab.yml"
echo "  2. Deploy fresh lab: ./scripts/complete-setup.sh"
echo "  3. Or modify configs before deploying"
echo ""

# Create cleanup log
LOG_FILE="logs/cleanup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p logs
cat > "$LOG_FILE" << EOF
Cleanup performed: $(date)
=========================

Containers removed: $TOTAL_CONTAINERS
Networks removed: $TOTAL_NETWORKS
Backup files remaining: $BACKUP_COUNT
Disk usage: $DISK_USAGE
Memory usage: $MEMORY_USAGE

Status: Complete
EOF

echo "Cleanup log saved to: $LOG_FILE"
echo ""

