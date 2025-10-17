#!/bin/bash
# ====================================================================
# Enable Resource Manager
# ====================================================================
# Adds the resource manager service to docker-compose.yml

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
RESOURCE_MANAGER_COMPOSE="$PROJECT_DIR/compose/resource-manager.yml"

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

# Check if resource manager is already in compose
if grep -q "resource-manager:" "$COMPOSE_FILE"; then
    log_warn "Resource Manager already exists in docker-compose.yml"
    echo ""
    echo "To update, remove the service first:"
    echo "  ./scripts/disable-resource-manager.sh"
    exit 0
fi

# Check if resource manager compose file exists
if [ ! -f "$RESOURCE_MANAGER_COMPOSE" ]; then
    log_error "Resource Manager compose file not found: $RESOURCE_MANAGER_COMPOSE"
    exit 1
fi

log_info "Adding Resource Manager to docker-compose.yml..."

# Backup docker-compose.yml
cp "$COMPOSE_FILE" "$COMPOSE_FILE.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Backup created: $COMPOSE_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Add include for resource-manager.yml
if ! grep -q "compose/resource-manager.yml" "$COMPOSE_FILE"; then
    # Check if include section exists
    if grep -q "^include:" "$COMPOSE_FILE"; then
        # Add to existing include section
        sed -i '/^include:/a \  - compose/resource-manager.yml' "$COMPOSE_FILE"
    else
        # Create include section at the top
        echo "include:
  - compose/resource-manager.yml
" | cat - "$COMPOSE_FILE" > temp && mv temp "$COMPOSE_FILE"
    fi
    log_success "Added resource-manager.yml to include section"
fi

# Create data directory
mkdir -p "$PROJECT_DIR/data/resource-manager/logs"
log_success "Created data directory: $PROJECT_DIR/data/resource-manager/logs"

# Display usage information
echo ""
log_success "Resource Manager has been enabled!"
echo ""
echo "Next steps:"
echo ""
echo "1. Build the Resource Manager image:"
echo "   ${BLUE}docker-compose build resource-manager${NC}"
echo ""
echo "2. Start the Resource Manager service:"
echo "   ${BLUE}docker-compose up -d resource-manager${NC}"
echo ""
echo "3. View logs:"
echo "   ${BLUE}docker-compose logs -f resource-manager${NC}"
echo ""
echo "4. Check health:"
echo "   ${BLUE}curl http://localhost:8000/health${NC}"
echo ""
echo "5. Access web interface:"
echo "   ${BLUE}https://resource-manager.\${PUBLIC_FQDN}${NC}"
echo ""
echo "Configuration file:"
echo "   ${BLUE}$PROJECT_DIR/config/resource-manager/config.yml${NC}"
echo ""
echo "Documentation:"
echo "   ${BLUE}$PROJECT_DIR/config/resource-manager/README.md${NC}"
echo ""

exit 0
