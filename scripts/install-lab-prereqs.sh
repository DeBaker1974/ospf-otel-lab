#!/bin/bash

# ==========================================
# OSPF Lab Prerequisites Installer
# Installs: Docker CE and Containerlab
# Platform: Ubuntu/Debian
# ==========================================

set -e # Exit immediately if a command exits with a non-zero status

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# 1. Update and Install Dependencies
log "Updating package lists and installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y curl apt-transport-https ca-certificates software-properties-common gnupg lsb-release

# 2. Install Docker
log "Setting up Docker repository..."

# Detect OS ID (ubuntu or debian) to construct the correct URL
OS_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
if [ -f /etc/apt/keyrings/docker.gpg ]; then
    sudo rm /etc/apt/keyrings/docker.gpg
fi
curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
  ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

log "Installing Docker CE..."
sudo apt-get update -qq
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 3. Configure Docker Permissions
log "Configuring Docker user permissions..."
# Check if group exists, if not create it (usually created by install)
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi

# Add current user to group
sudo usermod -aG docker $USER
success "User $USER added to 'docker' group."

# 4. Install Containerlab
log "Installing Containerlab..."
if command -v containerlab &> /dev/null; then
    log "Containerlab is already installed. Updating..."
fi
# Using the official install script
bash -c "$(curl -sL https://get.containerlab.dev)"

# 5. Verification
echo ""
echo "=========================================="
echo "       VERIFICATION RESULTS"
echo "=========================================="

# Verify Docker
if command -v docker &> /dev/null; then
    DOCKER_VER=$(docker --version)
    success "Docker is installed: $DOCKER_VER"
else
    error "Docker installation failed."
    exit 1
fi

# Verify Containerlab
if command -v containerlab &> /dev/null; then
    CLAB_VER=$(containerlab version | grep "version" | head -1)
    success "Containerlab is installed: $CLAB_VER"
else
    error "Containerlab installation failed."
    exit 1
fi

echo ""
echo "=========================================="
echo "       IMPORTANT NEXT STEPS"
echo "=========================================="
echo -e "${RED}YOU MUST LOG OUT AND LOG BACK IN OR RESTART YOUR SESSION.${NC}"
echo "This is required for the Docker group permissions to take effect."
echo ""
echo "To verify after re-login, run:"
echo "  docker run hello-world"
echo ""
