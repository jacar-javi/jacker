#!/usr/bin/env bash
#
# Script: fix-traefik-acme.sh
# Description: Fixes ACME certificate file permissions and creates if missing
# Usage: ./fix-traefik-acme.sh
#

set -euo pipefail

# Change to Jacker root directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Fixing Traefik ACME Certificate File ===${NC}"
echo ""

# Load environment if .env exists
if [ -f .env ]; then
    # shellcheck source=/dev/null
    source .env
else
    echo -e "${RED}ERROR: .env file not found${NC}"
    echo "Please run 'make install' first"
    exit 1
fi

# Set default DATADIR if not set
DATADIR="${DATADIR:-./data}"

# ACME file path
ACME_FILE="$DATADIR/traefik/acme.json"

echo "Checking ACME certificate file: $ACME_FILE"
echo ""

# Create traefik directory if it doesn't exist
if [ ! -d "$DATADIR/traefik" ]; then
    echo -e "${YELLOW}Creating Traefik data directory...${NC}"
    mkdir -p "$DATADIR/traefik"
    echo -e "${GREEN}✓ Created $DATADIR/traefik${NC}"
fi

# Check if ACME file exists
if [ ! -f "$ACME_FILE" ]; then
    echo -e "${YELLOW}ACME file does not exist, creating...${NC}"
    echo '{}' > "$ACME_FILE"
    echo -e "${GREEN}✓ Created $ACME_FILE${NC}"
elif [ ! -s "$ACME_FILE" ]; then
    # File exists but is empty
    echo -e "${YELLOW}ACME file exists but is empty, initializing...${NC}"
    echo '{}' > "$ACME_FILE"
    echo -e "${GREEN}✓ Initialized $ACME_FILE with empty JSON${NC}"
else
    # File exists and has content
    echo -e "${GREEN}✓ ACME file exists and contains data${NC}"

    # Count certificates
    cert_count=$(grep -o '"domain"' "$ACME_FILE" 2>/dev/null | wc -l || echo "0")
    if [ "$cert_count" -gt 0 ]; then
        echo "  Found $cert_count certificate(s)"
    fi
fi

# Check current permissions
current_perms=$(stat -c '%a' "$ACME_FILE" 2>/dev/null || stat -f '%A' "$ACME_FILE" 2>/dev/null || echo "unknown")
echo ""
echo "Current permissions: $current_perms"

# Fix permissions if needed
if [ "$current_perms" != "600" ]; then
    echo -e "${YELLOW}Setting correct permissions (600)...${NC}"
    chmod 600 "$ACME_FILE"
    echo -e "${GREEN}✓ Set permissions to 600${NC}"
else
    echo -e "${GREEN}✓ Permissions are already correct (600)${NC}"
fi

# Verify Traefik can access the file
echo ""
echo "Verifying Traefik access..."

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
    # Check if Traefik container can read the file
    if docker exec traefik test -r /acme.json 2>/dev/null; then
        echo -e "${GREEN}✓ Traefik container can read acme.json${NC}"
    else
        echo -e "${RED}✗ Traefik container cannot read acme.json${NC}"
        echo "  This might indicate a volume mounting issue"
    fi

    # Check if file is properly mounted
    mounted_size=$(docker exec traefik stat -c '%s' /acme.json 2>/dev/null || echo "0")
    local_size=$(stat -c '%s' "$ACME_FILE" 2>/dev/null || stat -f '%z' "$ACME_FILE" 2>/dev/null || echo "0")

    if [ "$mounted_size" = "$local_size" ]; then
        echo -e "${GREEN}✓ File is properly mounted in container${NC}"
    else
        echo -e "${YELLOW}⚠ File sizes don't match (local: $local_size, container: $mounted_size)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Traefik container is not running${NC}"
    echo "  Start Traefik with: make up"
fi

echo ""
echo -e "${GREEN}=== ACME File Fix Complete ===${NC}"
echo ""

# Provide helpful information
echo "Notes:"
echo "• The acme.json file stores Let's Encrypt certificates"
echo "• It must have 600 permissions (owner read/write only)"
echo "• Traefik will automatically request certificates when needed"
echo "• Certificates are valid for 90 days and auto-renew"
echo ""

# Check if we're using staging or production Let's Encrypt
if [ -f "$DATADIR/traefik/traefik.yml" ]; then
    if grep -q "acme-staging" "$DATADIR/traefik/traefik.yml" 2>/dev/null; then
        echo -e "${YELLOW}WARNING: Using Let's Encrypt STAGING environment${NC}"
        echo "  Certificates will not be trusted by browsers"
        echo "  To use production certificates, edit traefik.yml"
    fi
fi

# If Traefik is running, suggest restart if we made changes
if [ "$current_perms" != "600" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
    echo ""
    echo -e "${YELLOW}Recommendation:${NC}"
    echo "  Restart Traefik to ensure changes take effect:"
    echo "  docker restart traefik"
fi