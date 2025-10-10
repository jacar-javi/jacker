#!/usr/bin/env bash
#
# Script: 03-setup_ufw.sh
# Description: Configure UFW (Uncomplicated Firewall) with security rules
# Usage: ./03-setup_ufw.sh
# Requirements: .env file must exist, sudo access
# Note: SSH access is configured based on UFW_ALLOW_SSH to prevent lockout
#

set -euo pipefail

cd "$(dirname "$0")"

# Check if .env exists
if [ ! -f ../.env ]; then
    echo "ERROR: .env file not found. Please run setup.sh first."
    exit 1
fi

source ../.env

echo "=== UFW Firewall Setup ==="

# Install ufw (if not installed)
if ! command -v ufw &> /dev/null; then
    echo "Installing UFW..."
    sudo apt-get update &> /dev/null
    sudo apt-get install ufw -y &> /dev/null
else
    echo "UFW already installed"
fi

echo ""
echo "WARNING: This will reset all existing UFW rules!"
echo "SSH access will be configured for: $UFW_ALLOW_SSH"
echo ""
echo "NOTE: UFW setup is optional. You can configure the firewall manually later."
read -r -p "Continue with UFW configuration? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        echo "Proceeding with UFW configuration..."
    ;;
    *)
        echo ""
        echo "UFW configuration skipped."
        echo "You can configure UFW manually later by running:"
        echo "  sudo ./assets/03-setup_ufw.sh"
        echo ""
        exit 0
    ;;
esac

# Reset and configure basic ufw rules
echo "Resetting UFW rules..."
sudo ufw --force disable &> /dev/null
sudo ufw --force reset &> /dev/null

echo "Setting default policies..."
sudo ufw default deny incoming &> /dev/null
sudo ufw default allow outgoing &> /dev/null

# Configure SSH access first to prevent lockout
echo "Configuring SSH access..."
if [ -n "$UFW_ALLOW_SSH" ]; then
    for i in ${UFW_ALLOW_SSH//,/ }; do
        i=$(echo "$i" | xargs) # trim whitespace
        if [ -n "$i" ]; then
            echo "  Allowing SSH from: $i"
            sudo ufw allow from "$i" to any port 22 comment 'SSH access' &> /dev/null
        fi
    done
else
    echo "WARNING: No SSH allow rules configured. You may be locked out!"
    read -r -p "Allow SSH from anywhere? [y/N] " response
    case $response in
        [yY][eE][sS]|[yY])
            sudo ufw limit 22/tcp comment 'SSH with rate limiting' &> /dev/null
        ;;
    esac
fi

# Allow from specific networks/IPs
if [ -n "$UFW_ALLOW_FROM" ]; then
    echo "Configuring allow-from rules..."
    for i in ${UFW_ALLOW_FROM//,/ }; do
        i=$(echo "$i" | xargs) # trim whitespace
        if [ -n "$i" ]; then
            echo "  Allowing all traffic from: $i"
            sudo ufw allow from "$i" &> /dev/null
        fi
    done
fi

# Allow specific ports
if [ -n "$UFW_ALLOW_PORTS" ]; then
    echo "Configuring port access rules..."
    for i in ${UFW_ALLOW_PORTS//,/ }; do
        i=$(echo "$i" | xargs) # trim whitespace
        if [ -n "$i" ]; then
            echo "  Allowing port: $i"
            sudo ufw allow "$i" &> /dev/null
        fi
    done
fi

# Enable UFW
echo "Enabling UFW..."
sudo ufw --force enable

echo ""
echo "=== UFW Status ==="
sudo ufw status verbose

echo ""
echo "UFW configuration completed successfully."
echo "IMPORTANT: Verify you can still access SSH before closing this session!"
echo ""
