#!/usr/bin/env bash
#
# Script: 01-tune_system.sh
# Description: Apply system tuning for file handling and performance, then update system
# Usage: ./01-tune_system.sh
# Requirements: .env file must exist, sudo access
#

set -euo pipefail

cd "$(dirname "$0")"

# Check if .env exists
if [ ! -f ../.env ]; then
    echo "ERROR: .env file not found. Please run setup.sh first."
    exit 1
fi

source ../.env

echo "=== System Tuning ==="
echo "Configuring system parameters for production workloads..."

# Apply sysctl tuning for file watching
if ! grep -q "fs.inotify.max_user_watches=" /etc/sysctl.conf; then
    echo "Setting fs.inotify.max_user_watches=262144"
    echo fs.inotify.max_user_watches=262144 | sudo tee -a /etc/sysctl.conf > /dev/null
else
    echo "fs.inotify.max_user_watches already configured"
fi

# Apply VM cache pressure tuning
if ! grep -q "vm.vfs_cache_pressure=" /etc/sysctl.conf; then
    echo "Setting vm.vfs_cache_pressure=50"
    echo vm.vfs_cache_pressure=50 | sudo tee -a /etc/sysctl.conf > /dev/null
else
    echo "vm.vfs_cache_pressure already configured"
fi

# Apply swappiness tuning
if ! grep -q "vm.swappiness=" /etc/sysctl.conf; then
    echo "Setting vm.swappiness=10"
    echo vm.swappiness=10 | sudo tee -a /etc/sysctl.conf > /dev/null
else
    echo "vm.swappiness already configured"
fi

# Apply sysctl changes immediately
echo "Applying sysctl changes..."
sudo sysctl -p > /dev/null

echo ""
echo "=== System Update ==="
echo "Updating system packages (this may take several minutes)..."

sudo apt-get update &> /dev/null || {
    echo "ERROR: Failed to update package lists"
    exit 1
}

sudo apt-get upgrade -y &> /dev/null || {
    echo "ERROR: Failed to upgrade packages"
    exit 1
}

sudo apt-get dist-upgrade -y &> /dev/null || {
    echo "WARNING: dist-upgrade had issues, continuing..."
}

sudo apt-get autoremove -y &> /dev/null

echo ""
echo "System tuning and update completed successfully."
echo ""
