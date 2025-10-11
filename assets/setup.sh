#!/usr/bin/env bash
#
# setup-new.sh - Simplified Jacker installation script
# This is the refactored version using modular libraries
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source libraries
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=assets/lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=assets/lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"

# ============================================================================
# Installation Modes
# ============================================================================

# Quick setup mode
quick_setup() {
    section "Quick Setup Mode"

    info "This mode gets you running with minimal prompts"
    info "Perfect for development, testing, or quick evaluation"
    echo ""

    # Auto-detect system values
    export PUID=$(id -u)
    export PGID=$(id -g)
    export TZ=$(cat /etc/timezone 2>/dev/null || echo 'UTC')
    export USERDIR="$HOME"
    export DOCKERDIR="$(get_jacker_root)"
    export DATADIR="$(get_data_dir)"

    # Auto-detect hostname
    local detected_hostname=$(hostname -s 2>/dev/null || echo "mybox")
    export HOSTNAME="$detected_hostname"

    # Ask for domain
    local default_domain="${detected_hostname}.localhost"
    export DOMAINNAME=$(prompt_with_default "Enter your Domain Name" "$default_domain")
    export PUBLIC_FQDN="$HOSTNAME.$DOMAINNAME"

    # Use default network configuration
    export LOCAL_IPS="127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12"
    export DOCKER_DEFAULT_SUBNET="192.168.69.0/24"
    export SOCKET_PROXY_SUBNET="192.168.70.0/24"
    export TRAEFIK_PROXY_SUBNET="192.168.71.0/24"

    # Skip OAuth (can be configured later)
    export OAUTH_CLIENT_ID=""
    export OAUTH_CLIENT_SECRET=""
    export OAUTH_SECRET=$(generate_password 16)
    export OAUTH_WHITELIST=""

    # Skip Let's Encrypt (use self-signed)
    export LETSENCRYPT_EMAIL=""

    # PostgreSQL configuration
    export POSTGRES_DB="crowdsec_db"
    export POSTGRES_USER="crowdsec"
    export POSTGRES_PASSWORD=$(generate_password 24)

    # CrowdSec configuration
    export CROWDSEC_API_PORT="8888"
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$(generate_password 32)
    export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$(generate_password 32)
    export CROWDSEC_API_LOCAL_PASSWORD=$(generate_password 24)

    # Show summary
    echo ""
    section "Configuration Summary"
    echo "Hostname:     $HOSTNAME"
    echo "Domain:       $DOMAINNAME"
    echo "Public FQDN:  $PUBLIC_FQDN"
    echo "Timezone:     $TZ"
    echo ""
    warning "OAuth:     Not configured (services will be UNAUTHENTICATED)"
    warning "SSL:       Self-signed certificates will be used"
    echo ""
    info "To configure OAuth later: make reconfigure-oauth"
    info "To configure SSL later:   make reconfigure-ssl"
    echo ""

    if ! confirm_action "Proceed with quick setup?" "Y"; then
        error "Setup cancelled"
        exit 0
    fi

    # Create configuration
    create_configuration
}

