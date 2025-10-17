#!/usr/bin/env bash
# Quick resource tuning script
# This is a standalone helper for applying resource optimization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="${PROJECT_DIR}/assets/lib"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# Check if running from project directory
if [[ ! -f "${PROJECT_DIR}/docker-compose.yml" ]]; then
    error "Not in Jacker project directory"
    error "Please run this script from: ${PROJECT_DIR}"
    exit 1
fi

# Check if .env exists
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    error "No .env file found"
    error "Please run 'jacker init' first"
    exit 1
fi

# Source resources library
if [[ ! -f "${LIB_DIR}/resources.sh" ]]; then
    error "Resources library not found at: ${LIB_DIR}/resources.sh"
    exit 1
fi

# shellcheck source=/dev/null
source "${LIB_DIR}/resources.sh"

info "Analyzing system capabilities..."
echo ""

# Apply tuning
if apply_resource_tuning "${PROJECT_DIR}/docker-compose.override.yml"; then
    echo ""
    success "Resource tuning complete!"
    echo ""
    info "The docker-compose.override.yml file has been updated with optimized"
    info "resource allocations based on your system capabilities."
    echo ""
    warn "Changes will take effect after restarting services"
    echo ""
    echo "To apply changes now, run:"
    echo "  cd ${PROJECT_DIR}"
    echo "  docker compose restart"
    echo ""
    echo "Or use the jacker CLI:"
    echo "  ./jacker restart"
else
    error "Resource tuning failed"
    exit 1
fi
