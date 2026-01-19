#!/bin/bash

# ==========================================
# OSPF Lab Prerequisites Installer
# Installs: Docker and Containerlab
# Platforms: Ubuntu/Debian, macOS, WSL
# ==========================================

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==========================================
# Detect Platform FIRST (before any installs)
# ==========================================
detect_platform() {
    PLATFORM="unknown"
    ARCH=$(uname -m)
    
    case "$(uname -s)" in
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            elif [ -f /etc/debian_version ]; then
                PLATFORM="debian"
            elif [ -f /etc/redhat-release ]; then
                PLATFORM="rhel"
            else
                PLATFORM="linux"
            fi
            ;;
        Darwin*)
            PLATFORM="macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            PLATFORM="windows"
            ;;
    esac
    
    # Normalize architecture
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
    esac
    
    log "Detected platform: $PLATFORM (arch: $ARCH)"
}

# ==========================================
# Check if Docker is already working
# ==========================================
check_docker() {
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null 2>&1; then
            success "Docker is already installed and running: $(docker --version)"
            return 0
        else
            warn "Docker is installed but not running or not accessible"
            return 1
        fi
    fi
    return 1
}

# ==========================================
# Check if Containerlab is installed
# ==========================================
check_containerlab() {
    if command -v containerlab &> /dev/null; then
        success "Containerlab is already installed: $(containerlab version 2>/dev/null | grep version | head -1)"
        return 0
    fi
    return 1
}

