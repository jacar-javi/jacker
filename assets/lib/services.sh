#!/usr/bin/env bash
#
# services.sh - Service management library
# This module handles service-specific configurations and operations
#

# Source common library
# shellcheck source=assets/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================================
# CrowdSec Functions
# ============================================================================

# Setup CrowdSec
setup_crowdsec() {
    section "CrowdSec Setup"

    # Create directories
    ensure_dir "$(get_data_dir)/crowdsec/config/parsers/s02-enrich"
    ensure_dir "$(get_data_dir)/crowdsec/data"

    # Configure CrowdSec for PostgreSQL
    configure_crowdsec_db

    # Register bouncers
    register_crowdsec_bouncers

    success "CrowdSec setup complete"
}

# Configure CrowdSec database
configure_crowdsec_db() {
    subsection "Configuring CrowdSec database"

    local config_file="$(get_data_dir)/crowdsec/config/config.yaml.local"
    local template_file="$(get_assets_dir)/templates/config.yaml.local.template"

    if [ -f "$template_file" ]; then
        create_from_template "$template_file" "$config_file"
    else
        warning "CrowdSec config template not found"
    fi
}

# Register CrowdSec bouncers
register_crowdsec_bouncers() {
    subsection "Registering CrowdSec bouncers"

    # Wait for CrowdSec to be ready
    # CrowdSec health check: start_period=60s + interval=30s × retries=3 = max 150s
    # Add 30s buffer for safety = 180s total
    wait_for_healthy "crowdsec" 180 5

    # Get API keys from environment
    local traefik_key="${CROWDSEC_TRAEFIK_BOUNCER_API_KEY:-}"
    local iptables_key="${CROWDSEC_IPTABLES_BOUNCER_API_KEY:-}"
    local hostname="${HOSTNAME:-$(hostname)}"
    local api_password="${CROWDSEC_API_LOCAL_PASSWORD:-}"

    if [ -n "$traefik_key" ]; then
        info "Registering Traefik bouncer"
        docker_exec crowdsec cscli bouncers add traefik-bouncer --key "$traefik_key" &> /dev/null || true
    fi

    if [ -n "$iptables_key" ]; then
        info "Registering iptables bouncer"
        docker_exec crowdsec cscli bouncers add iptables-bouncer --key "$iptables_key" &> /dev/null || true
    fi

    if [ -n "$api_password" ]; then
        info "Setting local API password"
        docker_exec crowdsec cscli machines add "$hostname" -p "$api_password" --force &> /dev/null || true
    fi

    # Install bash completion
    docker_exec crowdsec cscli completion bash | sudo tee /etc/bash_completion.d/cscli &> /dev/null

    success "Bouncers registered"
}

# Install CrowdSec firewall bouncer
install_crowdsec_firewall_bouncer() {
    subsection "Installing CrowdSec firewall bouncer"

    # Check OS
    local os_info=$(detect_os)
    local os="${os_info%%:*}"

    case "$os" in
        ubuntu|debian)
            curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
            sudo apt-get install -y crowdsec-firewall-bouncer-iptables
            ;;
        centos|rhel|rocky|almalinux)
            curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.rpm.sh | sudo bash
            sudo yum install -y crowdsec-firewall-bouncer-iptables
            ;;
        *)
            warning "Unsupported OS for firewall bouncer: $os"
            return 1
            ;;
    esac

    # Configure firewall bouncer
    local bouncer_config="/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local"
    local template_file="$(get_assets_dir)/templates/crowdsec-firewall-bouncer.yaml.template"

    if [ -f "$template_file" ]; then
        sudo mkdir -p /etc/crowdsec/bouncers
        envsubst < "$template_file" | sudo tee "$bouncer_config" > /dev/null
    fi

    # Enable and start the service
    sudo systemctl enable crowdsec-firewall-bouncer
    sudo systemctl restart crowdsec-firewall-bouncer

    success "Firewall bouncer installed"
}

# ============================================================================
# Traefik Functions
# ============================================================================

# Setup Traefik
setup_traefik() {
    section "Traefik Setup"

    # Create directories
    ensure_dir "$(get_data_dir)/traefik"

    # Create acme.json with correct permissions
    touch "$(get_data_dir)/traefik/acme.json"
    chmod 600 "$(get_data_dir)/traefik/acme.json"

    # Configure Traefik
    configure_traefik

    success "Traefik setup complete"
}

# Configure Traefik
configure_traefik() {
    subsection "Configuring Traefik"

    # Configure logrotate for Traefik
    local template_file="$(get_assets_dir)/templates/traefik.logrotate.template"
    if [ -f "$template_file" ]; then
        envsubst < "$template_file" | sudo tee /etc/logrotate.d/traefik > /dev/null
        sudo chown root:root /etc/logrotate.d/traefik
        sudo chmod 644 /etc/logrotate.d/traefik
    fi

    success "Traefik configured"
}

