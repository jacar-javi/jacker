#!/usr/bin/env bash
#
# Script: 02-install_docker-multiplatform.sh
# Description: Install Docker Engine with multi-platform support (Ubuntu, Debian, Rocky, AlmaLinux, ARM64, x86_64)
# Usage: ./02-install_docker-multiplatform.sh
# Requirements: sudo access, supported Linux distribution
#

set -euo pipefail

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Docker Installation (Multi-Platform) ===${NC}"

# Detect OS and architecture
if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
    OS_CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}ERROR: Cannot detect OS. /etc/os-release not found.${NC}"
    exit 1
fi

ARCH=$(uname -m)
case $ARCH in
    x86_64)
        DOCKER_ARCH="amd64"
        ;;
    aarch64)
        DOCKER_ARCH="arm64"
        ;;
    armv7l)
        DOCKER_ARCH="armhf"
        ;;
    *)
        echo -e "${RED}ERROR: Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Detected:${NC}"
echo "  OS: $OS_ID $OS_VERSION ($OS_CODENAME)"
echo "  Architecture: $ARCH ($DOCKER_ARCH)"

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo -e "${YELLOW}Docker is already installed: $DOCKER_VERSION${NC}"
    read -r -p "Do you want to reinstall Docker? [y/N] " response
    case $response in
        [yY][eE][sS]|[yY])
            echo "Proceeding with Docker installation..."
        ;;
        *)
            echo "Skipping Docker installation."
            exit 0
        ;;
    esac
fi

# Function to install Docker on Debian/Ubuntu
install_docker_debian_ubuntu() {
    local os_path=$1

    echo -e "${BLUE}Installing Docker on Debian/Ubuntu...${NC}"

    # Update package index
    echo "Updating package index..."
    sudo apt-get update

    # Install prerequisites
    echo "Installing prerequisites..."
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    echo "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/${os_path}/gpg -o /etc/apt/keyrings/docker.asc

    if [ ! -s /etc/apt/keyrings/docker.asc ]; then
        echo -e "${RED}ERROR: Failed to download Docker GPG key${NC}"
        exit 1
    fi

    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo "Adding Docker repository..."
    echo \
      "deb [arch=${DOCKER_ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${os_path} \
      ${OS_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker packages
    echo "Installing Docker packages..."
    sudo apt-get update
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
}

# Function to install Docker on RHEL-based systems (Rocky, AlmaLinux, Fedora)
install_docker_rhel() {
    echo -e "${BLUE}Installing Docker on RHEL-based system...${NC}"

    # Remove old versions
    sudo dnf remove -y docker \
                        docker-client \
                        docker-client-latest \
                        docker-common \
                        docker-latest \
                        docker-latest-logrotate \
                        docker-logrotate \
                        docker-engine \
                        podman \
                        runc 2>/dev/null || true

    # Install prerequisites
    echo "Installing prerequisites..."
    sudo dnf install -y dnf-plugins-core

    # Add Docker repository
    echo "Adding Docker repository..."
    sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker packages
    echo "Installing Docker packages..."
    sudo dnf install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Configure SELinux (if enabled)
    if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
        echo "Configuring SELinux for Docker..."
        sudo setsebool -P container_manage_cgroup on 2>/dev/null || true
    fi
}

# Install Docker based on OS
case $OS_ID in
    ubuntu)
        install_docker_debian_ubuntu "ubuntu"
        ;;
    debian)
        install_docker_debian_ubuntu "debian"
        ;;
    raspbian)
        install_docker_debian_ubuntu "debian"
        ;;
    rocky|almalinux)
        install_docker_rhel
        ;;
    fedora)
        install_docker_rhel
        ;;
    *)
        echo -e "${RED}ERROR: Unsupported OS: $OS_ID${NC}"
        echo "Supported: Ubuntu, Debian, Rocky Linux, AlmaLinux, Fedora"
        exit 1
        ;;
esac

echo -e "${BLUE}Configuring Docker...${NC}"

# Add current user to docker group
sudo usermod -aG docker "$USER"
echo -e "${GREEN}✓ User $USER added to docker group${NC}"

# Configure Docker daemon
DOCKER_CONFIG_DIR="/etc/docker"
DOCKER_DAEMON_JSON="$DOCKER_CONFIG_DIR/daemon.json"

sudo mkdir -p "$DOCKER_CONFIG_DIR"

# Create daemon.json with best practices
echo "Configuring Docker daemon..."
sudo tee "$DOCKER_DAEMON_JSON" > /dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323",
  "live-restore": true,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

sudo chown root:root "$DOCKER_DAEMON_JSON"
sudo chmod 644 "$DOCKER_DAEMON_JSON"
echo -e "${GREEN}✓ Docker daemon configured${NC}"

# Configure Docker to start on boot
echo "Enabling Docker service..."
sudo systemctl enable docker.service
sudo systemctl enable containerd.service

# Restart Docker to apply configuration
echo "Restarting Docker service..."
sudo systemctl restart docker.service

# Wait for Docker to start
sleep 2

# Verify installation
echo ""
echo -e "${BLUE}Verifying Docker installation...${NC}"
# Use sudo for verification since user group changes require re-login
if sudo docker version &> /dev/null; then
    DOCKER_VERSION=$(sudo docker --version)
    COMPOSE_VERSION=$(sudo docker compose version)
    echo -e "${GREEN}✓ Docker installed successfully!${NC}"
    echo "  $DOCKER_VERSION"
    echo "  $COMPOSE_VERSION"
else
    echo -e "${RED}✗ Docker installation verification failed${NC}"
    exit 1
fi

# Platform-specific optimizations
echo ""
echo -e "${BLUE}Applying platform-specific optimizations...${NC}"

case $ARCH in
    aarch64)
        echo "ARM64 platform detected"
        # ARM-specific optimizations
        if [ -f /boot/firmware/cmdline.txt ]; then
            # Raspberry Pi
            echo "Raspberry Pi detected - checking cgroup configuration..."
            if ! grep -q "cgroup_memory=1 cgroup_enable=memory" /boot/firmware/cmdline.txt; then
                echo -e "${YELLOW}⚠ cgroup memory not enabled${NC}"
                echo "Run: echo 'cgroup_memory=1 cgroup_enable=memory' | sudo tee -a /boot/firmware/cmdline.txt"
                echo "Then reboot"
            else
                echo -e "${GREEN}✓ cgroup memory enabled${NC}"
            fi
        fi
        ;;
    x86_64)
        echo "x86_64 platform detected"
        # Enable BBR congestion control if available
        if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
            if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
                echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf > /dev/null
                echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf > /dev/null
                sudo sysctl -p > /dev/null 2>&1
                echo -e "${GREEN}✓ BBR congestion control enabled${NC}"
            fi
        fi
        ;;
esac

echo ""
echo -e "${GREEN}=== Docker Installation Complete ===${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} You need to log out and log back in for group changes to take effect."
echo "Or run: newgrp docker"
echo ""
echo "Docker version: $(sudo docker --version)"
echo "Docker Compose version: $(sudo docker compose version)"
echo ""
echo -e "${GREEN}✓ System ready for Jacker installation!${NC}"
