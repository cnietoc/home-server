#!/usr/bin/env bash
set -euo pipefail

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️${NC} $*"
}

# Verify the script is running on Ubuntu
check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot determine the operating system"
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        error "This script is designed for Ubuntu. Detected system: $ID"
        exit 1
    fi

    log "✅ Ubuntu detected: $VERSION"
}

# Verify sudo permissions
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root. Recommended to run as a normal user with sudo."
    fi

    if ! sudo -v >/dev/null 2>&1; then
        error "This script requires sudo permissions"
        exit 1
    fi

    log "✅ sudo permissions verified"
}

# Check if Docker is already installed
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        info "Docker is already installed: version $docker_version"

        # Check if the service is running
        if sudo systemctl is-active --quiet docker; then
            info "Docker service is running"
        else
            warn "Docker service is not running, starting it..."
            sudo systemctl start docker
            sudo systemctl enable docker
        fi

        return 0
    else
        return 1
    fi
}

# Remove Docker snap if present to avoid conflicts
remove_docker_snap() {
    if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
        warn "Docker snap detected. Removing to avoid conflicts..."
        sudo snap remove docker
        log "✅ Docker snap removed"
    else
        info "No Docker snap installation found"
    fi
}

# Install Docker
install_docker() {
    if check_docker_installed; then
        return 0
    fi

    log "🐳 Installing Docker..."

    # Remove Docker snap first
    remove_docker_snap

    # Remove old versions if present
    log "Removing old Docker versions..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Add official Docker repository
    log "Setting up official Docker repository..."

    # Check if GPG key already exists
    local gpg_keyring="/usr/share/keyrings/docker-archive-keyring.gpg"
    if [[ ! -f "$gpg_keyring" ]]; then
        log "Downloading Docker GPG key..."
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$gpg_keyring"
        log "✅ Docker GPG key installed"
    else
        info "Docker GPG key already exists"
    fi

    # Check if repository is already configured
    local docker_list="/etc/apt/sources.list.d/docker.list"
    if [[ ! -f "$docker_list" ]] || ! grep -q "download.docker.com" "$docker_list"; then
        log "Adding Docker repository..."
        echo "deb [arch=$(dpkg --print-architecture) signed-by=$gpg_keyring] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee "$docker_list" > /dev/null
        log "✅ Docker repository configured"
    else
        info "Docker repository is already configured"
    fi

    # Update package list with the new repository
    sudo apt-get update

    # Install Docker Engine
    log "Installing Docker Engine, CLI and containerd..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    log "✅ Docker installed successfully"
}

# Configure Docker for the current user
configure_docker_user() {
    local current_user=$(whoami)

    if [[ "$current_user" == "root" ]]; then
        warn "Running as root, skipping docker group configuration"
        return 0
    fi

    log "👤 Configuring Docker for user: $current_user"

    # Create docker group if it doesn't exist
    if ! getent group docker >/dev/null; then
        sudo groupadd docker
        log "docker group created"
    fi

    # Add user to docker group if not already a member
    if groups "$current_user" | grep -q docker; then
        info "User $current_user is already in the docker group"
    else
        sudo usermod -aG docker "$current_user"
        log "User $current_user added to the docker group"
        warn "⚠️ You will need to log out and back in for the changes to take effect"
        warn "   Or run: newgrp docker"
    fi
}

# Verify Docker installation
verify_docker() {
    log "🔍 Verifying Docker installation..."

    # Check docker command
    if ! command -v docker >/dev/null 2>&1; then
        error "Docker is not in PATH"
        return 1
    fi

    # Check service
    if ! sudo systemctl is-active --quiet docker; then
        error "Docker service is not running"
        return 1
    fi

    # Verify basic functionality
    if sudo docker run --rm hello-world >/dev/null 2>&1; then
        log "✅ Docker is working correctly"
    else
        error "Docker is installed but not working correctly"
        return 1
    fi

    # Show versions
    local docker_version=$(docker --version)
    local compose_version=$(docker compose version 2>/dev/null || echo "Docker Compose not available")

    log "📋 Installed versions:"
    log "   $docker_version"
    log "   $compose_version"
}

# Show final information
show_final_info() {
    log "🎉 Installation completed successfully!"
    echo ""
    log "📋 What was installed:"
    log "   ✅ Docker Engine and Docker Compose"
    echo ""
    warn "⚠️ IMPORTANT: Restart your SSH session for the docker group changes to take effect"
    log "  Or run: newgrp docker"
    echo ""
    log "🚀 You can verify the installation by running: docker run hello-world"
}

# Help
show_help() {
    cat << EOF
Usage: $0 [options]

DESCRIPTION:
  Installs Docker and Docker Compose on Ubuntu Server.
  The script is idempotent (safe to run multiple times).

OPTIONS:
  --help             Show this help

EXAMPLES:
  $0                       # Install Docker

PREREQUISITES:
  - Ubuntu Server (18.04 or later)
  - User with sudo permissions
  - Internet connection

EOF
}

# Main function
main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log "🚀 Starting Docker installation on Ubuntu Server..."
    echo ""

    check_ubuntu
    check_sudo

    install_docker
    configure_docker_user
    verify_docker

    show_final_info
}

trap 'error "Installation interrupted"; exit 130' INT TERM

main "$@"
