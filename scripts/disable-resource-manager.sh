#!/bin/bash
# ====================================================================
# Disable Resource Manager
# ====================================================================
# Removes the resource manager service from docker-compose.yml

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if resource manager exists
if ! grep -q "compose/resource-manager.yml" "$COMPOSE_FILE"; then
    log_warn "Resource Manager is not enabled in docker-compose.yml"
    exit 0
fi

log_info "Removing Resource Manager from docker-compose.yml..."

# Stop the service if running
if docker ps --format '{{.Names}}' | grep -q "^resource-manager$"; then
    log_info "Stopping resource-manager service..."
    docker-compose stop resource-manager
    docker-compose rm -f resource-manager
    log_success "Service stopped and removed"
fi

# Backup docker-compose.yml
cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Backup created: $COMPOSE_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Remove from include section
sed -i '/compose\/resource-manager.yml/d' "$COMPOSE_FILE"
log_success "Removed resource-manager.yml from include section"

# Clean up empty include section if needed
if grep -A1 "^include:" "$COMPOSE_FILE" | grep -q "^$"; then
    sed -i '/^include:$/,+1d' "$COMPOSE_FILE"
    log_success "Cleaned up empty include section"
fi

echo ""
log_success "Resource Manager has been disabled!"
echo ""
echo "To re-enable later:"
echo "   ${BLUE}./scripts/enable-resource-manager.sh${NC}"
echo ""

exit 0
