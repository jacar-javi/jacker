#!/usr/bin/env bash
#
# Script: register_bouncers.sh
# Description: Register CrowdSec bouncers with API keys
# Usage: ./register_bouncers.sh
# Requirements: .env file must exist, CrowdSec running, cscli installed
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

source .env

echo "=== Registering CrowdSec Bouncers ==="

# Check if cscli is available
if ! command -v cscli &> /dev/null; then
    echo "ERROR: cscli command not found. Please run setup.sh first."
    exit 1
fi

# Check if CrowdSec is running
if ! docker compose ps crowdsec | grep -q "running"; then
    echo "ERROR: CrowdSec container is not running"
    echo "Please start the stack first: docker compose up -d"
    exit 1
fi

# Register traefik bouncer
echo "Registering traefik-bouncer..."
if cscli bouncers add traefik-bouncer --key "$CROWDSEC_TRAEFIK_BOUNCER_API_KEY" 2>&1; then
    echo "✓ Traefik bouncer registered successfully"
else
    echo "⚠ Traefik bouncer may already be registered"
fi

# Register iptables bouncer
echo "Registering iptables-bouncer..."
if cscli bouncers add iptables-bouncer --key "$CROWDSEC_IPTABLES_BOUNCER_API_KEY" 2>&1; then
    echo "✓ IPTables bouncer registered successfully"
else
    echo "⚠ IPTables bouncer may already be registered"
fi

echo ""
echo "Bouncer registration completed."
echo "You can check registered bouncers with: cscli bouncers list"
echo ""

