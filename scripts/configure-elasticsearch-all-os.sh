#!/bin/bash

echo "========================================="
echo "Elasticsearch & Fleet Configuration"
echo "  Supports: Cloud, Serverless & On-Premise"
echo "  Auto-detects: Runtime Environment"
echo "========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$LAB_DIR/.env"

# Universal sed wrapper
sedi() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ============================================
# GLOBAL VARIABLES (set by detection functions)
# ============================================
DEPLOYMENT_TYPE=""          # serverless, cloud, on-premise
RUNTIME_OS=""               # linux, macos, wsl, wsl2
CLOUD_PROVIDER=""           # aws, gcp, azure, none
CLOUD_INSTANCE_TYPE=""      # e.g., "t3.large", "e2-standard-2"
CLOUD_REGION=""             # e.g., "us-east-1", "us-central1"
DETECTED_VERSION=""
AGENT_VERSION=""

# ============================================
# RUNTIME ENVIRONMENT DETECTION
# ============================================

detect_runtime_environment() {
    echo "Detecting runtime environment..."
    echo ""
    
    # ----------------------------------------
    # Step 1: Detect base OS
    # ----------------------------------------
    local uname_out=$(uname -s 2>/dev/null)
    local uname_r=$(uname -r 2>/dev/null)
    
    case "$uname_out" in
        Linux*)
            # Check for WSL first
            if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
                if grep -qi "WSL2" /proc/version 2>/dev/null || [ -n "$WSL_INTEROP" ]; then
                    RUNTIME_OS="wsl2"
                else
                    RUNTIME_OS="wsl"
                fi
            elif [ -n "$WSL_DISTRO_NAME" ]; then
                # Fallback WSL detection via env var
                if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
                    RUNTIME_OS="wsl2"
                else
                    RUNTIME_OS="wsl"
                fi
            else
                RUNTIME_OS="linux"
            fi
            ;;
        Darwin*)
            RUNTIME_OS="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            RUNTIME_OS="windows-shell"
            ;;
        *)
            RUNTIME_OS="unknown"
            ;;
    esac
    
    # ----------------------------------------
    # Step 2: Detect cloud provider (Linux/WSL only)
    # ----------------------------------------
    if [[ "$RUNTIME_OS" == "linux" || "$RUNTIME_OS" == "wsl"* ]]; then
        detect_cloud_provider
    else
        CLOUD_PROVIDER="none"
    fi
    
    # ----------------------------------------
    # Step 3: Display results
    # ----------------------------------------
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ RUNTIME ENVIRONMENT                                         │"
    echo "├─────────────────────────────────────────────────────────────┤"
    
    case "$RUNTIME_OS" in
        "macos")
            local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
            local chip=$(uname -m)
            echo "│  OS:        🍎 macOS $macos_version ($chip)                    "
            echo "│  Provider:  Local Machine                                 │"
            
            # Check if running in a VM on macOS
            if system_profiler SPHardwareDataType 2>/dev/null | grep -q "VMware\|VirtualBox\|Parallels"; then
                echo "│  Note:      Running in VM on macOS                        │"
            fi
            ;;
        "wsl2")
            local distro=${WSL_DISTRO_NAME:-$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')}
            echo "│  OS:        🪟 WSL2 ($distro)                               "
            echo "│  Host:      Windows $(cmd.exe /c ver 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "10/11")"
            echo "│  Provider:  Local Machine (Windows Host)                  │"
            ;;
        "wsl")
            local distro=${WSL_DISTRO_NAME:-$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"')}
            echo "│  OS:        🪟 WSL1 ($distro)                               "
            echo "│  Host:      Windows                                       │"
            echo "│  Provider:  Local Machine (Windows Host)                  │"
            echo "│  ⚠️  Note:   WSL1 may have networking limitations          │"
            ;;
        "linux")
            local distro=$(grep -oP '^PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "Linux")
            echo "│  OS:        🐧 $distro"
            
            case "$CLOUD_PROVIDER" in
                "aws")
                    echo "│  Provider:  ☁️  Amazon Web Services (AWS)                 │"
                    [ -n "$CLOUD_INSTANCE_TYPE" ] && echo "│  Instance:  $CLOUD_INSTANCE_TYPE"
                    [ -n "$CLOUD_REGION" ] && echo "│  Region:    $CLOUD_REGION"
                    ;;
                "gcp")
                    echo "│  Provider:  ☁️  Google Cloud Platform (GCP)               │"
                    [ -n "$CLOUD_INSTANCE_TYPE" ] && echo "│  Instance:  $CLOUD_INSTANCE_TYPE"
                    [ -n "$CLOUD_REGION" ] && echo "│  Zone:      $CLOUD_REGION"
                    ;;
                "azure")
                    echo "│  Provider:  ☁️  Microsoft Azure                           │"
                    [ -n "$CLOUD_INSTANCE_TYPE" ] && echo "│  Instance:  $CLOUD_INSTANCE_TYPE"
                    [ -n "$CLOUD_REGION" ] && echo "│  Region:    $CLOUD_REGION"
                    ;;
                "oracle")
                    echo "│  Provider:  ☁️  Oracle Cloud (OCI)                         │"
                    ;;
                "digitalocean")
                    echo "│  Provider:  ☁️  DigitalOcean                               │"
                    ;;
                "linode")
                    echo "│  Provider:  ☁️  Linode/Akamai                              │"
                    ;;
                "vmware")
                    echo "│  Provider:  🖥️  VMware (vSphere/ESXi)                      │"
                    ;;
                "virtualbox")
                    echo "│  Provider:  📦 VirtualBox                                 │"
                    ;;
                "hyperv")
                    echo "│  Provider:  🪟 Hyper-V                                    │"
                    ;;
                "kvm")
                    echo "│  Provider:  🐧 KVM/QEMU                                   │"
                    ;;
                "docker")
                    echo "│  Provider:  🐳 Docker Container                           │"
                    ;;
                *)
                    echo "│  Provider:  🖥️  Bare Metal / Unknown                      │"
                    ;;
            esac
            ;;
        *)
            echo "│  OS:        ❓ $uname_out (unsupported)                     │"
            ;;
    esac
    
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    # ----------------------------------------
    # Step 4: Runtime-specific warnings
    # ----------------------------------------
    print_runtime_warnings
}