# Advanced setup mode
advanced_setup() {
    section "Advanced Setup Mode"

    info "This mode provides full control over all settings"
    echo ""

    # System configuration
    export PUID=$(id -u)
    export PGID=$(id -g)
    export TZ=$(prompt_with_default "Enter your timezone" "$(cat /etc/timezone 2>/dev/null || echo 'UTC')")
    export USERDIR="$HOME"
    export DOCKERDIR="$(get_jacker_root)"
    export DATADIR="$(get_data_dir)"

    # Basic configuration
    subsection "Basic Configuration"

    while true; do
        local hostname=$(prompt_with_default "Enter your Host Name" "$(hostname -s)")
        if validate_hostname "$hostname"; then
            export HOSTNAME="$hostname"
            break
        fi
    done

    while true; do
        local domain=$(prompt_with_default "Enter your Domain Name" "example.com")
        if validate_domain "$domain"; then
            export DOMAINNAME="$domain"
            break
        fi
    done

    export PUBLIC_FQDN="$HOSTNAME.$DOMAINNAME"
    info "Your public FQDN will be: $PUBLIC_FQDN"

    # Network configuration
    subsection "Network Configuration"

    if confirm_action "Use default network configuration?" "Y"; then
        export LOCAL_IPS="127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12"
        export DOCKER_DEFAULT_SUBNET="192.168.69.0/24"
        export SOCKET_PROXY_SUBNET="192.168.70.0/24"
        export TRAEFIK_PROXY_SUBNET="192.168.71.0/24"
    else
        export LOCAL_IPS=$(prompt_with_default "Local IPs (comma separated CIDR)" "127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12")
        export DOCKER_DEFAULT_SUBNET=$(prompt_with_default "Docker Default Subnet" "192.168.69.0/24")
        export SOCKET_PROXY_SUBNET=$(prompt_with_default "Socket Proxy Subnet" "192.168.70.0/24")
        export TRAEFIK_PROXY_SUBNET=$(prompt_with_default "Traefik Proxy Subnet" "192.168.71.0/24")
    fi

    # Firewall configuration
    subsection "Firewall Configuration"

    export UFW_ALLOW_PORTS=$(prompt_with_default "Additional UFW ports to allow" "")
    export UFW_ALLOW_SSH=$(prompt_with_default "Networks/hosts to allow SSH" "any")

    # OAuth configuration
    subsection "OAuth Configuration"

    if confirm_action "Configure OAuth authentication?" "Y"; then
        export OAUTH_CLIENT_ID=$(prompt_with_default "OAuth Client ID" "")
        export OAUTH_CLIENT_SECRET=$(prompt_with_default "OAuth Client Secret" "")
        export OAUTH_SECRET=$(generate_password 16)

        while true; do
            local whitelist=$(prompt_with_default "OAuth whitelist emails (comma separated)" "")
            if [ -z "$whitelist" ] || validate_email "${whitelist%%,*}"; then
                export OAUTH_WHITELIST="$whitelist"
                break
            fi
        done
    else
        export OAUTH_CLIENT_ID=""
        export OAUTH_CLIENT_SECRET=""
        export OAUTH_SECRET=$(generate_password 16)
        export OAUTH_WHITELIST=""
        warning "OAuth skipped - services will be UNAUTHENTICATED"
    fi

    # SSL configuration
    subsection "SSL Configuration"

    if confirm_action "Configure Let's Encrypt SSL?" "Y"; then
        while true; do
            local email=$(prompt_with_default "Let's Encrypt Email" "")
            if validate_email "$email"; then
                export LETSENCRYPT_EMAIL="$email"
                break
            fi
        done
    else
        export LETSENCRYPT_EMAIL=""
        warning "Let's Encrypt skipped - self-signed certificates will be used"
    fi

    # Database configuration
    subsection "Database Configuration"

    export POSTGRES_DB="crowdsec_db"
    export POSTGRES_USER="crowdsec"
    export POSTGRES_PASSWORD=$(generate_password 24)

    info "PostgreSQL Database: $POSTGRES_DB"
    info "PostgreSQL User: $POSTGRES_USER"

    # CrowdSec configuration
    subsection "Security Configuration"

    export CROWDSEC_API_PORT="8888"
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$(generate_password 32)
    export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$(generate_password 32)
    export CROWDSEC_API_LOCAL_PASSWORD=$(generate_password 24)

    info "CrowdSec API keys generated"

    # Create configuration
    create_configuration
}

# ============================================================================
# Configuration Functions
# ============================================================================

# Create configuration files
create_configuration() {
    section "Creating Configuration"

    # Create .env file
    create_env_file

    # Setup services
    setup_traefik
    setup_crowdsec
    setup_oauth
    setup_monitoring

    # Configure systemd services
    configure_systemd_services

    success "Configuration complete!"
}

# Create .env file
create_env_file() {
    subsection "Creating .env file"

    local env_template="$(get_jacker_root)/.env.template"
    local env_file="$(get_jacker_root)/.env"

    if [ -f "$env_template" ]; then
        envsubst < "$env_template" > "$env_file"
        success ".env file created"
    else
        # Create minimal .env if template doesn't exist
        cat > "$env_file" <<EOF
# Jacker Configuration
PUID=$PUID
PGID=$PGID
TZ=$TZ
USERDIR=$USERDIR
DOCKERDIR=$DOCKERDIR
DATADIR=$DATADIR

# Network
HOSTNAME=$HOSTNAME
DOMAINNAME=$DOMAINNAME
PUBLIC_FQDN=$PUBLIC_FQDN
LOCAL_IPS=$LOCAL_IPS

# Docker Networks
DOCKER_DEFAULT_SUBNET=$DOCKER_DEFAULT_SUBNET
SOCKET_PROXY_SUBNET=$SOCKET_PROXY_SUBNET
TRAEFIK_PROXY_SUBNET=$TRAEFIK_PROXY_SUBNET

# OAuth
OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID
OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET
OAUTH_SECRET=$OAUTH_SECRET
OAUTH_WHITELIST=$OAUTH_WHITELIST

# SSL
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# PostgreSQL
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# CrowdSec
CROWDSEC_API_PORT=$CROWDSEC_API_PORT
CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$CROWDSEC_TRAEFIK_BOUNCER_API_KEY
CROWDSEC_IPTABLES_BOUNCER_API_KEY=$CROWDSEC_IPTABLES_BOUNCER_API_KEY
CROWDSEC_API_LOCAL_PASSWORD=$CROWDSEC_API_LOCAL_PASSWORD
EOF
        success ".env file created"
    fi
}