# ==========================================
# macOS Installation
# ==========================================
install_macos() {
    log "Setting up prerequisites for macOS..."
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        log "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add Homebrew to PATH for Apple Silicon
        if [ "$ARCH" = "arm64" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        fi
    fi
    success "Homebrew is available"
    
    # Install Docker Desktop
    if ! check_docker; then
        if [ -d "/Applications/Docker.app" ]; then
            warn "Docker Desktop is installed but not running"
            echo ""
            echo "Please start Docker Desktop:"
            echo "  1. Open /Applications/Docker.app"
            echo "  2. Wait for the whale icon in the menu bar"
            echo ""
            log "Attempting to start Docker Desktop..."
            open -a Docker
            
            echo "Waiting up to 60 seconds for Docker to start..."
            for i in {1..60}; do
                sleep 1
                if docker info &> /dev/null 2>&1; then
                    success "Docker Desktop is now running!"
                    break
                fi
                echo -n "."
            done
            echo ""
            
            if ! docker info &> /dev/null 2>&1; then
                error "Docker didn't start. Please start it manually and re-run this script."
                exit 1
            fi
        else
            log "Installing Docker Desktop via Homebrew..."
            brew install --cask docker
            
            echo ""
            warn "Docker Desktop installed. You must start it manually:"
            echo "  1. Open /Applications/Docker.app"
            echo "  2. Complete the setup wizard"
            echo "  3. Wait for Docker to start"
            echo "  4. Re-run this script"
            echo ""
            
            open -a Docker
            exit 0
        fi
    fi
    
    # Install Containerlab
    if ! check_containerlab; then
        log "Installing Containerlab via Homebrew..."
        brew install containerlab
    fi
    
    # Install additional tools
    log "Installing additional tools..."
    brew install jq curl wget git 2>/dev/null || true
    
    # Install SNMP tools (optional)
    brew install net-snmp 2>/dev/null || true
}

# ==========================================
# Debian/Ubuntu Installation
# ==========================================
install_debian() {
    log "Setting up prerequisites for Debian/Ubuntu..."
    
    # Install dependencies
    log "Installing system dependencies..."
    sudo apt-get update -qq
    sudo apt-get install -y \
        curl \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        gnupg \
        lsb-release \
        jq \
        git \
        wget
    
    # Install Docker if needed
    if ! check_docker; then
        log "Installing Docker CE..."
        
        OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        CODENAME=$(lsb_release -cs)
        
        # Add Docker GPG key
        sudo mkdir -p /etc/apt/keyrings
        sudo rm -f /etc/apt/keyrings/docker.gpg
        curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Add user to docker group
        if ! getent group docker > /dev/null; then
            sudo groupadd docker
        fi
        sudo usermod -aG docker $USER
        
        # Start Docker
        sudo systemctl enable docker
        sudo systemctl start docker
        
        success "Docker CE installed"
        NEED_RELOGIN=true
    fi
    
    # Install Containerlab
    if ! check_containerlab; then
        log "Installing Containerlab..."
        bash -c "$(curl -sL https://get.containerlab.dev)"
    fi
    
    # Install SNMP tools
    log "Installing SNMP tools..."
    sudo apt-get install -y snmp snmp-mibs-downloader net-tools 2>/dev/null || true
    sudo download-mibs 2>/dev/null || true
}

# ==========================================
# WSL Installation
# ==========================================
install_wsl() {
    log "Setting up prerequisites for WSL..."
    
    # Check if Docker Desktop for Windows is available
    if command -v docker &> /dev/null && docker info 2>&1 | grep -q "Docker Desktop"; then
        success "Docker Desktop for Windows detected with WSL integration"
        DOCKER_DESKTOP=true
    else
        DOCKER_DESKTOP=false
    fi
    
    # Install base dependencies (apt works in WSL)
    sudo apt-get update -qq
    sudo apt-get install -y \
        curl \
        apt-transport-https \
        ca-certificates \
        software-properties-common \
        gnupg \
        lsb-release \
        jq \
        git \
        wget
    
    # Install Docker
    if ! check_docker; then
        if [ "$DOCKER_DESKTOP" = true ]; then
            warn "Docker Desktop detected but not accessible from WSL"
            echo ""
            echo "Enable WSL integration in Docker Desktop:"
            echo "  1. Open Docker Desktop"
            echo "  2. Settings → Resources → WSL Integration"
            echo "  3. Enable integration for your WSL distro"
            echo "  4. Restart WSL: wsl --shutdown"
            echo ""
            exit 1
        fi
        
        log "Installing Docker CE in WSL..."
        
        OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
        CODENAME=$(lsb_release -cs)
        
        # Add Docker GPG key
        sudo mkdir -p /etc/apt/keyrings
        sudo rm -f /etc/apt/keyrings/docker.gpg
        curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update -qq
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        
        # Try to start Docker (may fail without systemd)
        if command -v systemctl &> /dev/null && systemctl is-system-running &> /dev/null; then
            sudo systemctl enable docker
            sudo systemctl start docker
        else
            warn "systemd not available - starting Docker manually..."
            sudo dockerd > /var/log/docker.log 2>&1 &
            sleep 5
            
            # Create helper script
            cat > /tmp/start-docker.sh << 'SCRIPT'
#!/bin/bash
if ! pgrep -x "dockerd" > /dev/null; then
    sudo dockerd > /var/log/docker.log 2>&1 &
    sleep 3
fi
SCRIPT
            sudo mv /tmp/start-docker.sh /usr/local/bin/start-docker.sh
            sudo chmod +x /usr/local/bin/start-docker.sh
            
            echo ""
            warn "Add this to your ~/.bashrc to auto-start Docker:"
            echo '  echo "Starting Docker..." && /usr/local/bin/start-docker.sh'
        fi
        
        NEED_RELOGIN=true
    fi
    
    # Install Containerlab
    if ! check_containerlab; then
        log "Installing Containerlab..."
        bash -c "$(curl -sL https://get.containerlab.dev)"
    fi
    
    # Install SNMP tools
    sudo apt-get install -y snmp net-tools 2>/dev/null || true
}

# ==========================================
# Main
# ==========================================
main() {
    echo ""
    echo "=========================================="
    echo "   OSPF Lab Prerequisites Installer"
    echo "   Supports: Linux, macOS, WSL"
    echo "=========================================="
    echo ""
    
    NEED_RELOGIN=false
    
    # DETECT PLATFORM FIRST!
    detect_platform
    
    # Handle unsupported platforms
    if [ "$PLATFORM" = "windows" ]; then
        error "Native Windows is not supported. Please use WSL 2."
        echo "Install WSL: wsl --install"
        exit 1
    fi
    
    if [ "$PLATFORM" = "unknown" ]; then
        error "Unknown platform. Cannot proceed."
        exit 1
    fi
    
    # Run platform-specific installation
    case "$PLATFORM" in
        macos)
            install_macos
            ;;
        debian|linux)
            install_debian
            ;;
        wsl)
            install_wsl
            ;;
        rhel)
            error "RHEL/CentOS not fully supported yet."
            echo "Please install Docker and Containerlab manually."
            exit 1
            ;;
    esac
    
    # ==========================================
    # Verification
    # ==========================================
    echo ""
    echo "=========================================="
    echo "       VERIFICATION RESULTS"
    echo "=========================================="
    
    # Docker
    if docker info &> /dev/null 2>&1; then
        success "Docker: $(docker --version)"
    else
        warn "Docker: installed but not accessible yet"
    fi
    
    # Containerlab
    if command -v containerlab &> /dev/null; then
        success "Containerlab: $(containerlab version 2>/dev/null | grep version | head -1)"
    else
        error "Containerlab: NOT FOUND"
    fi
    
    # jq
    if command -v jq &> /dev/null; then
        success "jq: $(jq --version)"
    fi
    
    # ==========================================
    # Next Steps
    # ==========================================
    echo ""
    echo "=========================================="
    echo "       NEXT STEPS"
    echo "=========================================="
    
    if [ "$NEED_RELOGIN" = true ]; then
        echo ""
        echo -e "${RED}IMPORTANT: Log out and log back in${NC}"
        echo "This is required for Docker group permissions."
        echo ""
        echo "Or run this command to apply immediately:"
        echo "  newgrp docker"
    fi
    
    if [ "$PLATFORM" = "macos" ]; then
        echo ""
        echo "macOS Notes:"
        echo "  - Ensure Docker Desktop has enough resources:"
        echo "    Docker Desktop → Settings → Resources"
        echo "    Recommended: 4+ CPUs, 8GB+ RAM"
    fi
    
    if [ "$PLATFORM" = "wsl" ]; then
        echo ""
        echo "WSL Notes:"
        echo "  - Ensure you're using WSL 2: wsl -l -v"
        echo "  - If Docker isn't starting, add to ~/.bashrc:"
        echo "    /usr/local/bin/start-docker.sh"
    fi
    
    echo ""
    echo "To verify Docker is working:"
    echo "  docker run hello-world"
    echo ""
}

main "$@"