# ============================================================================
# PostgreSQL Functions
# ============================================================================

# Setup PostgreSQL
setup_postgresql() {
    section "PostgreSQL Setup"

    # Wait for PostgreSQL to be ready
    wait_for_postgresql

    # Ensure crowdsec_db exists
    ensure_crowdsec_database

    success "PostgreSQL setup complete"
}

# Wait for PostgreSQL to be ready
wait_for_postgresql() {
    subsection "Waiting for PostgreSQL"

    local max_attempts=30
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if docker_exec postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" &> /dev/null; then
            success "PostgreSQL is ready"
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    error "PostgreSQL failed to start within 60 seconds"
    return 1
}

# Ensure crowdsec_db database exists
ensure_crowdsec_database() {
    subsection "Ensuring crowdsec_db exists"

    local db_user="${POSTGRES_USER:-postgres}"
    local db_name="${POSTGRES_DB:-postgres}"

    # Check if crowdsec_db exists
    if ! docker_exec postgres psql -U "$db_user" -d "$db_name" -tc "SELECT 1 FROM pg_database WHERE datname='crowdsec_db'" | grep -q 1; then
        info "Creating crowdsec_db database"
        docker_exec postgres psql -U "$db_user" -d "$db_name" -c "CREATE DATABASE crowdsec_db OWNER $db_user;" &> /dev/null || true
    else
        info "crowdsec_db already exists"
    fi
}

# ============================================================================
# OAuth Functions
# ============================================================================

# Setup OAuth
setup_oauth() {
    section "OAuth Setup"

    # Create secrets directory
    ensure_dir "$(get_jacker_root)/secrets"

    # Configure OAuth secret
    configure_oauth_secret

    success "OAuth setup complete"
}

# Configure OAuth secret
configure_oauth_secret() {
    subsection "Configuring OAuth secret"

    local secret_file="$(get_jacker_root)/secrets/traefik_forward_oauth"
    local template_file="$(get_assets_dir)/templates/traefik_forward_oauth.template"

    if [ -f "$template_file" ]; then
        create_from_template "$template_file" "$secret_file"
    else
        warning "OAuth template not found"
    fi
}

# ============================================================================
# Monitoring Stack Functions
# ============================================================================

# Setup monitoring stack
setup_monitoring() {
    section "Monitoring Stack Setup"

    # Setup Prometheus
    setup_prometheus

    # Setup Grafana
    setup_grafana

    # Setup Loki
    setup_loki

    # Setup Alertmanager
    setup_alertmanager

    success "Monitoring stack setup complete"
}

# Setup Prometheus
setup_prometheus() {
    subsection "Setting up Prometheus"

    ensure_dir "$(get_data_dir)/prometheus"
    ensure_dir "$(get_data_dir)/prometheus/rules"

    # TODO: Add Prometheus configuration
    success "Prometheus configured"
}

# Setup Grafana
setup_grafana() {
    subsection "Setting up Grafana"

    ensure_dir "$(get_data_dir)/grafana/data"
    chmod 755 "$(get_data_dir)/grafana/data"

    success "Grafana configured"
}

# Setup Loki
setup_loki() {
    subsection "Setting up Loki"

    # Create all required Loki directories
    ensure_dir "$(get_data_dir)/loki/data/rules"
    ensure_dir "$(get_data_dir)/loki/data/chunks"
    ensure_dir "$(get_data_dir)/loki/data/compactor"

    # Loki runs as UID 10001, needs write access
    chmod -R 777 "$(get_data_dir)/loki/data"

    # Copy configuration
    local config_file="$(get_data_dir)/loki/loki-config.yml"
    local template_file="$(get_assets_dir)/templates/loki-config.yml.template"

    if [ -f "$template_file" ]; then
        cp "$template_file" "$config_file"
    fi

    success "Loki configured"
}

# Setup Alertmanager
setup_alertmanager() {
    subsection "Setting up Alertmanager"

    ensure_dir "$(get_data_dir)/alertmanager"

    local config_file="$(get_data_dir)/alertmanager/alertmanager.yml"
    local template_file="$(get_assets_dir)/templates/alertmanager.yml.template"

    if [ -f "$template_file" ]; then
        create_from_template "$template_file" "$config_file"
    fi

    success "Alertmanager configured"
}

# ============================================================================
# Service Health Functions
# ============================================================================

# Check all services health
# ============================================================================
# Redis Functions
# ============================================================================

# Setup Redis
setup_redis() {
    section "Redis Setup"

    ensure_dir "$(get_data_dir)/redis"

    # Redis configuration is handled by docker-compose
    # No additional setup needed for basic configuration

    success "Redis setup complete"
}