detect_cloud_provider() {
    CLOUD_PROVIDER="none"
    CLOUD_INSTANCE_TYPE=""
    CLOUD_REGION=""
    
    # ----------------------------------------
    # Method 1: Check metadata endpoints (most reliable)
    # ----------------------------------------
    
    # AWS - IMDSv1 and IMDSv2
    if curl -s --connect-timeout 1 --max-time 2 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
        # Try IMDSv2 first (more secure)
        local aws_token=$(curl -s --connect-timeout 1 -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
        
        if [ -n "$aws_token" ]; then
            # IMDSv2
            local instance_check=$(curl -s --connect-timeout 1 -H "X-aws-ec2-metadata-token: $aws_token" \
                http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
            if [[ "$instance_check" == i-* ]]; then
                CLOUD_PROVIDER="aws"
                CLOUD_INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $aws_token" \
                    http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null)
                CLOUD_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $aws_token" \
                    http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
                return
            fi
        else
            # IMDSv1 fallback
            local instance_check=$(curl -s --connect-timeout 1 \
                http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)
            if [[ "$instance_check" == i-* ]]; then
                CLOUD_PROVIDER="aws"
                CLOUD_INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null)
                CLOUD_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)
                return
            fi
        fi
    fi
    
    # GCP
    if curl -s --connect-timeout 1 --max-time 2 -H "Metadata-Flavor: Google" \
        http://169.254.169.254/computeMetadata/v1/instance/ >/dev/null 2>&1; then
        CLOUD_PROVIDER="gcp"
        CLOUD_INSTANCE_TYPE=$(curl -s -H "Metadata-Flavor: Google" \
            "http://169.254.169.254/computeMetadata/v1/instance/machine-type" 2>/dev/null | awk -F/ '{print $NF}')
        CLOUD_REGION=$(curl -s -H "Metadata-Flavor: Google" \
            "http://169.254.169.254/computeMetadata/v1/instance/zone" 2>/dev/null | awk -F/ '{print $NF}')
        return
    fi
    
    # Azure
    local azure_check=$(curl -s --connect-timeout 1 --max-time 2 -H "Metadata:true" \
        "http://169.254.169.254/metadata/instance?api-version=2021-02-01" 2>/dev/null)
    if echo "$azure_check" | grep -q '"compute"' 2>/dev/null; then
        CLOUD_PROVIDER="azure"
        CLOUD_INSTANCE_TYPE=$(echo "$azure_check" | jq -r '.compute.vmSize // empty' 2>/dev/null)
        CLOUD_REGION=$(echo "$azure_check" | jq -r '.compute.location // empty' 2>/dev/null)
        return
    fi
    
    # Oracle Cloud (OCI)
    if curl -s --connect-timeout 1 --max-time 2 \
        http://169.254.169.254/opc/v1/instance/ >/dev/null 2>&1; then
        CLOUD_PROVIDER="oracle"
        return
    fi
    
    # DigitalOcean
    if curl -s --connect-timeout 1 --max-time 2 \
        http://169.254.169.254/metadata/v1/id >/dev/null 2>&1; then
        CLOUD_PROVIDER="digitalocean"
        return
    fi
    
    # ----------------------------------------
    # Method 2: Check DMI/SMBIOS information
    # ----------------------------------------
    if [ -r /sys/class/dmi/id/product_name ] || [ -r /sys/class/dmi/id/sys_vendor ]; then
        local product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
        local sys_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null | tr '[:upper:]' '[:lower:]')
        local board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | tr '[:upper:]' '[:lower:]')
        local chassis_asset=$(cat /sys/class/dmi/id/chassis_asset_tag 2>/dev/null)
        
        # AWS (if metadata didn't work)
        if [[ "$product_name" == *"amazon"* ]] || [[ "$sys_vendor" == *"amazon"* ]]; then
            CLOUD_PROVIDER="aws"
            return
        fi
        
        # GCP
        if [[ "$product_name" == *"google"* ]] || [[ "$sys_vendor" == *"google"* ]]; then
            CLOUD_PROVIDER="gcp"
            return
        fi
        
        # Azure - check chassis asset tag
        if [[ "$chassis_asset" == "7783-7084-3265-9085-8269-3286-77" ]]; then
            CLOUD_PROVIDER="azure"
            return
        fi
        if [[ "$sys_vendor" == *"microsoft"* ]] && [[ "$product_name" == *"virtual machine"* ]]; then
            CLOUD_PROVIDER="azure"
            return
        fi
        
        # VMware
        if [[ "$product_name" == *"vmware"* ]] || [[ "$sys_vendor" == *"vmware"* ]]; then
            CLOUD_PROVIDER="vmware"
            return
        fi
        
        # VirtualBox
        if [[ "$product_name" == *"virtualbox"* ]] || [[ "$sys_vendor" == *"innotek"* ]]; then
            CLOUD_PROVIDER="virtualbox"
            return
        fi
        
        # Hyper-V
        if [[ "$sys_vendor" == *"microsoft"* ]] && [[ "$product_name" == *"virtual"* ]]; then
            CLOUD_PROVIDER="hyperv"
            return
        fi
        
        # KVM/QEMU
        if [[ "$product_name" == *"kvm"* ]] || [[ "$product_name" == *"qemu"* ]] || [[ "$sys_vendor" == *"qemu"* ]]; then
            CLOUD_PROVIDER="kvm"
            return
        fi
    fi
    
    # ----------------------------------------
    # Method 3: Check for container environment
    # ----------------------------------------
    if [ -f /.dockerenv ] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
        CLOUD_PROVIDER="docker"
        return
    fi
    
    # ----------------------------------------
    # Method 4: Check hypervisor via cpuid (requires cpu-checker or virt-what)
    # ----------------------------------------
    if command -v virt-what &>/dev/null; then
        local virt=$(sudo virt-what 2>/dev/null | head -1)
        case "$virt" in
            "aws") CLOUD_PROVIDER="aws" ;;
            "gce") CLOUD_PROVIDER="gcp" ;;
            "azure") CLOUD_PROVIDER="azure" ;;
            "vmware") CLOUD_PROVIDER="vmware" ;;
            "virtualbox") CLOUD_PROVIDER="virtualbox" ;;
            "kvm") CLOUD_PROVIDER="kvm" ;;
            "hyperv") CLOUD_PROVIDER="hyperv" ;;
        esac
        [ "$CLOUD_PROVIDER" != "none" ] && return
    fi
    
    # ----------------------------------------
    # Method 5: Check environment variables
    # ----------------------------------------
    if [ -n "$AWS_REGION" ] || [ -n "$AWS_DEFAULT_REGION" ] || [ -n "$AWS_EXECUTION_ENV" ]; then
        CLOUD_PROVIDER="aws"
        CLOUD_REGION="${AWS_REGION:-$AWS_DEFAULT_REGION}"
        return
    fi
    
    if [ -n "$GOOGLE_CLOUD_PROJECT" ] || [ -n "$GCLOUD_PROJECT" ] || [ -n "$GCP_PROJECT" ]; then
        CLOUD_PROVIDER="gcp"
        return
    fi
    
    if [ -n "$AZURE_SUBSCRIPTION_ID" ] || [ -n "$ARM_SUBSCRIPTION_ID" ]; then
        CLOUD_PROVIDER="azure"
        return
    fi
}

