#!/bin/bash
# Disable OAuth authentication for testing purposes
# WARNING: This removes security - only use for testing/development!

set -e

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine Jacker root directory
# If script is in assets/ subdirectory, go up one level
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi

cd "$JACKER_DIR" || exit 1

echo "=== Disabling OAuth for Testing ==="
echo ""
echo "⚠️  WARNING: This removes OAuth authentication!"
echo "   Only use this for local testing/development."
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Creating backup of compose files..."
BACKUP_DIR=".backups/compose-oauth-disabled-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r compose/*.yml "$BACKUP_DIR/"

echo "Disabling OAuth on services..."

# Find all compose files with OAuth middleware
COMPOSE_FILES=$(grep -l "chain-oauth@file" compose/*.yml 2>/dev/null || true)

if [ -z "$COMPOSE_FILES" ]; then
    echo "No OAuth-protected services found!"
    exit 0
fi

COUNT=0
for file in $COMPOSE_FILES; do
    SERVICE=$(basename "$file" .yml)
    echo "  - $SERVICE"

    # Replace chain-oauth with chain-no-auth
    sed -i 's/middlewares=chain-oauth@file/middlewares=chain-no-auth@file/g' "$file"

    COUNT=$((COUNT + 1))
done

echo ""
echo "✓ Modified $COUNT service(s)"

# Check if chain-no-auth middleware exists
if [ ! -f "config/traefik/rules/chain-no-auth.yml" ]; then
    echo ""
    echo "Creating chain-no-auth middleware..."

    cat > config/traefik/rules/chain-no-auth.yml <<'EOF'
http:
  middlewares:
    # OAuth-free chain for testing/development
    # Apply with: middlewares=chain-no-auth@file
    chain-no-auth:
      chain:
        middlewares:
          - middlewares-traefik-bouncer  # CrowdSec IPS protection (kept)
          - rate-limit-enhanced@file     # Enhanced rate limiting (kept)
          - security-headers@file        # Security headers (kept)
          - request-size-limit@file      # Prevent large payload attacks (kept)
          # OAuth removed for testing
          - middlewares-compress         # Compression
EOF

    echo "✓ Created chain-no-auth middleware"
fi

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Add local DNS entries to /etc/hosts:"
echo ""
echo "   127.0.0.1 grafana.mybox.example.com"
echo "   127.0.0.1 portainer.mybox.example.com"
echo "   127.0.0.1 prometheus.mybox.example.com"
echo "   127.0.0.1 alertmanager.mybox.example.com"
echo "   127.0.0.1 loki.mybox.example.com"
echo "   127.0.0.1 homepage.mybox.example.com"
echo "   127.0.0.1 vscode.mybox.example.com"
echo ""
echo "2. Restart services:"
echo ""
echo "   make down"
echo "   make install"
echo ""
echo "3. Access services in browser:"
echo ""
echo "   http://grafana.mybox.example.com"
echo "   http://portainer.mybox.example.com"
echo "   etc."
echo ""
echo "⚠️  Remember: This is for testing only!"
echo "   For production, configure OAuth properly (see TROUBLESHOOTING_404_ERRORS.md)"
echo ""

# Offer to add hosts entries automatically (if running as root)
if [ "$EUID" -eq 0 ]; then
    echo ""
    read -p "Add /etc/hosts entries automatically? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        HOSTS_ENTRIES="
# Jacker local testing (added by disable-oauth-for-testing.sh)
127.0.0.1 grafana.mybox.example.com
127.0.0.1 portainer.mybox.example.com
127.0.0.1 prometheus.mybox.example.com
127.0.0.1 alertmanager.mybox.example.com
127.0.0.1 loki.mybox.example.com
127.0.0.1 homepage.mybox.example.com
127.0.0.1 vscode.mybox.example.com
127.0.0.1 oauth.mybox.example.com
"
        # Check if entries already exist
        if grep -q "Jacker local testing" /etc/hosts 2>/dev/null; then
            echo "Entries already exist in /etc/hosts"
        else
            echo "$HOSTS_ENTRIES" >> /etc/hosts
            echo "✓ Added entries to /etc/hosts"
        fi
    fi
fi

echo ""
echo "To restore OAuth protection later, restore from backup:"
echo "  cp .backups/compose-oauth-disabled-*/compose/*.yml compose/"
echo ""
