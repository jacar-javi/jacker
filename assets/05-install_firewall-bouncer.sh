#!/usr/bin/env bash
#
# Script: 05-install_firewall-bouncer.sh
# Description: Install CrowdSec firewall bouncer (iptables or nftables based on OS)
# Usage: ./05-install_firewall-bouncer.sh
# Requirements: .env file must exist
#

set -euo pipefail

cd "$(dirname "$0")"
source ../.env

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== CrowdSec Firewall Bouncer Installation ===${NC}\n"

# Detect OS version
if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
else
    echo -e "${RED}ERROR: Cannot detect OS. /etc/os-release not found.${NC}"
    exit 1
fi

echo -e "${GREEN}Detected:${NC} $OS_ID $OS_VERSION"

# Determine which firewall backend to use
# Ubuntu 24.04+ and Debian 12+ use nftables by default
USE_NFTABLES=false

case $OS_ID in
    ubuntu)
        if [ "${OS_VERSION%%.*}" -ge 24 ]; then
            USE_NFTABLES=true
        fi
        ;;
    debian)
        if [ "${OS_VERSION%%.*}" -ge 12 ]; then
            USE_NFTABLES=true
        fi
        ;;
    rocky|almalinux|fedora)
        # RHEL-based systems use nftables by default in newer versions
        if [ "${OS_VERSION%%.*}" -ge 9 ]; then
            USE_NFTABLES=true
        fi
        ;;
esac

# Check if nftables is actually in use
if command -v nft &> /dev/null && nft list tables &> /dev/null 2>&1; then
    echo -e "${GREEN}✓ nftables detected and active${NC}"
    USE_NFTABLES=true
elif command -v iptables &> /dev/null; then
    echo -e "${GREEN}✓ iptables detected${NC}"
    USE_NFTABLES=false
else
    echo -e "${YELLOW}⚠ No firewall backend detected, defaulting to iptables${NC}"
    USE_NFTABLES=false
fi

# Download and execute the CrowdSec repository script
TEMP_SCRIPT=$(mktemp)
trap 'rm -f "$TEMP_SCRIPT"' EXIT

echo -e "${BLUE}Downloading CrowdSec repository script...${NC}"
curl -fsSL https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh -o "$TEMP_SCRIPT"

# Verify the script was downloaded successfully
if [ ! -s "$TEMP_SCRIPT" ]; then
    echo -e "${RED}ERROR: Failed to download CrowdSec repository script${NC}"
    exit 1
fi

echo -e "${BLUE}Adding CrowdSec repository...${NC}"
sudo bash "$TEMP_SCRIPT"

# Install appropriate bouncer
if [ "$USE_NFTABLES" = true ]; then
    echo -e "${BLUE}Installing crowdsec-firewall-bouncer-nftables...${NC}"

    sudo apt-get update &> /dev/null

    # Install nftables if not present
    if ! command -v nft &> /dev/null; then
        echo -e "${YELLOW}Installing nftables...${NC}"
        sudo apt-get install -y nftables &> /dev/null
    fi

    # Install nftables bouncer
    if sudo apt-get install -y crowdsec-firewall-bouncer-nftables &> /dev/null; then
        echo -e "${GREEN}✓ crowdsec-firewall-bouncer-nftables installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠ nftables bouncer not available, falling back to iptables${NC}"
        USE_NFTABLES=false
    fi
fi

if [ "$USE_NFTABLES" = false ]; then
    echo -e "${BLUE}Installing crowdsec-firewall-bouncer-iptables...${NC}"

    sudo apt-get update &> /dev/null

    # Install iptables if not present
    if ! command -v iptables &> /dev/null; then
        echo -e "${YELLOW}Installing iptables...${NC}"
        sudo apt-get install -y iptables &> /dev/null
    fi

    # Install iptables bouncer
    if sudo apt-get install -y crowdsec-firewall-bouncer-iptables &> /dev/null; then
        echo -e "${GREEN}✓ crowdsec-firewall-bouncer-iptables installed successfully${NC}"
    else
        echo -e "${RED}ERROR: Failed to install iptables bouncer${NC}"
        exit 1
    fi
fi

# Enable and start the bouncer service
echo -e "${BLUE}Enabling and starting bouncer service...${NC}"
sudo systemctl enable crowdsec-firewall-bouncer
sudo systemctl start crowdsec-firewall-bouncer

# Verify service is running
if systemctl is-active --quiet crowdsec-firewall-bouncer; then
    echo -e "${GREEN}✓ CrowdSec firewall bouncer is running${NC}"
else
    echo -e "${RED}✗ CrowdSec firewall bouncer failed to start${NC}"
    echo -e "${YELLOW}Check logs: sudo journalctl -u crowdsec-firewall-bouncer -n 50${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Firewall Bouncer Installation Complete ===${NC}\n"

if [ "$USE_NFTABLES" = true ]; then
    echo -e "${BLUE}Backend:${NC} nftables"
    echo -e "${BLUE}View rules:${NC} sudo nft list ruleset | grep crowdsec"
else
    echo -e "${BLUE}Backend:${NC} iptables"
    echo -e "${BLUE}View rules:${NC} sudo iptables -L -n | grep CROWDSEC"
fi

echo ""
echo -e "${YELLOW}Note:${NC} The bouncer will automatically sync with CrowdSec decisions"
echo -e "${YELLOW}Check status:${NC} sudo systemctl status crowdsec-firewall-bouncer"
echo ""