print_runtime_warnings() {
    local warnings=()
    
    # WSL warnings
    if [[ "$RUNTIME_OS" == "wsl" ]]; then
        warnings+=("WSL1 detected - networking may have limitations")
        warnings+=("Consider upgrading to WSL2 for better Docker support")
    fi
    
    # macOS warnings
    if [[ "$RUNTIME_OS" == "macos" ]]; then
        if ! command -v docker &>/dev/null; then
            warnings+=("Docker not found - install Docker Desktop for Mac")
        fi
        if [[ $(uname -m) == "arm64" ]]; then
            warnings+=("Apple Silicon (M1/M2/M3) detected - ensure Docker uses arm64 images")
        fi
    fi
    
    # Cloud-specific warnings
    if [[ "$CLOUD_PROVIDER" == "aws" ]]; then
        # Check if IMDSv2 is required
        if ! curl -s --connect-timeout 1 http://169.254.169.254/latest/meta-data/ >/dev/null 2>&1; then
            warnings+=("AWS IMDSv1 blocked - using IMDSv2 (more secure)")
        fi
    fi
    
    # Docker socket check
    if [[ "$RUNTIME_OS" == "linux" || "$RUNTIME_OS" == "wsl2" ]]; then
        if [ ! -S /var/run/docker.sock ]; then
            warnings+=("Docker socket not found - is Docker running?")
        elif ! docker info >/dev/null 2>&1; then
            warnings+=("Cannot connect to Docker - check permissions (run: sudo usermod -aG docker \$USER)")
        fi
    fi
    
    # Memory check
    local total_mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    if [ -n "$total_mem_kb" ] && [ "$total_mem_kb" -lt 4000000 ]; then
        warnings+=("Low memory detected (<4GB) - lab may be unstable")
    fi
    
    # Print warnings if any
    if [ ${#warnings[@]} -gt 0 ]; then
        echo "⚠️  WARNINGS:"
        for warning in "${warnings[@]}"; do
            echo "   • $warning"
        done
        echo ""
    fi
}

# ============================================
# ELASTICSEARCH DEPLOYMENT DETECTION
# ============================================

test_elasticsearch() {
    local endpoint=$1
    local api_key=$2
    local username=$3
    local password=$4
    
    echo "Testing connection to Elasticsearch..."
    
    # Build curl command based on auth type
    local curl_opts="-s -k --max-time 30"
    
    if [ -n "$api_key" ]; then
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" \
            -H "Authorization: ApiKey $api_key" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts \
            -H "Authorization: ApiKey $api_key" "$endpoint/" 2>/dev/null)
    elif [ -n "$username" ]; then
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" \
            -u "$username:$password" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts \
            -u "$username:$password" "$endpoint/" 2>/dev/null)
    else
        RESPONSE=$(curl $curl_opts -o /dev/null -w "%{http_code}" "$endpoint/" 2>/dev/null)
        CLUSTER_INFO=$(curl $curl_opts "$endpoint/" 2>/dev/null)
    fi
    
    if [ "$RESPONSE" = "200" ]; then
        echo "✓ Connection successful!"
        
        local raw_version=$(echo "$CLUSTER_INFO" | jq -r '.version.number // "unknown"')
        local cluster_name=$(echo "$CLUSTER_INFO" | jq -r '.cluster_name // .name // "unknown"')
        local build_flavor=$(echo "$CLUSTER_INFO" | jq -r '.version.build_flavor // "unknown"')
        local build_type=$(echo "$CLUSTER_INFO" | jq -r '.version.build_type // "unknown"')
        local build_hash=$(echo "$CLUSTER_INFO" | jq -r '.version.build_hash // "unknown"' | cut -c1-12)
        
        # Determine deployment type FIRST (before displaying)
        if [[ "$build_flavor" == "serverless" ]]; then
            DEPLOYMENT_TYPE="serverless"
        elif [[ "$build_flavor" == "default" ]] && [[ "$endpoint" != *".cloud."* ]] && [[ "$endpoint" != *".elastic.cloud"* ]]; then
            DEPLOYMENT_TYPE="on-premise"
        elif [[ "$endpoint" == *".es."*".cloud."* ]] || [[ "$endpoint" == *".elastic-cloud.com"* ]]; then
            DEPLOYMENT_TYPE="cloud"
        elif [[ "$build_type" == "docker" ]] || [[ "$cluster_name" == "docker-cluster" ]]; then
            DEPLOYMENT_TYPE="on-premise"
        else
            if [[ "$endpoint" == *"cloud"* ]] || [[ "$endpoint" == *"found.io"* ]]; then
                DEPLOYMENT_TYPE="cloud"
            else
                DEPLOYMENT_TYPE="on-premise"
            fi
        fi
        
        # Set version based on deployment type
        if [[ "$DEPLOYMENT_TYPE" == "serverless" ]]; then
            # For Serverless: Don't use the raw version - it's meaningless
            DETECTED_VERSION="serverless"
            local display_version="Continuously Updated"
        else
            DETECTED_VERSION="$raw_version"
            local display_version="$raw_version"
        fi
        
        echo ""
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│ ELASTICSEARCH DEPLOYMENT                                    │"
        echo "├─────────────────────────────────────────────────────────────┤"
        printf "│  %-58s │\n" "Cluster:     $cluster_name"
        
        case "$DEPLOYMENT_TYPE" in
            "serverless")
                printf "│  %-58s │\n" "Type:        ⚡ SERVERLESS"
                printf "│  %-58s │\n" "Version:     $display_version"
                printf "│  %-58s │\n" "Build:       $build_hash"
                echo "├─────────────────────────────────────────────────────────────┤"
                echo "│  ℹ️  Serverless is continuously updated by Elastic          │"
                echo "│  • No version matching required for agents                 │"
                echo "│  • Fleet is integrated (no separate Fleet URL)             │"
                echo "│  • Uses data streams exclusively                           │"
                echo "│  • Some index operations restricted                        │"
                ;;
            "cloud")
                printf "│  %-58s │\n" "Type:        ☁️  ELASTIC CLOUD (Hosted)"
                printf "│  %-58s │\n" "Version:     $display_version"
                printf "│  %-58s │\n" "Build:       $build_flavor / $build_type"
                echo "├─────────────────────────────────────────────────────────────┤"
                echo "│  • Fleet available via Cloud Console                       │"
                echo "│  • Full index management capabilities                      │"
                echo "│  • Agent version should match ES version                   │"
                ;;
            "on-premise")
                printf "│  %-58s │\n" "Type:        🏠 SELF-MANAGED"
                printf "│  %-58s │\n" "Version:     $display_version"
                printf "│  %-58s │\n" "Build:       $build_flavor / $build_type"
                echo "├─────────────────────────────────────────────────────────────┤"
                echo "│  • Fleet Server required for agent management              │"
                echo "│  • Full control over indices and ILM                       │"
                echo "│  • Agent version should match ES version                   │"
                ;;
        esac
        echo "└─────────────────────────────────────────────────────────────┘"
        
        # Test write permission
        echo ""
        echo "Testing write permissions..."
        test_write_permission "$endpoint" "$api_key" "$username" "$password"
        
        return 0
    else
        echo "✗ Connection failed (HTTP $RESPONSE)"
        echo ""
        echo "Common endpoints by deployment type:"
        echo "  Self-Managed:  https://elasticsearch.local:9200"
        echo "  Elastic Cloud: https://xxx.es.region.cloud.es.io:443"
        echo "  Serverless:    https://xxx.es.region.elastic.cloud:443"
        return 1
    fi
}


