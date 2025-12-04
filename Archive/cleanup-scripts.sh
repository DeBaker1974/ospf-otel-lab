#!/bin/bash

cd ~/ospf-otel-lab/scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}   Scripts Cleanup Utility${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# Create backup
BACKUP_DIR="../scripts-backup-$(date +%s)"
echo "Creating backup: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -r ./* "$BACKUP_DIR/"
echo -e "${GREEN}✓${NC} Backup created"
echo ""

# Define deprecated scripts
DEPRECATED=(
    "setup-win-bottom.sh"
    "setup-node1.sh"
    "configure-elastic-agent.sh"
    "install-elastic-agent-old.sh"
    "setup-snmp-port-1161.sh"
)

# Define essential scripts
ESSENTIAL=(
    "configure-elasticsearch.sh"
    "status.sh"
    "show-lldp-neighbors.sh"
    "setup-lldp-service.sh"
    "lldp-to-elasticsearch.sh"
    "install-snmp-lldp.sh"
    "create-otel-config-fast-mode.sh"
    "emergency-diagnostic.sh"
    "list-all-metrics.sh"
    "lldp-status.sh"
    "show-topology.sh"
    "setup-persistent-lldp.sh"
    "show-topology-live.sh"
    "generate-topology-graph.sh"
    "export-topology-json.sh"
    "check-netflow-status.sh"
    "setup-netflow.sh"
)

# List all current scripts
echo -e "${YELLOW}Current scripts:${NC}"
ALL_SCRIPTS=($(ls -1 *.sh 2>/dev/null))
for script in "${ALL_SCRIPTS[@]}"; do
    echo "  • $script"
done
echo ""
echo "Total: ${#ALL_SCRIPTS[@]} scripts"
echo ""

# Find deprecated scripts
echo -e "${YELLOW}Scanning for deprecated scripts...${NC}"
FOUND_DEPRECATED=()
for script in "${DEPRECATED[@]}"; do
    if [ -f "$script" ]; then
        FOUND_DEPRECATED+=("$script")
        echo -e "  ${RED}✗${NC} Found: $script"
    fi
done

# Find old backup/version files
echo ""
echo -e "${YELLOW}Scanning for old backups/versions...${NC}"
OLD_FILES=($(ls -1 *-old.sh *-backup*.sh *.sh.bak *-v[0-9]*.sh 2>/dev/null))
for file in "${OLD_FILES[@]}"; do
    # Don't delete if it's the only version
    base_name="${file%-*}"
    if [[ ! " ${ESSENTIAL[@]} " =~ " ${base_name}.sh " ]]; then
        FOUND_DEPRECATED+=("$file")
        echo -e "  ${RED}✗${NC} Found: $file"
    fi
done

# Find non-executable scripts
echo ""
echo -e "${YELLOW}Scanning for non-executable scripts...${NC}"
for script in *.sh; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
        echo -e "  ${YELLOW}⚠${NC} Not executable: $script"
    fi
done

# Summary
echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo "  Total scripts: ${#ALL_SCRIPTS[@]}"
echo "  Essential scripts (defined): ${#ESSENTIAL[@]}"
echo "  Deprecated/old files found: ${#FOUND_DEPRECATED[@]}"
echo ""

if [ ${#FOUND_DEPRECATED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Files to remove:${NC}"
    for file in "${FOUND_DEPRECATED[@]}"; do
        echo "  • $file"
    done
    echo ""
    
    read -p "Remove these files? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        for file in "${FOUND_DEPRECATED[@]}"; do
            rm -f "$file"
            echo -e "${GREEN}✓${NC} Removed: $file"
        done
        echo ""
        echo -e "${GREEN}✓${NC} Cleanup complete"
    else
        echo "Cleanup cancelled"
    fi
else
    echo -e "${GREEN}✓${NC} No deprecated files found"
fi

# Check for missing essential scripts
echo ""
echo -e "${YELLOW}Checking for missing essential scripts...${NC}"
MISSING=()
for script in "${ESSENTIAL[@]}"; do
    if [ ! -f "$script" ]; then
        MISSING+=("$script")
        echo -e "  ${RED}✗${NC} Missing: $script"
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Missing ${#MISSING[@]} essential scripts${NC}"
    echo "These should be created or restored from backup"
else
    echo -e "${GREEN}✓${NC} All essential scripts present"
fi

# Fix permissions
echo ""
echo -e "${YELLOW}Fixing permissions...${NC}"
for script in *.sh; do
    if [ -f "$script" ]; then
        chmod +x "$script"
    fi
done
echo -e "${GREEN}✓${NC} All .sh files are now executable"

echo ""
echo -e "${CYAN}=========================================${NC}"
echo "Cleanup utility finished!"
echo "Backup location: $BACKUP_DIR"
echo ""

