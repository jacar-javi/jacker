#!/usr/bin/env bash

#================================================================
# HEADER
#================================================================
#% DESCRIPTION
#%    Migrate from legacy CrowdSec bouncer to Traefik Plugin
#%
#% USAGE
#%    ./migrate-crowdsec-plugin.sh [OPTIONS]
#%
#% OPTIONS
#%    -h, --help        Display this help message
#%    -c, --check       Check requirements only (don't migrate)
#%    -r, --rollback    Rollback to legacy bouncer
#%
#================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration files
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
TRAEFIK_CONFIG="$PROJECT_ROOT/data/traefik/traefik.yml"
MIDDLEWARE_CONFIG="$PROJECT_ROOT/data/traefik/rules/middlewares.yml"
BACKUP_DIR="$PROJECT_ROOT/backups/crowdsec-migration-$(date +%Y%m%d-%H%M%S)"

#================================================================
# FUNCTIONS
#================================================================

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  CrowdSec Bouncer Migration Tool${NC}"
    echo -e "${BLUE}  Legacy Container → Traefik Plugin${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_requirements() {
    local failed=0

    print_info "Checking requirements..."
    echo ""

    # Check if Traefik supports plugins (v2.3+)
    if docker compose ps traefik &>/dev/null; then
        local traefik_version=$(docker compose exec -T traefik traefik version 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown")
        if [[ "$traefik_version" != "unknown" ]]; then
            print_success "Traefik version: $traefik_version"
        else
            print_warning "Could not determine Traefik version"
        fi
    else
        print_error "Traefik is not running"
        ((failed++))
    fi

    # Check if CrowdSec is running
    if docker compose ps crowdsec &>/dev/null; then
        print_success "CrowdSec is running"
    else
        print_error "CrowdSec is not running"
        ((failed++))
    fi

    # Check if legacy bouncer is configured
    if grep -q "traefik-bouncer.yml" "$COMPOSE_FILE" 2>/dev/null; then
        print_success "Legacy bouncer detected in compose file"
    else
        print_warning "Legacy bouncer not found in compose file"
    fi

    # Check if plugin config already exists
    if [[ -f "$MIDDLEWARE_CONFIG" ]]; then
        if grep -q "crowdsec-bouncer-traefik-plugin" "$MIDDLEWARE_CONFIG" 2>/dev/null; then
            print_warning "Plugin configuration already exists in middlewares.yml"
        fi
    fi

    echo ""

    if [[ $failed -gt 0 ]]; then
        print_error "Requirements check failed. Please fix the issues above."
        return 1
    fi

    print_success "All requirements met!"
    return 0
}

backup_configs() {
    print_info "Creating backup..."

    mkdir -p "$BACKUP_DIR"

    cp "$COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml"
    [[ -f "$TRAEFIK_CONFIG" ]] && cp "$TRAEFIK_CONFIG" "$BACKUP_DIR/traefik.yml"
    [[ -f "$MIDDLEWARE_CONFIG" ]] && cp "$MIDDLEWARE_CONFIG" "$BACKUP_DIR/middlewares.yml"

    print_success "Backup created: $BACKUP_DIR"
}

enable_traefik_plugins() {
    print_info "Enabling Traefik experimental plugins..."

    if [[ ! -f "$TRAEFIK_CONFIG" ]]; then
        print_error "Traefik config not found: $TRAEFIK_CONFIG"
        return 1
    fi

    # Check if experimental already exists
    if grep -q "^experimental:" "$TRAEFIK_CONFIG"; then
        print_warning "Experimental section already exists"
    else
        cat >> "$TRAEFIK_CONFIG" << 'EOF'

# Experimental features for plugins
experimental:
  plugins:
    crowdsec-bouncer-traefik-plugin:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
      version: v1.2.1
EOF
        print_success "Added experimental plugins configuration"
    fi
}

configure_plugin_middleware() {
    print_info "Configuring CrowdSec plugin middleware..."

    # Load CROWDSEC_TRAEFIK_BOUNCER_API_KEY from .env
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        # shellcheck source=/dev/null
        source "$PROJECT_ROOT/.env"
    else
        print_error ".env file not found"
        return 1
    fi

    if [[ -z "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY:-}" ]]; then
        print_error "CROWDSEC_TRAEFIK_BOUNCER_API_KEY not set in .env"
        return 1
    fi

    # Create/update middleware configuration
    cat > "$MIDDLEWARE_CONFIG" << EOF
# CrowdSec Bouncer Traefik Plugin
# https://plugins.traefik.io/plugins/6335346ca4caa9ddeffda116/crowdsec-bouncer-traefik-plugin

http:
  middlewares:
    # CrowdSec plugin middleware
    crowdsec:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          enabled: true
          crowdsecMode: live
          crowdsecLapiKey: ${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}
          crowdsecLapiHost: crowdsec:8080
          crowdsecLapiScheme: http
          crowdsecLapiTLSInsecureVerify: false
          logLevel: info
          updateIntervalSeconds: 60
          defaultDecisionSeconds: 300
          httpTimeoutSeconds: 10

    # Chain with security headers
    chain-crowdsec:
      chain:
        middlewares:
          - crowdsec
          - secure-headers
          - rate-limit

    # Update chain-oauth to include CrowdSec
    chain-oauth:
      chain:
        middlewares:
          - crowdsec
          - secure-headers
          - oauth
EOF

    print_success "Created plugin middleware configuration"
}