# ============================================
# DYNAMIC AGENT VERSION DETECTION
# ============================================

get_latest_agent_version() {
    echo "  Fetching latest Elastic Agent version..." >&2
    
    # Method 1: Elastic Artifacts API (most reliable)
    local latest_from_api=$(fetch_from_elastic_api)
    if [ -n "$latest_from_api" ]; then
        echo "$latest_from_api"
        return 0
    fi
    
    # Method 2: GitHub Releases API
    local latest_from_github=$(fetch_from_github_api)
    if [ -n "$latest_from_github" ]; then
        echo "$latest_from_github"
        return 0
    fi
    
    # Method 3: Docker Hub Tags
    local latest_from_docker=$(fetch_from_docker_hub)
    if [ -n "$latest_from_docker" ]; then
        echo "$latest_from_docker"
        return 0
    fi
    
    # Method 4: Probe artifacts (fallback)
    local latest_from_probe=$(probe_latest_version)
    if [ -n "$latest_from_probe" ]; then
        echo "$latest_from_probe"
        return 0
    fi
    
    # Final fallback
    echo "  ⚠ Could not detect latest version, using fallback" >&2
    echo "8.17.0"
}

fetch_from_elastic_api() {
    # Elastic publishes version info at artifacts-api.elastic.co
    local api_response=$(curl -s --max-time 10 \
        "https://artifacts-api.elastic.co/v1/versions" 2>/dev/null)
    
    if [ -z "$api_response" ]; then
        return 1
    fi
    
    # Extract stable versions (X.Y.Z format, no snapshots/prereleases)
    # Sort by version and get the latest
    local latest=$(echo "$api_response" | \
        jq -r '.versions[]? // empty' 2>/dev/null | \
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
        sort -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)
    
    if [ -n "$latest" ] && check_agent_version_exists "$latest"; then
        echo "  ✓ Latest from Elastic API: $latest" >&2
        echo "$latest"
        return 0
    fi
    
    return 1
}

