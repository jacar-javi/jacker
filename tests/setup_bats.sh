#!/usr/bin/env bash
#
# setup_bats.sh - Install BATS testing framework
#

set -euo pipefail

BATS_VERSION="v1.10.0"
INSTALL_DIR="/usr/local"

echo "Installing BATS testing framework..."

# Check if BATS is already installed
if command -v bats &> /dev/null; then
    echo "BATS is already installed: $(bats --version)"
    exit 0
fi

# Install BATS Core
echo "Installing bats-core ${BATS_VERSION}..."
git clone --depth 1 --branch "${BATS_VERSION}" https://github.com/bats-core/bats-core.git /tmp/bats-core
cd /tmp/bats-core
sudo ./install.sh "${INSTALL_DIR}"
rm -rf /tmp/bats-core

# Install BATS helper libraries
echo "Installing BATS helper libraries..."

# bats-support
git clone --depth 1 https://github.com/bats-core/bats-support.git /tmp/bats-support
sudo mkdir -p "${INSTALL_DIR}/lib/bats-support"
sudo cp -r /tmp/bats-support/* "${INSTALL_DIR}/lib/bats-support/"
rm -rf /tmp/bats-support

# bats-assert
git clone --depth 1 https://github.com/bats-core/bats-assert.git /tmp/bats-assert
sudo mkdir -p "${INSTALL_DIR}/lib/bats-assert"
sudo cp -r /tmp/bats-assert/* "${INSTALL_DIR}/lib/bats-assert/"
rm -rf /tmp/bats-assert

# bats-file
git clone --depth 1 https://github.com/bats-core/bats-file.git /tmp/bats-file
sudo mkdir -p "${INSTALL_DIR}/lib/bats-file"
sudo cp -r /tmp/bats-file/* "${INSTALL_DIR}/lib/bats-file/"
rm -rf /tmp/bats-file

echo "BATS installation complete!"
echo "Version: $(bats --version)"
echo ""
echo "Run tests with: bats tests/"