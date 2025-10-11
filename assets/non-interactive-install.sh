#!/usr/bin/env bash
#
# non-interactive-install.sh - Non-interactive Jacker installation
# This script installs Jacker using values from a backup .env file
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JACKER_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error() { echo -e "${RED}✗ $*${NC}" >&2; }
success() { echo -e "${GREEN}✓ $*${NC}"; }
info() { echo -e "${BLUE}ℹ $*${NC}"; }
warning() { echo -e "${YELLOW}⚠ $*${NC}"; }

# Check if backup .env file is provided
if [ $# -eq 0 ]; then
    error "Usage: $0 <backup-env-file>"
    error "Example: $0 ~/jacker-env-backup-20251011-205649"
    exit 1
fi

BACKUP_ENV="$1"

if [ ! -f "$BACKUP_ENV" ]; then
    error "Backup .env file not found: $BACKUP_ENV"
    exit 1
fi

info "Using backup .env from: $BACKUP_ENV"

# Copy backup to .env
cp "$BACKUP_ENV" "$JACKER_ROOT/.env"
success "Restored .env file"

# Source the .env file to get all variables
set -a
# shellcheck source=/dev/null
source "$JACKER_ROOT/.env"
set +a

info "Loaded configuration:"
info "  Domain: $PUBLIC_FQDN"
info "  Let's Encrypt: $LETSENCRYPT_EMAIL"
info "  OAuth: ${OAUTH_CLIENT_ID:0:20}..."

# Now run the installation without the configuration prompts
cd "$JACKER_ROOT"

# Source libraries
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=assets/lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=assets/lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"

# Initialize logging
init_logging

# Banner
echo ""
echo "     ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ "
echo "     ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗"
echo "     ██║███████║██║     █████╔╝ █████╗  ██████╔╝"
echo "██   ██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗"
echo "╚█████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║  ██║"
echo " ╚════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
echo ""
echo "       Docker Stack Management Platform v2.0.0"
echo ""
echo "       NON-INTERACTIVE INSTALLATION"
echo ""

# Create configuration from existing .env
info "Creating configuration files..."
setup_traefik
setup_crowdsec
setup_oauth
setup_monitoring

# Run installation
info "Starting system installation..."

# System tuning
tune_system

# Install Docker if needed
install_docker

# Configure firewall
configure_firewall

# Install system packages
install_packages

# Start services
info "Starting Jacker services..."
cd_jacker_root
start_services

# Wait for critical services
wait_for_postgresql
ensure_crowdsec_database
register_crowdsec_bouncers

# Install CrowdSec firewall bouncer
install_crowdsec_firewall_bouncer

# Install systemd services
if [ -d "$SCRIPT_DIR/templates" ]; then
    local service_files=(
        "jacker-compose.service"
        "jacker-compose-reload.service"
        "jacker-compose-reload.timer"
    )

    for file in "${service_files[@]}"; do
        if [ -f "$SCRIPT_DIR/templates/$file.template" ]; then
            envsubst < "$SCRIPT_DIR/templates/${file}.template" > "/tmp/$file"
            sudo mv "/tmp/$file" "/etc/systemd/system/"
        fi
    done

    sudo systemctl daemon-reload
    sudo systemctl enable --now jacker-compose.service jacker-compose-reload.timer || true
fi

echo ""
success "Installation complete!"
echo ""
info "Access your services:"
echo "  • Traefik:   https://traefik.$PUBLIC_FQDN"
echo "  • Portainer: https://portainer.$PUBLIC_FQDN"
echo "  • Grafana:   https://grafana.$PUBLIC_FQDN"
echo ""
info "Useful commands:"
echo "  • Check service health: make health"
echo "  • View logs: make logs"
echo ""