update_compose_file() {
    print_info "Updating docker-compose.yml..."

    # Remove legacy bouncer, add plugin note
    sed -i.bak '/traefik-bouncer\.yml/d' "$COMPOSE_FILE"

    # Add comment about plugin
    if ! grep -q "# CrowdSec Plugin configured in Traefik" "$COMPOSE_FILE"; then
        sed -i "/compose\/crowdsec\.yml/a\\  # CrowdSec Plugin configured in Traefik (no separate container needed)" "$COMPOSE_FILE"
    fi

    print_success "Updated docker-compose.yml"
}

restart_services() {
    print_info "Restarting services..."

    # Stop legacy bouncer if running
    docker compose stop traefik-bouncer 2>/dev/null || true
    docker compose rm -f traefik-bouncer 2>/dev/null || true

    # Restart Traefik to load plugin
    docker compose restart traefik

    # Wait for Traefik to be healthy
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if docker compose ps traefik | grep -q "healthy"; then
            print_success "Traefik restarted and healthy"
            return 0
        fi
        ((retries--))
        sleep 2
    done

    print_error "Traefik failed to become healthy"
    return 1
}

verify_migration() {
    print_info "Verifying migration..."

    # Check if Traefik loaded the plugin
    if docker compose logs traefik 2>/dev/null | grep -qi "crowdsec.*plugin"; then
        print_success "CrowdSec plugin loaded in Traefik"
    else
        print_warning "Could not verify plugin loading in Traefik logs"
    fi

    # Check if bouncer is registered
    if docker compose exec -T crowdsec cscli bouncers list 2>/dev/null | grep -q "traefik"; then
        print_success "Bouncer is registered in CrowdSec"
    else
        print_warning "Bouncer not found in CrowdSec"
        print_info "You may need to register it: docker compose exec crowdsec cscli bouncers add traefik-plugin"
    fi

    echo ""
    print_success "Migration completed!"
    echo ""
    print_info "Next steps:"
    echo "  1. Check Traefik logs: docker compose logs traefik"
    echo "  2. Verify bouncer: docker compose exec crowdsec cscli bouncers list"
    echo "  3. Test a request to your services"
    echo "  4. Backup is at: $BACKUP_DIR"
}

rollback() {
    print_warning "Rolling back to legacy bouncer..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory not found. Cannot rollback."
        echo "Please manually restore from: backups/"
        return 1
    fi

    # Restore files
    cp "$BACKUP_DIR/docker-compose.yml" "$COMPOSE_FILE"
    [[ -f "$BACKUP_DIR/traefik.yml" ]] && cp "$BACKUP_DIR/traefik.yml" "$TRAEFIK_CONFIG"
    [[ -f "$BACKUP_DIR/middlewares.yml" ]] && cp "$BACKUP_DIR/middlewares.yml" "$MIDDLEWARE_CONFIG"

    # Restart services
    docker compose up -d

    print_success "Rollback completed!"
}

show_help() {
    sed -n '/^#%/s/^#% \?//p' "$0"
}

#================================================================
# MAIN
#================================================================

main() {
    local check_only=false
    local do_rollback=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -r|--rollback)
                do_rollback=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_header

    if [[ "$do_rollback" == "true" ]]; then
        rollback
        exit 0
    fi

    # Check requirements
    if ! check_requirements; then
        exit 1
    fi

    if [[ "$check_only" == "true" ]]; then
        echo ""
        print_info "Check completed. Run without --check to perform migration."
        exit 0
    fi

    # Confirm migration
    echo ""
    print_warning "This will:"
    echo "  • Remove the legacy traefik-bouncer container"
    echo "  • Configure Traefik to use the CrowdSec plugin"
    echo "  • Update Traefik configuration"
    echo "  • Restart Traefik"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Migration cancelled"
        exit 0
    fi

    # Perform migration
    backup_configs
    enable_traefik_plugins
    configure_plugin_middleware
    update_compose_file
    restart_services
    verify_migration
}

main "$@"
