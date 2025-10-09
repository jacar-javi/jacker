#!/usr/bin/env bash
#
# Script: 04-install_assets.sh
# Description: Install CrowdSec CLI tool (cscli) for managing CrowdSec
# Usage: ./04-install_assets.sh
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

echo "=== Installing Jacker Assets ==="

# Check if cscli binary exists
if [ ! -f cscli ]; then
    echo "ERROR: cscli binary not found in assets directory"
    echo "Please ensure the cscli binary is present before running this script"
    exit 1
fi

# Verify it's an executable
if ! file cscli | grep -q "executable"; then
    echo "ERROR: cscli is not a valid executable"
    exit 1
fi

echo "Installing cscli to /usr/local/sbin..."
sudo chmod +x cscli
sudo cp cscli /usr/local/sbin/

# Verify installation
if command -v cscli &> /dev/null; then
    CSCLI_VERSION=$(cscli version 2>&1 || echo "unknown")
    echo "cscli installed successfully: $CSCLI_VERSION"
else
    echo "ERROR: cscli installation failed"
    exit 1
fi

echo ""
echo "Asset installation completed successfully."
echo ""