# ============================================================================
# Individual Service Health Checks
# ============================================================================

# Check Traefik health
check_traefik_health() {
    if is_container_running "traefik"; then
        # Try to access Traefik API
        if docker_exec traefik wget --quiet --tries=1 --spider http://localhost:8080/ping 2>/dev/null; then
            success "Traefik is healthy"
            return 0
        else
            warning "Traefik is running but not responding"
            return 1
        fi
    else
        error "Traefik is not running"
        return 1
    fi
}

# Check CrowdSec health
check_crowdsec_health() {
    if is_container_running "crowdsec"; then
        # Check if CrowdSec CLI is accessible
        if docker_exec crowdsec cscli version &>/dev/null; then
            success "CrowdSec is healthy"
            return 0
        else
            warning "CrowdSec is running but not responding"
            return 1
        fi
    else
        error "CrowdSec is not running"
        return 1
    fi
}

# Check PostgreSQL health
check_postgresql_health() {
    if is_container_running "postgres"; then
        local db_user="${POSTGRES_USER:-postgres}"
        # Check if PostgreSQL is ready
        if docker_exec postgres pg_isready -U "$db_user" &>/dev/null; then
            success "PostgreSQL is healthy"
            return 0
        else
            warning "PostgreSQL is running but not ready"
            return 1
        fi
    else
        error "PostgreSQL is not running"
        return 1
    fi
}

# Check Redis health
check_redis_health() {
    if is_container_running "redis"; then
        # Check if Redis responds to ping
        if docker_exec redis redis-cli ping &>/dev/null; then
            success "Redis is healthy"
            return 0
        else
            warning "Redis is running but not responding"
            return 1
        fi
    else
        error "Redis is not running"
        return 1
    fi
}

# Check Prometheus health
check_prometheus_health() {
    if is_container_running "prometheus"; then
        # Try to access Prometheus health endpoint
        if docker_exec prometheus wget --quiet --tries=1 --spider http://localhost:9090/-/healthy 2>/dev/null; then
            success "Prometheus is healthy"
            return 0
        else
            warning "Prometheus is running but not responding"
            return 1
        fi
    else
        error "Prometheus is not running"
        return 1
    fi
}

# Check Grafana health
check_grafana_health() {
    if is_container_running "grafana"; then
        success "Grafana is healthy"
        return 0
    else
        error "Grafana is not running"
        return 1
    fi
}

# ============================================================================
# Network Management Functions
# ============================================================================

# Create Docker networks
create_networks() {
    section "Creating Docker Networks"

    local networks=(
        "proxy"
        "backend"
    )

    for network in "${networks[@]}"; do
        if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
            info "Creating network: $network"
            docker network create "$network" &>/dev/null || warning "Failed to create network: $network"
        else
            info "Network already exists: $network"
        fi
    done

    success "Networks configured"
}

# Check network connectivity
check_network_connectivity() {
    local network="${1:-proxy}"
    
    info "Checking network connectivity for: $network"
    
    if ! docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
        error "Network does not exist: $network"
        return 1
    fi
    
    # Try to inspect the network
    if docker network inspect "$network" &>/dev/null; then
        success "Network $network is accessible"
        return 0
    else
        error "Cannot inspect network: $network"
        return 1
    fi
}

# ============================================================================
# Volume Management Functions
# ============================================================================

# Create Docker volumes
create_volumes() {
    section "Creating Docker Volumes"

    local volumes=(
        "traefik-data"
        "postgres-data"
        "redis-data"
        "grafana-data"
        "prometheus-data"
        "loki-data"
        "crowdsec-data"
    )

    for volume in "${volumes[@]}"; do
        if ! docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
            info "Creating volume: $volume"
            docker volume create "$volume" &>/dev/null || warning "Failed to create volume: $volume"
        else
            info "Volume already exists: $volume"
        fi
    done

    success "Volumes configured"
}

# Backup volumes
backup_volumes() {
    local backup_dir="${1:-$(get_jacker_root)/backup}"
    local timestamp="$(date +%Y%m%d-%H%M%S)"
    
    section "Backing Up Docker Volumes"
    
    ensure_dir "$backup_dir"
    
    local volumes=(
        "traefik-data"
        "postgres-data"
        "redis-data"
        "grafana-data"
        "prometheus-data"
    )
    
    for volume in "${volumes[@]}"; do
        if docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
            info "Backing up volume: $volume"
            local backup_file="${backup_dir}/${volume}_${timestamp}.tar.gz"
            
            docker run --rm \
                -v "${volume}:/data" \
                -v "${backup_dir}:/backup" \
                alpine \
                tar czf "/backup/$(basename "$backup_file")" -C /data . &>/dev/null
            
            if [ -f "$backup_file" ]; then
                success "Backed up: $volume -> $(basename "$backup_file")"
            else
                warning "Failed to backup: $volume"
            fi
        fi
    done
    
    success "Volume backups complete"
}

