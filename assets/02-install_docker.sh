#!/usr/bin/env bash
#
# Script: 02-install_docker.sh
# Description: Install Docker Engine, CLI, and plugins with security best practices
# Usage: ./02-install_docker.sh
# Requirements: .env file must exist, sudo access, Ubuntu/Debian system
#

set -euo pipefail

cd "$(dirname "$0")"

# Check if .env exists
if [ ! -f ../.env ]; then
    echo "ERROR: .env file not found. Please run setup.sh first."
    exit 1
fi

source ../.env

echo "=== Docker Installation ==="

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "Docker is already installed: $DOCKER_VERSION"
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

echo "Installing prerequisites..."
sudo apt-get update &> /dev/null
sudo apt-get install ca-certificates curl -y &> /dev/null

echo "Adding Docker's official GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings &> /dev/null
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

# Verify the download succeeded
if [ ! -s /etc/apt/keyrings/docker.asc ]; then
    echo "ERROR: Failed to download Docker GPG key"
    exit 1
fi

sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "Adding Docker repository..."
sudo truncate -s 0 /etc/apt/sources.list.d/docker.list
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Installing Docker packages..."
sudo apt-get update &> /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y &> /dev/null

echo "Configuring Docker..."

# Add current user to docker group
sudo usermod -aG docker "$USER"
echo "User $USER added to docker group"

# Configure log rotation for containers
if [ -f templates/docker-daemon.json ]; then
    sudo cp templates/docker-daemon.json /etc/docker/daemon.json
    sudo chown root:root /etc/docker/daemon.json
    sudo chmod 644 /etc/docker/daemon.json
    echo "Docker daemon configured with log rotation"
else
    echo "WARNING: docker-daemon.json template not found"
fi

# Configure docker to run on boot
sudo systemctl enable docker.service &> /dev/null
sudo systemctl enable containerd.service &> /dev/null

# Restart Docker to apply configuration
sudo systemctl restart docker.service

echo ""
echo "Docker installation completed successfully."
echo "NOTE: You need to log out and back in for group changes to take effect."
echo ""
