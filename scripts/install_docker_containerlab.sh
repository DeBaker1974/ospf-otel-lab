#!/bin/bash

# Script: install_docker_containerlab.sh
# Description: Smart installation of Containerlab (and Docker if missing)
# Supports: Linux (Ubuntu/Debian), WSL2, and macOS
# Usage: sudo bash install_docker_containerlab.sh

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}→ $1${NC}"; }

# Detect OS
detect_os() {
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)     OS="Linux";;
        Darwin*)    OS="Mac";;
        *)          OS="UNKNOWN:${unameOut}"
    esac
}

# Check Root (Required for Linux installs, recommended for macOS binary placement)
check_permissions() {
    if [ "$OS" == "Linux" ] && [ "$EUID" -ne 0 ]; then
        print_error "On Linux/WSL, this script must be run as root (sudo)"
        exit 1
    fi
}

install_docker_linux() {
    print_info "Installing Docker Engine on Linux/WSL..."
    
    # 1. Update and install prereqs
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release

    # 2. Add GPG key
    mkdir -p /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    # 3. Add Repo
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # 4. Install
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # 5. Start Service (Skip if WSL systemd is missing)
    if command -v systemctl &> /dev/null; then
        systemctl start docker || print_info "Could not start Docker service (normal for some WSL configs)"
        systemctl enable docker || true
    fi
}

main() {
    detect_os
    check_permissions
    
    print_info "Detected OS: $OS"
    echo ""

    # ============================================
    # STEP 1: DOCKER CHECK
    # ============================================
    print_info "Checking Docker..."
    
    if command -v docker &> /dev/null; then
        print_success "Docker is already installed!"
        docker --version
    else
        if [ "$OS" == "Mac" ]; then
            print_error "Docker is missing on macOS."
            print_error "Please install Docker Desktop manually: https://www.docker.com/products/docker-desktop"
            exit 1
        else
            print_info "Docker not found. Installing..."
            install_docker_linux
            print_success "Docker installed."
        fi
    fi
    echo ""

    # ============================================
    # STEP 2: CONTAINERLAB INSTALLATION
    # ============================================
    print_info "Checking Containerlab..."

    if command -v containerlab &> /dev/null; then
        print_success "Containerlab is already installed."
    else
        print_info "Installing Containerlab..."
        
        # Use the official install script
        # It handles Linux and macOS binary placement automatically
        bash -c "$(curl -sL https://get.containerlab.dev)"
        
        if command -v containerlab &> /dev/null; then
            print_success "Containerlab installed successfully."
        else
            print_error "Containerlab installation failed."
            exit 1
        fi
    fi

    # ============================================
    # SUMMARY
    # ============================================
    echo ""
    echo "================================================"
    print_success "Prerequisites Ready!"
    echo "================================================"
    echo "  OS:           $OS"
    echo "  Docker:       $(docker --version)"
    echo "  Containerlab: $(containerlab version | head -n 1)"
    echo ""
    
    if [ "$OS" == "Linux" ] && [ -n "$SUDO_USER" ]; then
        if ! groups "$SUDO_USER" | grep &>/dev/null "\bdocker\b"; then
            print_info "Adding user $SUDO_USER to docker group..."
            usermod -aG docker "$SUDO_USER"
            print_info "NOTE: You must log out and back in for group changes to take effect."
        fi
    fi
}

main