# Configure systemd services
configure_systemd_services() {
    subsection "Configuring systemd services"

    local template_dir="$(get_assets_dir)/templates"
    local service_files=(
        "jacker-compose.service"
        "jacker-compose-reload.service"
        "jacker-compose-reload.timer"
    )

    for file in "${service_files[@]}"; do
        if [ -f "$template_dir/${file}.template" ]; then
            envsubst < "$template_dir/${file}.template" > "$template_dir/$file"
        fi
    done

    success "Systemd services configured"
}

# ============================================================================
# Installation Functions
# ============================================================================

# Run installation
run_installation() {
    section "Running Installation"

    # System tuning
    tune_system

    # Install Docker if needed
    install_docker

    # Configure firewall
    configure_firewall

    # Install system packages
    install_packages

    # Start services
    start_jacker_services

    # Post-installation setup
    post_installation_setup

    success "Installation complete!"
}

# Start Jacker services
start_jacker_services() {
    subsection "Starting Jacker services"

    cd_jacker_root
    start_services

    # Wait for critical services
    wait_for_postgresql
    ensure_crowdsec_database
    register_crowdsec_bouncers

    success "Services started"
}

# Post-installation setup
post_installation_setup() {
    subsection "Post-installation setup"

    # Install CrowdSec firewall bouncer
    install_crowdsec_firewall_bouncer

    # Install systemd services
    if [ -d "$(get_assets_dir)/templates" ]; then
        local service_files=(
            "jacker-compose.service"
            "jacker-compose-reload.service"
            "jacker-compose-reload.timer"
        )

        for file in "${service_files[@]}"; do
            if [ -f "$(get_assets_dir)/templates/$file" ]; then
                sudo mv "$(get_assets_dir)/templates/$file" "/etc/systemd/system/"
            fi
        done

        sudo systemctl daemon-reload
        sudo systemctl enable --now jacker-compose.service jacker-compose-reload.timer
    fi

    success "Post-installation complete"
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Initialize
    cd_jacker_root
    init_logging

    # Show banner
    echo ""
    echo "     ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ "
    echo "     ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗"
    echo "     ██║███████║██║     █████╔╝ █████╗  ██████╔╝"
    echo "██   ██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗"
    echo "╚█████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║  ██║"
    echo " ╚════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo ""
    echo "       Docker Stack Management Platform v${JACKER_VERSION}"
    echo ""

    # Check if .env exists
    if [ -f ".env" ]; then
        warning "Existing .env file detected"
        echo ""
        echo "Choose an option:"
        echo "  1) Reinstall (keep existing values as defaults)"
        echo "  2) Fresh install (backup .env and start from scratch)"
        echo "  3) Cancel"
        echo ""
        read -r -p "Select option [1-3]: " option

        case "$option" in
            1)
                info "Starting reinstall mode..."
                load_env
                ;;
            2)
                backup_file ".env"
                info "Starting fresh installation..."
                ;;
            *)
                error "Installation cancelled"
                exit 0
                ;;
        esac
    fi

    # Select setup mode
    section "Setup Mode Selection"

    echo "Choose your setup mode:"
    echo ""
    echo "  [1] $ROCKET Quick Setup (Recommended for testing)"
    echo "      • Minimal prompts (~2 questions)"
    echo "      • Auto-detect most settings"
    echo "      • Get running in under 1 minute"
    echo ""
    echo "  [2] 🔧 Advanced Setup (Full customization)"
    echo "      • Complete control over all settings"
    echo "      • Configure OAuth, SSL, alerting"
    echo "      • Production-ready configuration"
    echo ""

    while true; do
        read -r -p "Select mode [1/2]: " mode

        case "$mode" in
            1)
                quick_setup
                break
                ;;
            2)
                advanced_setup
                break
                ;;
            *)
                error "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done

    # Run installation
    run_installation

    # Show completion message
    section "Installation Complete!"

    success "Jacker has been successfully installed!"
    echo ""
    echo "Access your services:"
    echo "  • Traefik:   https://traefik.$PUBLIC_FQDN"
    echo "  • Portainer: https://portainer.$PUBLIC_FQDN"
    echo "  • Grafana:   https://grafana.$PUBLIC_FQDN"
    echo ""
    echo "Next steps:"
    echo "  • Check service health: make health"
    echo "  • View logs: make logs"
    echo "  • Configure OAuth: make reconfigure-oauth"
    echo "  • Configure SSL: make reconfigure-ssl"
    echo ""
    success "Enjoy using Jacker!"
}

# Run main function
main "$@"