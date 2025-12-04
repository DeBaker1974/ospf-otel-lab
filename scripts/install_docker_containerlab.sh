#!/bin/bash

# Script: install_docker_containerlab.sh
# Description: Automated installation of Docker and Containerlab
# Author: Senior Software Engineer
# Usage: sudo bash install_docker_containerlab.sh

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

print_success() {
    print_message "${GREEN}" "✓ $1"
}

print_error() {
    print_message "${RED}" "✗ $1"
}

print_info() {
    print_message "${YELLOW}" "→ $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Main installation function
main() {
    print_info "Starting Docker and Containerlab installation..."
    echo ""

    # Step 1: Update package list
    print_info "Step 1: Updating package list..."
    apt update || { print_error "Failed to update package list"; exit 1; }
    print_success "Package list updated"
    echo ""

    # Step 2: Install required packages
    print_info "Step 2: Installing required packages..."
    apt install -y curl apt-transport-https ca-certificates software-properties-common gnupg lsb-release || {
        print_error "Failed to install required packages"
        exit 1
    }
    print_success "Required packages installed"
    echo ""

    # Step 3: Add Docker's official GPG key
    print_info "Step 3: Adding Docker's official GPG key..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || {
        print_error "Failed to add Docker GPG key"
        exit 1
    }
    print_success "Docker GPG key added"
    echo ""

    # Step 4: Add Docker repository
    print_info "Step 4: Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null || {
        print_error "Failed to add Docker repository"
        exit 1
    }
    print_success "Docker repository added"
    echo ""

    # Step 5: Update package list again
    print_info "Step 5: Updating package list with Docker repository..."
    apt update || { print_error "Failed to update package list"; exit 1; }
    print_success "Package list updated"
    echo ""

    # Step 6: Install Docker
    print_info "Step 6: Installing Docker Engine..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        print_error "Failed to install Docker"
        exit 1
    }
    print_success "Docker installed successfully"
    echo ""

    # Step 7: Add user to docker group
    print_info "Step 7: Adding user to docker group..."
    ACTUAL_USER=${SUDO_USER:-$USER}
    if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
        usermod -aG docker "$ACTUAL_USER" || {
            print_error "Failed to add user to docker group"
            exit 1
        }
        print_success "User '$ACTUAL_USER' added to docker group"
    else
        print_info "Running as root - skipping user group addition"
    fi
    echo ""

    # Step 8: Start and enable Docker service
    print_info "Step 8: Starting and enabling Docker service..."
    systemctl start docker || { print_error "Failed to start Docker"; exit 1; }
    systemctl enable docker || { print_error "Failed to enable Docker"; exit 1; }
    print_success "Docker service started and enabled"
    echo ""

    # Step 9: Verify Docker installation
    print_info "Step 9: Verifying Docker installation..."
    docker --version || { print_error "Docker verification failed"; exit 1; }
    print_success "Docker version: $(docker --version)"
    echo ""

    # Step 10: Install Containerlab
    print_info "Step 10: Installing Containerlab..."
    bash -c "$(curl -sL https://get.containerlab.dev)" || {
        print_error "Failed to install Containerlab"
        exit 1
    }
    print_success "Containerlab installed successfully"
    echo ""

    # Step 11: Verify Containerlab installation
    print_info "Step 11: Verifying Containerlab installation..."
    containerlab version || { print_error "Containerlab verification failed"; exit 1; }
    print_success "Containerlab version: $(containerlab version | head -n 1)"
    echo ""

    # Final summary
    echo "================================================"
    print_success "Installation completed successfully!"
    echo "================================================"
    echo ""
    print_info "Docker version: $(docker --version)"
    print_info "Containerlab version: $(containerlab version | head -n 1)"
    echo ""
    print_info "IMPORTANT: If you added a user to the docker group, you need to:"
    print_info "  1. Log out and log back in, OR"
    print_info "  2. Run 'newgrp docker' in your current terminal"
    echo ""
    print_info "Test your installation with:"
    print_info "  docker run hello-world"
    print_info "  containerlab help"
    echo ""
}

# Check if running as root
check_root

# Run main installation
main

exit 0