# ============================================================================
# Certificate Management Functions
# ============================================================================

# Generate self-signed certificate
generate_self_signed_cert() {
    local domain="${1:-localhost}"
    local cert_dir="${2:-$(get_data_dir)/traefik/certs}"
    
    section "Generating Self-Signed Certificate"
    
    ensure_dir "$cert_dir"
    
    local cert_file="${cert_dir}/cert.pem"
    local key_file="${cert_dir}/key.pem"
    
    info "Generating certificate for: $domain"
    
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$key_file" \
        -out "$cert_file" \
        -days 365 \
        -subj "/CN=$domain" &>/dev/null
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        success "Certificate generated: $cert_file"
        return 0
    else
        error "Failed to generate certificate"
        return 1
    fi
}

# Check certificate expiry
check_certificate_expiry() {
    local cert_file="$1"
    
    if [ ! -f "$cert_file" ]; then
        error "Certificate file not found: $cert_file"
        return 1
    fi
    
    info "Checking certificate expiry: $cert_file"
    
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    if [ -n "$expiry_date" ]; then
        info "Certificate expires: $expiry_date"
        echo "notAfter=$expiry_date"
        return 0
    else
        error "Failed to read certificate"
        return 1
    fi
}

# ============================================================================
# Service Scaling Functions
# ============================================================================

# Scale service
scale_service() {
    local service="$1"
    local replicas="${2:-1}"
    
    info "Scaling service $service to $replicas replicas"
    
    if docker compose up -d --scale "${service}=${replicas}" &>/dev/null; then
        success "Service $service scaled to $replicas replicas"
        return 0
    else
        error "Failed to scale service: $service"
        return 1
    fi
}

# ============================================================================
# OAuth2 Proxy Functions
# ============================================================================

# Setup OAuth2 Proxy
setup_oauth2_proxy() {
    section "OAuth2 Proxy Setup"
    
    local data_dir="$(get_data_dir)/oauth2-proxy"
    local secrets_dir="$(get_jacker_root)/secrets"
    
    ensure_dir "$data_dir"
    ensure_dir "$secrets_dir"
    
    # Create configuration file
    local config_file="${data_dir}/oauth2-proxy.cfg"
    cat > "$config_file" <<EOF
provider = "${OAUTH2_PROXY_PROVIDER:-google}"
client_id = "${OAUTH2_PROXY_CLIENT_ID}"
client_secret = "${OAUTH2_PROXY_CLIENT_SECRET}"
cookie_secret = "${OAUTH2_PROXY_COOKIE_SECRET}"
email_domains = ["${OAUTH2_PROXY_EMAIL_DOMAINS:-*}"]
upstreams = ["http://127.0.0.1:8080/"]
http_address = "0.0.0.0:4180"
EOF
    
    # Create secrets file
    local secrets_file="${secrets_dir}/oauth2_proxy_secrets.env"
    cat > "$secrets_file" <<EOF
CLIENT_ID=${OAUTH2_PROXY_CLIENT_ID}
CLIENT_SECRET=${OAUTH2_PROXY_CLIENT_SECRET}
COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
EOF
    
    chmod 600 "$secrets_file"
    
    success "OAuth2 Proxy configured"
}

check_services_health() {
    section "Service Health Check"

    local services=(
        "traefik"
        "crowdsec"
        "postgres"
        "redis"
        "prometheus"
        "grafana"
        "loki"
        "portainer"
    )

    local all_healthy=true

    for service in "${services[@]}"; do
        if is_container_running "$service"; then
            success "$service: Running"
        else
            error "$service: Not running"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        success "All services are healthy"
        return 0
    else
        error "Some services are not healthy"
        return 1
    fi
}

# ============================================================================
# Export Functions
# ============================================================================

export -f setup_crowdsec configure_crowdsec_db register_crowdsec_bouncers install_crowdsec_firewall_bouncer
export -f setup_traefik configure_traefik
export -f setup_postgresql wait_for_postgresql ensure_crowdsec_database
export -f setup_redis
export -f setup_oauth configure_oauth_secret
export -f setup_oauth2_proxy
export -f setup_monitoring setup_prometheus setup_grafana setup_loki setup_alertmanager
export -f check_services_health
export -f check_traefik_health check_crowdsec_health check_postgresql_health
export -f check_redis_health check_prometheus_health check_grafana_health
export -f create_networks check_network_connectivity
export -f create_volumes backup_volumes
export -f generate_self_signed_cert check_certificate_expiry
export -f scale_service