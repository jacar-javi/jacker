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
# Configuration Setup
# ============================================================================

# Configuration setup mode
setup_configuration() {
    section "Jacker Configuration"

    info "Configure your Jacker installation"
    echo ""

    # System configuration
    export PUID=$(id -u)
    export PGID=$(id -g)
    
    # Use existing TZ if available, otherwise detect
    local default_tz="${TZ:-$(cat /etc/timezone 2>/dev/null || echo 'UTC')}"
    export TZ=$(prompt_with_default "Enter your timezone" "$default_tz")
    
    export USERDIR="$HOME"
    export DOCKERDIR="$(get_jacker_root)"
    export DATADIR="$(get_data_dir)"

    # Basic configuration
    subsection "Basic Configuration"

    while true; do
        # Use existing HOSTNAME if available, otherwise detect
        local default_hostname="${HOSTNAME:-$(hostname -s)}"
        local hostname=$(prompt_with_default "Enter your Host Name" "$default_hostname")
        if validate_hostname "$hostname"; then
            export HOSTNAME="$hostname"
            break
        fi
    done

    while true; do
        # Use existing DOMAINNAME if available, otherwise use example.com
        local default_domain="${DOMAINNAME:-example.com}"
        local domain=$(prompt_with_default "Enter your Domain Name" "$default_domain")
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
        export LOCAL_IPS="${LOCAL_IPS:-127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12}"
        export DOCKER_DEFAULT_SUBNET="${DOCKER_DEFAULT_SUBNET:-192.168.69.0/24}"
        export SOCKET_PROXY_SUBNET="${SOCKET_PROXY_SUBNET:-192.168.70.0/24}"
        export TRAEFIK_PROXY_SUBNET="${TRAEFIK_PROXY_SUBNET:-192.168.71.0/24}"
    else
        export LOCAL_IPS=$(prompt_with_default "Local IPs (comma separated CIDR)" "${LOCAL_IPS:-127.0.0.1/32,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12}")
        export DOCKER_DEFAULT_SUBNET=$(prompt_with_default "Docker Default Subnet" "${DOCKER_DEFAULT_SUBNET:-192.168.69.0/24}")
        export SOCKET_PROXY_SUBNET=$(prompt_with_default "Socket Proxy Subnet" "${SOCKET_PROXY_SUBNET:-192.168.70.0/24}")
        export TRAEFIK_PROXY_SUBNET=$(prompt_with_default "Traefik Proxy Subnet" "${TRAEFIK_PROXY_SUBNET:-192.168.71.0/24}")
    fi

    # Firewall configuration
    subsection "Firewall Configuration"

    export UFW_ALLOW_PORTS=$(prompt_with_default "Additional UFW ports to allow" "${UFW_ALLOW_PORTS:-}")
    export UFW_ALLOW_SSH=$(prompt_with_default "Networks/hosts to allow SSH" "${UFW_ALLOW_SSH:-any}")

    # OAuth configuration
    subsection "OAuth Configuration"

    # Check if OAuth was previously configured
    local oauth_configured=false
    if [ -n "${OAUTH_CLIENT_ID:-}" ] && [ -n "${OAUTH_CLIENT_SECRET:-}" ]; then
        oauth_configured=true
    fi

    if confirm_action "Configure OAuth authentication?" "Y"; then
        export OAUTH_CLIENT_ID=$(prompt_with_default "OAuth Client ID" "${OAUTH_CLIENT_ID:-}")
        export OAUTH_CLIENT_SECRET=$(prompt_with_default "OAuth Client Secret" "${OAUTH_CLIENT_SECRET:-}")
        
        # Reuse existing OAUTH_SECRET if available, otherwise generate new
        if [ -z "${OAUTH_SECRET:-}" ]; then
            export OAUTH_SECRET=$(generate_password 16)
        fi

        while true; do
            local whitelist=$(prompt_with_default "OAuth whitelist emails (comma separated)" "${OAUTH_WHITELIST:-}")
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

    # Check if Let's Encrypt was previously configured
    local letsencrypt_configured=false
    if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
        letsencrypt_configured=true
    fi

    if confirm_action "Configure Let's Encrypt SSL?" "Y"; then
        while true; do
            local email=$(prompt_with_default "Let's Encrypt Email" "${LETSENCRYPT_EMAIL:-}")
            if [ -n "$email" ] && validate_email "$email"; then
                export LETSENCRYPT_EMAIL="$email"
                break
            elif [ -z "$email" ]; then
                warning "Email is required for Let's Encrypt"
            fi
        done
    else
        export LETSENCRYPT_EMAIL=""
        warning "Let's Encrypt skipped - self-signed certificates will be used"
    fi

    # Database configuration
    subsection "Database Configuration"

    export POSTGRES_DB="${POSTGRES_DB:-crowdsec_db}"
    export POSTGRES_USER="${POSTGRES_USER:-crowdsec}"
    
    # Keep existing password if available, otherwise generate new
    if [ -z "${POSTGRES_PASSWORD:-}" ]; then
        export POSTGRES_PASSWORD=$(generate_password 24)
    fi

    info "PostgreSQL Database: $POSTGRES_DB"
    info "PostgreSQL User: $POSTGRES_USER"

    # CrowdSec configuration
    subsection "Security Configuration"

    export CROWDSEC_API_PORT="${CROWDSEC_API_PORT:-8888}"
    
    # Keep existing API keys if available, otherwise generate new
    if [ -z "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY:-}" ]; then
        export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$(generate_password 32)
    fi
    
    if [ -z "${CROWDSEC_IPTABLES_BOUNCER_API_KEY:-}" ]; then
        export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$(generate_password 32)
    fi
    
    if [ -z "${CROWDSEC_API_LOCAL_PASSWORD:-}" ]; then
        export CROWDSEC_API_LOCAL_PASSWORD=$(generate_password 24)
    fi

    info "CrowdSec API keys preserved/generated"

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

    local env_defaults="$(get_jacker_root)/.env.defaults"
    local env_file="$(get_jacker_root)/.env"

    # Start with .env.defaults as base
    if [ -f "$env_defaults" ]; then
        cp "$env_defaults" "$env_file"
        
        # Override with user-provided values using sed
        sed -i "s|^PUID=.*|PUID=$PUID|" "$env_file"
        sed -i "s|^PGID=.*|PGID=$PGID|" "$env_file"
        sed -i "s|^TZ=.*|TZ=$TZ|" "$env_file"
        sed -i "s|^USERDIR=.*|USERDIR=$USERDIR|" "$env_file"
        sed -i "s|^DOCKERDIR=.*|DOCKERDIR=$DOCKERDIR|" "$env_file"
        sed -i "s|^DATADIR=.*|DATADIR=$DATADIR|" "$env_file"
        sed -i "s|^HOSTNAME=.*|HOSTNAME=$HOSTNAME|" "$env_file"
        sed -i "s|^DOMAINNAME=.*|DOMAINNAME=$DOMAINNAME|" "$env_file"
        sed -i "s|^PUBLIC_FQDN=.*|PUBLIC_FQDN=$PUBLIC_FQDN|" "$env_file"
        sed -i "s|^LOCAL_IPS=.*|LOCAL_IPS=$LOCAL_IPS|" "$env_file"
        sed -i "s|^DOCKER_DEFAULT_SUBNET=.*|DOCKER_DEFAULT_SUBNET=$DOCKER_DEFAULT_SUBNET|" "$env_file"
        sed -i "s|^SOCKET_PROXY_SUBNET=.*|SOCKET_PROXY_SUBNET=$SOCKET_PROXY_SUBNET|" "$env_file"
        sed -i "s|^TRAEFIK_PROXY_SUBNET=.*|TRAEFIK_PROXY_SUBNET=$TRAEFIK_PROXY_SUBNET|" "$env_file"
        sed -i "s|^OAUTH_CLIENT_ID=.*|OAUTH_CLIENT_ID=$OAUTH_CLIENT_ID|" "$env_file"
        sed -i "s|^OAUTH_CLIENT_SECRET=.*|OAUTH_CLIENT_SECRET=$OAUTH_CLIENT_SECRET|" "$env_file"
        sed -i "s|^OAUTH_SECRET=.*|OAUTH_SECRET=$OAUTH_SECRET|" "$env_file"
        sed -i "s|^OAUTH_WHITELIST=.*|OAUTH_WHITELIST=$OAUTH_WHITELIST|" "$env_file"
        sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL|" "$env_file"
        sed -i "s|^POSTGRES_DB=.*|POSTGRES_DB=$POSTGRES_DB|" "$env_file"
        sed -i "s|^POSTGRES_USER=.*|POSTGRES_USER=$POSTGRES_USER|" "$env_file"
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" "$env_file"
        sed -i "s|^CROWDSEC_API_PORT=.*|CROWDSEC_API_PORT=$CROWDSEC_API_PORT|" "$env_file"
        sed -i "s|^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.*|CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$CROWDSEC_TRAEFIK_BOUNCER_API_KEY|" "$env_file"
        sed -i "s|^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.*|CROWDSEC_IPTABLES_BOUNCER_API_KEY=$CROWDSEC_IPTABLES_BOUNCER_API_KEY|" "$env_file"
        sed -i "s|^CROWDSEC_API_LOCAL_PASSWORD=.*|CROWDSEC_API_LOCAL_PASSWORD=$CROWDSEC_API_LOCAL_PASSWORD|" "$env_file"
        
        success ".env file created from defaults with user overrides"
    else
        error ".env.defaults file not found!"
        return 1
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

    # Run configuration setup
    setup_configuration

    # Run installation
    run_installation

    # Show completion message
    section "Installation Complete!"

    success "Jacker has been successfully installed!"
    echo ""
    
    # Check if using placeholder domain
    if [[ "$DOMAINNAME" == "example.com" ]] || [[ "$DOMAINNAME" == *".localhost" ]] || [[ "$DOMAINNAME" == "localhost" ]]; then
        warning "You are using a test/placeholder domain: $DOMAINNAME"
        echo ""
        echo "This is fine for local testing, but for external access you need:"
        echo "  1. A real domain name (e.g., yourdomain.com)"
        echo "  2. DNS A records pointing to your server's public IP"
        echo "  3. Cloud provider firewall allowing ports 80/443"
        echo ""
        echo "To reconfigure later:"
        echo "  • Update domain: make reconfigure-domain"
        echo "  • Configure SSL: make reconfigure-ssl"
        echo ""
    else
        info "To access services externally, ensure DNS is configured:"
        echo ""
        echo "Required DNS configuration:"
        echo "  1. Add A record: $PUBLIC_FQDN → [your server's public IP]"
        echo "  2. Add wildcard or specific subdomain records"
        echo "  3. Wait 5-30 minutes for DNS propagation"
        echo "  4. Ensure cloud provider firewall allows ports 80/443"
        echo ""
        info "Run diagnostics to verify external access:"
        echo "  make diagnose"
        echo ""
    fi
    
    echo "Access your services:"
    echo "  • Traefik:   https://traefik.$PUBLIC_FQDN"
    echo "  • Portainer: https://portainer.$PUBLIC_FQDN"
    echo "  • Grafana:   https://grafana.$PUBLIC_FQDN"
    echo ""
    echo "Useful commands:"
    echo "  • Check service health: make health"
    echo "  • Run network diagnostics: make diagnose"
    echo "  • View logs: make logs"
    echo "  • Configure OAuth: make reconfigure-oauth"
    echo "  • Configure SSL: make reconfigure-ssl"
    echo ""
    success "Enjoy using Jacker!"
}

# Run main function
main "$@"