fetch_from_github_api() {
    # GitHub releases API for elastic-agent
    local api_response=$(curl -s --max-time 10 \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/elastic/elastic-agent/releases?per_page=10" 2>/dev/null)
    
    if [ -z "$api_response" ]; then
        return 1
    fi
    
    # Get the latest non-prerelease version
    local latest=$(echo "$api_response" | \
        jq -r '.[] | select(.prerelease == false) | .tag_name' 2>/dev/null | \
        sed 's/^v//' | \
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
        head -1)
    
    if [ -n "$latest" ] && check_agent_version_exists "$latest"; then
        echo "  ✓ Latest from GitHub: $latest" >&2
        echo "$latest"
        return 0
    fi
    
    return 1
}

fetch_from_docker_hub() {
    # Docker Hub tags API
    local api_response=$(curl -s --max-time 10 \
        "https://hub.docker.com/v2/repositories/elastic/elastic-agent/tags?page_size=50&ordering=last_updated" 2>/dev/null)
    
    if [ -z "$api_response" ]; then
        return 1
    fi
    
    # Extract version tags (exclude 'latest', snapshots, etc.)
    local latest=$(echo "$api_response" | \
        jq -r '.results[].name' 2>/dev/null | \
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | \
        sort -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)
    
    if [ -n "$latest" ]; then
        echo "  ✓ Latest from Docker Hub: $latest" >&2
        echo "$latest"
        return 0
    fi
    
    return 1
}

probe_latest_version() {
    # Probe artifacts.elastic.co directly
    # Start high and work down for efficiency
    echo "  Probing for latest version..." >&2
    
    # Check 9.x first (newest major), then 8.x
    for major in 9 8; do
        # Start from likely current minor version and go down
        for minor in $(seq 15 -1 0); do
            # Check a few patch versions
            for patch in $(seq 5 -1 0); do
                local test_version="${major}.${minor}.${patch}"
                
                # Quick HEAD request to check if version exists
                local url="https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${test_version}-linux-x86_64.tar.gz"
                local http_code=$(curl -s -o /dev/null -w "%{http_code}" -I --max-time 3 "$url" 2>/dev/null)
                
                if [ "$http_code" = "200" ]; then
                    echo "  ✓ Found latest: $test_version" >&2
                    echo "$test_version"
                    return 0
                fi
            done
        done
    done
    
    return 1
}

# Optimized version existence check
check_agent_version_exists() {
    local version=$1
    
    # Determine correct architecture
    local arch="linux-x86_64"
    if [[ "$RUNTIME_OS" == "macos" ]]; then
        if [[ $(uname -m) == "arm64" ]]; then
            arch="darwin-aarch64"
        else
            arch="darwin-x86_64"
        fi
    fi
    
    local url="https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${version}-${arch}.tar.gz"
    
    # Use HEAD request for speed
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -I --max-time 5 "$url" 2>/dev/null)
    [ "$http_code" = "200" ]
}


find_latest_available_agent_version() {
    local target_version=$1
    
    echo "  Determining Elastic Agent version..." >&2
    
    # Serverless: Always use latest available
    if [[ "$DEPLOYMENT_TYPE" == "serverless" ]] || [[ "$target_version" == "serverless" ]]; then
        echo "  Serverless: Fetching latest stable agent..." >&2
        local latest=$(get_latest_agent_version)
        echo "$latest"
        return 0
    fi
    
    # Cloud/On-premise: Try to match ES version first, then fall back to latest
    if [ -n "$target_version" ] && [[ "$target_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  Checking for agent version matching ES $target_version..." >&2
        
        # Try exact match
        if check_agent_version_exists "$target_version"; then
            echo "  ✓ Exact match: $target_version" >&2
            echo "$target_version"
            return 0
        fi
        
        # Try same major.minor with different patch
        local major_minor=$(echo "$target_version" | cut -d. -f1-2)
        for patch in $(seq 10 -1 0); do
            local test_version="${major_minor}.${patch}"
            if check_agent_version_exists "$test_version"; then
                echo "  ✓ Compatible version: $test_version" >&2
                echo "$test_version"
                return 0
            fi
        done
        
        echo "  ⚠ No matching version found, using latest..." >&2
    fi
    
    # Fallback to latest
    get_latest_agent_version
}



# ============================================
# FLEET CONFIGURATION (DEPLOYMENT AWARE)
# ============================================

configure_fleet() {
    echo ""
    echo "========================================="
    echo "Fleet Configuration"
    echo "========================================="
    
    if [[ "$DEPLOYMENT_TYPE" == "serverless" ]]; then
        configure_fleet_serverless
    elif [[ "$DEPLOYMENT_TYPE" == "cloud" ]]; then
        configure_fleet_cloud
    else
        configure_fleet_onpremise
    fi
}

configure_fleet_serverless() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ SERVERLESS FLEET CONFIGURATION                              │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Fleet is integrated into Serverless deployments.           │"
    echo "│                                                             │"
    echo "│ To get enrollment details:                                  │"
    echo "│ 1. Go to Kibana → Fleet → Agents                            │"
    echo "│ 2. Click 'Add agent'                                        │"
    echo "│ 3. Select your policy                                       │"
    echo "│ 4. Copy the enrollment token and Fleet URL                  │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    read -p "Configure Fleet enrollment now? (y/N): " config_now
    
    if [[ ! $config_now =~ ^[Yy]$ ]]; then
        echo "⚠ Fleet configuration skipped"
        FLEET_URL=""
        FLEET_ENROLLMENT_TOKEN=""
        return 1
    fi
    
    echo ""
    echo "From the Kibana Fleet enrollment screen:"
    read -p "  Fleet URL: " FLEET_URL
    
    if [ -z "$FLEET_URL" ]; then
        echo "✗ Fleet URL required"
        return 1
    fi
    
    read -sp "  Enrollment Token: " FLEET_ENROLLMENT_TOKEN
    echo ""
    
    if [ -z "$FLEET_ENROLLMENT_TOKEN" ]; then
        echo "✗ Enrollment token required"
        FLEET_URL=""
        return 1
    fi
    
    echo "✓ Fleet configured for Serverless"
    return 0
}

configure_fleet_cloud() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ ELASTIC CLOUD FLEET CONFIGURATION                           │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Fleet Server is managed by Elastic Cloud.                   │"
    echo "│                                                             │"
    echo "│ Your Fleet URL format:                                      │"
    echo "│   https://xxx.fleet.region.cloud.es.io:443                  │"
    echo "│                                                             │"
    echo "│ Get details from:                                           │"
    echo "│   Cloud Console → Deployment → Fleet                        │"
    echo "│   OR Kibana → Fleet → Settings                              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    read -p "Fleet Server URL (Enter to skip): " FLEET_URL
    
    if [ -z "$FLEET_URL" ]; then
        echo "⚠ Fleet configuration skipped"
        FLEET_ENROLLMENT_TOKEN=""
        return 1
    fi
    
    # Validate URL format
    if [[ ! $FLEET_URL =~ ^https?:// ]]; then
        echo "✗ Must start with https://"
        FLEET_URL=""
        return 1
    fi
    
    # Add port if missing (Cloud uses 443)
    if [[ ! $FLEET_URL =~ :[0-9]+$ ]]; then
        FLEET_URL="${FLEET_URL}:443"
        echo "  Updated: $FLEET_URL"
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

configure_fleet_onpremise() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ SELF-MANAGED FLEET CONFIGURATION                            │"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ You need a Fleet Server deployed in your environment.       │"
    echo "│                                                             │"
    echo "│ Common Fleet Server URLs:                                   │"
    echo "│   https://fleet-server:8220                                 │"
    echo "│   https://fleet.yourdomain.com:8220                         │"
    echo "│                                                             │"
    echo "│ Create enrollment token in:                                 │"
    echo "│   Kibana → Fleet → Enrollment tokens                        │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
    
    read -p "Fleet Server URL (Enter to skip): " FLEET_URL
    
    if [ -z "$FLEET_URL" ]; then
        echo "⚠ Fleet configuration skipped"
        FLEET_ENROLLMENT_TOKEN=""
        return 1
    fi
    
    if [[ ! $FLEET_URL =~ ^https?:// ]]; then
        echo "✗ Must start with http:// or https://"
        FLEET_URL=""
        return 1
    fi
    
    # Add port if missing (on-premise uses 8220)
    if [[ ! $FLEET_URL =~ :[0-9]+$ ]]; then
        echo ""
        echo "⚠ No port specified."
        read -p "Add :8220 to URL? (Y/n): " add_port
        if [[ ! $add_port =~ ^[Nn]$ ]]; then
            FLEET_URL="${FLEET_URL}:8220"
            echo "  Updated: $FLEET_URL"
        fi
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

# ============================================
# PORT SUGGESTION
# ============================================

suggest_port() {
    local url=$1
    local service=$2
    
    # Already has port
    [[ $url =~ :[0-9]+$ ]] && return
    
    # Cloud URLs use 443
    if [[ $url =~ elastic.*cloud|\.es\.|\.fleet\.|\.cloud\. ]]; then
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

# ============================================
# CONFIGURATION FILE UPDATES
# ============================================

update_otel_collector() {
    # We don't need the actual values here anymore since we use env vars
    # But we'll keep the arguments for compatibility
    
    OTEL_CONFIG="$LAB_DIR/configs/otel/otel-collector.yml"

    
    echo ""
    echo "Updating OTel Collector configuration to use environment variables..."
    
    if [ ! -f "$OTEL_CONFIG" ]; then
        echo "⚠ OTel config not found: $OTEL_CONFIG"
        return 1
    fi
    
    cp "$OTEL_CONFIG" "${OTEL_CONFIG}.backup-$(date +%s)"
    
    # Force use of environment variable syntax
    sedi 's|endpoints: \[ "https://[^"]*" \]|endpoints: [ "${env:ES_ENDPOINT}" ]|g' "$OTEL_CONFIG"
    sedi 's|endpoints: \[ "http://[^"]*" \]|endpoints: [ "${env:ES_ENDPOINT}" ]|g' "$OTEL_CONFIG"
    sedi 's|api_key: "[^"]*"|api_key: "${env:ES_API_KEY}"|g' "$OTEL_CONFIG"
    
    echo "✓ OTel Collector configuration set to use \${env:ES_ENDPOINT}"
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "clab-ospf-network-otel-collector"; then
        read -p "Restart OTel Collector? (Y/n): " restart
        # We assume the container already has the env vars from .env file via clab
        [[ ! $restart =~ ^[Nn]$ ]] && docker restart clab-ospf-network-otel-collector >/dev/null 2>&1 && echo "✓ OTel Collector restarted"
    fi
}


update_logstash_pipeline() {
    # Arguments ignored to prevent hardcoding - purely relies on env variables now
    
    PIPELINE_FILE="$LAB_DIR/configs/logstash/pipeline/snmp-traps.conf"
    
    echo ""
    echo "Updating Logstash pipeline to use environment variables..."
    
    mkdir -p "$(dirname $PIPELINE_FILE)"
    [ -f "$PIPELINE_FILE" ] && cp "$PIPELINE_FILE" "${PIPELINE_FILE}.backup-$(date +%s)"
    
    # Use quoted 'PIPELINE_EOF' to prevent variable expansion during creation
    # This writes "${ES_ENDPOINT}" literally into the file
    cat > "$PIPELINE_FILE" << 'PIPELINE_EOF'
input {
  snmptrap {
    host => "0.0.0.0"
    port => 1062
    community => ["public"]
  }
}

filter {
  # Add host identification for CSR23 (trap source)
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
      add_field => { "event.action" => "interface-down" }
    }
  } else if [oid] == "1.3.6.1.6.3.1.1.5.4" {
    mutate { 
      add_tag => ["interface_up"] 
      add_field => { "event.action" => "interface-up" }
    }
  }
  
  # Add data stream fields for proper indexing
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
  stdout { codec => rubydebug }
  
  # Elasticsearch output - uses environment variables from container
  elasticsearch {
    hosts => ["${ES_ENDPOINT}"]
    api_key => "${ES_API_KEY}"
    data_stream => true
    data_stream_type => "logs"
    data_stream_dataset => "snmp.trap"
    data_stream_namespace => "prod"
  }
}
PIPELINE_EOF

    echo "✓ Logstash pipeline configured with dynamic \${ES_ENDPOINT}"
    
    # Restart Logstash if running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "clab-ospf-network-logstash"; then
        read -p "Restart Logstash? (Y/n): " restart
        if [[ ! $restart =~ ^[Nn]$ ]]; then
            docker restart clab-ospf-network-logstash >/dev/null 2>&1
            echo "✓ Logstash restarted"
        fi
    fi
}



# ============================================
# ELASTICSEARCH CONFIGURATION
# ============================================

configure_elasticsearch() {
    echo "========================================="
    echo "Elasticsearch Configuration"
    echo "========================================="
    echo ""
    echo "Supported deployments:"
    echo "  • Self-Managed: http(s)://host:9200"
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
            echo "   Self-Managed: 9200 | Cloud/Serverless: 443"
            read -p "Add :$SUGGESTED_PORT to endpoint? (Y/n): " add_port
            [[ ! $add_port =~ ^[Nn]$ ]] && ES_ENDPOINT="${ES_ENDPOINT}:${SUGGESTED_PORT}" && echo "  Updated: $ES_ENDPOINT"
        fi
        break
    done

    echo ""
    echo "Authentication:"
    echo "  1) API Key (recommended for all deployments)"
    echo "  2) Username/Password (Self-Managed only)"
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
        echo "  - For Serverless: Use the Cloud Console or Kibana"
        read -sp "API Key (base64 encoded): " ES_API_KEY
        echo ""
    fi

    echo ""
    if ! test_elasticsearch "$ES_ENDPOINT" "$ES_API_KEY" "$ES_USERNAME" "$ES_PASSWORD"; then
        echo "✗ Elasticsearch connection failed"
        return 1
    fi
    
    echo ""
    echo "Determining Elastic Agent version..."
    AGENT_VERSION=$(find_latest_available_agent_version "$DETECTED_VERSION")
    echo "✓ Agent version: $AGENT_VERSION"
    
    return 0
}

update_topology_file() {
    local agent_ver=$1
    TOPOLOGY_FILE="$LAB_DIR/ospf-network.clab.yml"
    
    echo ""
    echo "Updating topology configuration..."
    
    if [ ! -f "$TOPOLOGY_FILE" ]; then
        echo "⚠ Topology file not found: $TOPOLOGY_FILE"
        return 1
    fi
    
    # Update Agent Version
    if [ -n "$agent_ver" ]; then
        sedi "s|image: elastic/elastic-agent:[0-9.]*|image: elastic/elastic-agent:$agent_ver|g" "$TOPOLOGY_FILE"
        sedi "s|image: docker.elastic.co/logstash/logstash:[0-9.]*|image: docker.elastic.co/logstash/logstash:$agent_ver|g" "$TOPOLOGY_FILE"
        echo "✓ Updated agent version to $agent_ver"
    fi
    
    # Ensure OTEL collector has env vars
    if ! grep -A 10 "otel-collector:" "$TOPOLOGY_FILE" | grep -q "ES_ENDPOINT"; then
        sedi '/otel-collector:/,/ports:/{
            /cmd:/a\      env:\n        ES_ENDPOINT: ${ES_ENDPOINT}\n        ES_API_KEY: ${ES_API_KEY}
        }' "$TOPOLOGY_FILE"
        echo "✓ Added environment variables to OTEL collector"
    fi
}

# ============================================
# MAIN SCRIPT
# ============================================

# Step 1: Detect runtime environment
detect_runtime_environment

# Step 2: Check prerequisites based on runtime
echo "Checking prerequisites..."
if [[ "$RUNTIME_OS" == "macos" ]]; then
    if ! command -v docker &>/dev/null; then
        echo "✗ Docker not installed"
        echo "  Install Docker Desktop: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "⚠ jq not installed (install with: brew install jq)"
    fi
elif [[ "$RUNTIME_OS" == "wsl"* ]] || [[ "$RUNTIME_OS" == "linux" ]]; then
    if ! command -v docker &>/dev/null; then
        echo "✗ Docker not installed"
        echo "  Run: ./scripts/install-lab-prereqs.sh"
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "✗ Cannot connect to Docker"
        echo "  Try: sudo usermod -aG docker \$USER && newgrp docker"
        exit 1
    fi
fi
echo "✓ Prerequisites OK"
echo ""

# Step 3: Check existing config
if [ -f "$ENV_FILE" ]; then
    echo "Existing configuration found."
    source "$ENV_FILE"
    
    if [ -n "$ES_ENDPOINT" ] && [ -n "$ES_API_KEY" ]; then
        echo "  Endpoint: $ES_ENDPOINT"
        echo "  API Key:  ${ES_API_KEY:0:20}..."
        [ -n "$FLEET_URL" ] && echo "  Fleet:    $FLEET_URL"
        [ -n "$SAVED_DEPLOYMENT_TYPE" ] && echo "  Type:     $SAVED_DEPLOYMENT_TYPE"
        [ -n "$SAVED_RUNTIME_OS" ] && echo "  Runtime:  $SAVED_RUNTIME_OS"
        echo ""
        
        read -p "Update configuration? (y/N): " update_config
        if [[ ! $update_config =~ ^[Yy]$ ]]; then
            echo "Keeping existing configuration."
            exit 0
        fi
    fi
fi

# Step 4: Configure Elasticsearch
if ! configure_elasticsearch; then
    echo "✗ Configuration failed"
    exit 1
fi

# Step 5: Configure Fleet
echo ""
read -p "Configure Fleet for agent deployment? (y/N): " config_fleet
[[ $config_fleet =~ ^[Yy]$ ]] && configure_fleet

# Step 6: Save configuration
echo ""
echo "Saving configuration..."

cat > "$ENV_FILE" << ENVEOF
# Elasticsearch Configuration - $(date)
# Runtime: $RUNTIME_OS | Cloud: $CLOUD_PROVIDER | ES Type: $DEPLOYMENT_TYPE

ES_ENDPOINT=$ES_ENDPOINT
ES_API_KEY=$ES_API_KEY
ES_USERNAME=$ES_USERNAME
ES_PASSWORD=$ES_PASSWORD
ES_VERSION=$DETECTED_VERSION
AGENT_VERSION=$AGENT_VERSION

# Deployment metadata
SAVED_DEPLOYMENT_TYPE=$DEPLOYMENT_TYPE
SAVED_RUNTIME_OS=$RUNTIME_OS
SAVED_CLOUD_PROVIDER=$CLOUD_PROVIDER
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
echo "  ES Type:       $DEPLOYMENT_TYPE"
echo "  Agent Version: $AGENT_VERSION"
echo "  Runtime:       $RUNTIME_OS"
echo "  Cloud:         $CLOUD_PROVIDER"
[ -n "$FLEET_URL" ] && echo "  Fleet URL:     $FLEET_URL"
echo ""

# Step 7: Update component configs
update_logstash_pipeline "$ES_ENDPOINT" "$ES_API_KEY"
update_otel_collector "$ES_ENDPOINT" "$ES_API_KEY"
update_topology_file "$AGENT_VERSION"  # ← Add this line

# Step 8: Update topology if script exists
if [ -f "$LAB_DIR/scripts/update-topology-from-env.sh" ]; then
    bash "$LAB_DIR/scripts/update-topology-from-env.sh"
fi


echo ""
echo "========================================="
echo "Next Steps"
echo "========================================="

if [[ "$DEPLOYMENT_TYPE" == "serverless" ]]; then
    echo "  ⚡ Serverless detected:"
    echo "     • Data streams will be used automatically"
    echo "     • Fleet is integrated in your deployment"
    echo "     • Some lab features may need adjustment"
fi

if [[ "$RUNTIME_OS" == "macos" ]]; then
    echo "  🍎 macOS detected:"
    echo "     • Ensure Docker Desktop has sufficient resources"
    echo "     • Recommended: 4+ CPU cores, 8GB+ RAM for Docker"
fi

if [[ "$RUNTIME_OS" == "wsl"* ]]; then
    echo "  🪟 WSL detected:"
    echo "     • Ensure WSL2 is configured for Docker"
    echo "     • Check: wsl --set-default-version 2"
fi

echo ""
echo "Run: ./scripts/complete-setup.sh"
