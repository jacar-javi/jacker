#!/usr/bin/env bash
# Jacker Setup Library
# Simplified and unified setup functions

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"

#########################################
# Configuration Detection
#########################################

detect_system_config() {
    log_info "Detecting system configuration..."

    # Detect user and paths
    PUID=$(id -u)
    PGID=$(id -g)
    USERDIR="${HOME}"
    DOCKERDIR="$(cd "${JACKER_DIR}" && pwd)"
    DATADIR="${DOCKERDIR}/data"

    # Detect hostname and domain
    HOSTNAME=$(hostname -s)

    # Try to detect existing domain from various sources
    if [[ -f /etc/letsencrypt/renewal/* ]]; then
        DETECTED_DOMAIN=$(ls /etc/letsencrypt/renewal/ | head -1 | sed 's/\.conf$//')
    elif command -v hostname &>/dev/null && hostname -f 2>/dev/null | grep -q '\.'; then
        DETECTED_DOMAIN=$(hostname -f)
    else
        DETECTED_DOMAIN=""
    fi

    # Detect if running in VM/container
    if grep -q "docker\|lxc\|virtualization" /proc/1/cgroup 2>/dev/null || \
       systemd-detect-virt 2>/dev/null | grep -qE "docker|lxc|kvm|qemu|vmware|virtualbox|hyperv"; then
        HOST_IS_VM=true
    else
        HOST_IS_VM=false
    fi

    log_success "System configuration detected"
}

#########################################
# Environment Setup
#########################################

create_env_file() {
    local quick_mode="${1:-false}"

    log_info "Creating .env configuration..."

    # Start with defaults
    cp "${JACKER_DIR}/.env.defaults" "${JACKER_DIR}/.env.tmp"

    # Apply detected values
    sed -i "s|^PUID=.*|PUID=${PUID}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PGID=.*|PGID=${PGID}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^USERDIR=.*|USERDIR=${USERDIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^DOCKERDIR=.*|DOCKERDIR=${DOCKERDIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^DATADIR=.*|DATADIR=${DATADIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOSTNAME=.*|HOSTNAME=${HOSTNAME}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOST_IS_VM=.*|HOST_IS_VM=${HOST_IS_VM}|" "${JACKER_DIR}/.env.tmp"

    if [[ "$quick_mode" == "false" ]]; then
        # Interactive configuration
        configure_interactive
    else
        # Quick mode - use minimal required inputs
        configure_quick
    fi

    # Generate secrets
    generate_all_secrets

    # Move tmp to final
    mv "${JACKER_DIR}/.env.tmp" "${JACKER_DIR}/.env"
    chmod 600 "${JACKER_DIR}/.env"

    log_success ".env file created"
}

configure_quick() {
    log_info "Quick configuration mode"

    # Domain configuration
    read -p "Enter your domain name (e.g., example.com): " domain
    read -p "Enter your hostname (e.g., myserver): " hostname

    sed -i "s|^DOMAINNAME=.*|DOMAINNAME=${domain}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PUBLIC_FQDN=.*|PUBLIC_FQDN=${hostname}.${domain}|" "${JACKER_DIR}/.env.tmp"

    # Let's Encrypt
    read -p "Enter email for Let's Encrypt certificates: " le_email
    sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${le_email}|" "${JACKER_DIR}/.env.tmp"

    # OAuth (optional)
    echo
    echo "OAuth configuration (press Enter to skip for now):"
    read -p "Google OAuth Client ID: " oauth_id
    read -p "Google OAuth Client Secret: " oauth_secret
    read -p "Allowed emails (comma-separated): " oauth_emails

    if [[ -n "$oauth_id" ]]; then
        sed -i "s|^OAUTH_CLIENT_ID=.*|OAUTH_CLIENT_ID=${oauth_id}|" "${JACKER_DIR}/.env.tmp"
        sed -i "s|^OAUTH_CLIENT_SECRET=.*|OAUTH_CLIENT_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
        sed -i "s|^OAUTH_WHITELIST=.*|OAUTH_WHITELIST=${oauth_emails}|" "${JACKER_DIR}/.env.tmp"
    fi
}

configure_interactive() {
    log_info "Interactive configuration mode"

    # Full interactive configuration
    # Domain and networking
    read -p "Domain name [${DETECTED_DOMAIN:-example.com}]: " domain
    domain="${domain:-${DETECTED_DOMAIN:-example.com}}"

    read -p "Hostname [${HOSTNAME}]: " hostname_input
    hostname_input="${hostname_input:-${HOSTNAME}}"

    sed -i "s|^DOMAINNAME=.*|DOMAINNAME=${domain}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOSTNAME=.*|HOSTNAME=${hostname_input}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PUBLIC_FQDN=.*|PUBLIC_FQDN=${hostname_input}.${domain}|" "${JACKER_DIR}/.env.tmp"

    # Let's Encrypt
    read -p "Let's Encrypt email address: " le_email
    sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${le_email}|" "${JACKER_DIR}/.env.tmp"

    # OAuth configuration
    echo
    echo "Authentication Configuration:"
    echo "1. Google OAuth (recommended)"
    echo "2. Authentik (self-hosted)"
    echo "3. Skip authentication (not recommended for production)"
    read -p "Choose authentication method [1]: " auth_choice
    auth_choice="${auth_choice:-1}"

    case "$auth_choice" in
        1)
            configure_google_oauth
            ;;
        2)
            configure_authentik
            ;;
        3)
            log_warn "Skipping authentication - services will be publicly accessible!"
            ;;
    esac

    # Advanced options
    echo
    read -p "Configure advanced options? (y/N): " advanced
    if [[ "${advanced,,}" == "y" ]]; then
        configure_advanced_options
    fi
}

configure_google_oauth() {
    echo
    echo "Google OAuth Configuration"
    echo "See: https://console.cloud.google.com/apis/credentials"

    read -p "OAuth Client ID: " oauth_id
    read -p "OAuth Client Secret: " oauth_secret
    read -p "Allowed email addresses (comma-separated): " oauth_emails

    sed -i "s|^OAUTH_CLIENT_ID=.*|OAUTH_CLIENT_ID=${oauth_id}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_CLIENT_SECRET=.*|OAUTH_CLIENT_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_WHITELIST=.*|OAUTH_WHITELIST=${oauth_emails}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_PROVIDER=.*|OAUTH_PROVIDER=google|" "${JACKER_DIR}/.env.tmp"
}

configure_authentik() {
    echo
    echo "Authentik will be configured automatically"

    # Generate Authentik secrets
    local secret_key=$(openssl rand -base64 60 | tr -d '\n')
    local pg_password=$(openssl rand -base64 32 | tr -d '\n')

    # Update .env.tmp
    sed -i "/^# AUTHENTIK_VERSION=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_SECRET_KEY=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_PASSWORD=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_DB=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_USER=/s/^# //" "${JACKER_DIR}/.env.tmp"

    sed -i "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=${secret_key}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^AUTHENTIK_POSTGRES_PASSWORD=.*|AUTHENTIK_POSTGRES_PASSWORD=${pg_password}|" "${JACKER_DIR}/.env.tmp"

    # Enable Authentik in docker-compose.yml
    sed -i '/path: compose\/authentik.yml/s/^#[[:space:]]*//' "${JACKER_DIR}/docker-compose.yml"

    log_info "Authentik configured - will be available at https://auth.${domain}"
}

configure_advanced_options() {
    echo
    echo "Advanced Configuration Options:"

    # Timezone
    read -p "Timezone [Europe/Madrid]: " tz
    tz="${tz:-Europe/Madrid}"
    sed -i "s|^TZ=.*|TZ=${tz}|" "${JACKER_DIR}/.env.tmp"

    # Network configuration
    read -p "Configure custom Docker networks? (y/N): " custom_net
    if [[ "${custom_net,,}" == "y" ]]; then
        read -p "Docker default subnet [192.168.69.0/24]: " docker_subnet
        docker_subnet="${docker_subnet:-192.168.69.0/24}"
        sed -i "s|^DOCKER_DEFAULT_SUBNET=.*|DOCKER_DEFAULT_SUBNET=${docker_subnet}|" "${JACKER_DIR}/.env.tmp"
    fi

    # Alerting
    read -p "Configure email alerts? (y/N): " alerts
    if [[ "${alerts,,}" == "y" ]]; then
        configure_alerting
    fi
}

configure_alerting() {
    echo
    echo "Email Alert Configuration:"

    read -p "SMTP Host [smtp.gmail.com]: " smtp_host
    smtp_host="${smtp_host:-smtp.gmail.com}"

    read -p "SMTP Port [587]: " smtp_port
    smtp_port="${smtp_port:-587}"

    read -p "SMTP Username: " smtp_user
    read -sp "SMTP Password: " smtp_pass
    echo

    read -p "Alert recipient email: " alert_email

    sed -i "s|^SMTP_HOST=.*|SMTP_HOST=${smtp_host}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^SMTP_PORT=.*|SMTP_PORT=${smtp_port}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^SMTP_USERNAME=.*|SMTP_USERNAME=${smtp_user}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^SMTP_PASSWORD=.*|SMTP_PASSWORD=${smtp_pass}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^ALERT_EMAIL_TO=.*|ALERT_EMAIL_TO=${alert_email}|" "${JACKER_DIR}/.env.tmp"
}

#########################################
# Secret Generation
#########################################

generate_all_secrets() {
    log_info "Generating secrets..."

    # OAuth secrets
    if ! grep -q "^OAUTH_SECRET=.\+" "${JACKER_DIR}/.env.tmp"; then
        local oauth_secret=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^OAUTH_SECRET=.*|OAUTH_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
    fi

    if ! grep -q "^OAUTH_COOKIE_SECRET=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cookie_secret=$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')
        sed -i "s|^OAUTH_COOKIE_SECRET=.*|OAUTH_COOKIE_SECRET=${cookie_secret}|" "${JACKER_DIR}/.env.tmp"
    fi

    # PostgreSQL password
    if ! grep -q "^POSTGRES_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local pg_password=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pg_password}|" "${JACKER_DIR}/.env.tmp"
    fi

    # CrowdSec API keys
    if ! grep -q "^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_traefik_key=$(openssl rand -hex 32)
        sed -i "s|^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.*|CROWDSEC_TRAEFIK_BOUNCER_API_KEY=${cs_traefik_key}|" "${JACKER_DIR}/.env.tmp"
    fi

    if ! grep -q "^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_iptables_key=$(openssl rand -hex 32)
        sed -i "s|^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.*|CROWDSEC_IPTABLES_BOUNCER_API_KEY=${cs_iptables_key}|" "${JACKER_DIR}/.env.tmp"
    fi

    if ! grep -q "^CROWDSEC_API_LOCAL_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_api_pass=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^CROWDSEC_API_LOCAL_PASSWORD=.*|CROWDSEC_API_LOCAL_PASSWORD=${cs_api_pass}|" "${JACKER_DIR}/.env.tmp"
    fi

    log_success "Secrets generated"
}

#########################################
# Directory Structure
#########################################

create_directory_structure() {
    log_info "Creating directory structure..."

    # Create all required directories based on compose services
    local dirs=(
        "data/traefik/rules"
        "data/traefik/acme"
        "data/oauth2-proxy"
        "data/crowdsec/config/parsers/s02-enrich"
        "data/crowdsec/data"
        "data/postgres"
        "data/redis"
        "data/loki/data/rules"
        "data/loki/data/chunks"
        "data/loki/data/compactor"
        "data/promtail"
        "data/grafana/data"
        "data/prometheus"
        "data/alertmanager"
        "data/homepage/config"
        "data/portainer"
        "data/vscode"
        "data/node-exporter"
        "data/jaeger"
        "config/traefik"
        "config/oauth2-proxy"
        "config/crowdsec"
        "config/postgres"
        "config/redis"
        "config/loki"
        "config/grafana/provisioning/dashboards"
        "config/grafana/provisioning/datasources"
        "config/prometheus"
        "config/alertmanager"
        "config/homepage"
        "config/jaeger"
        "secrets"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "${JACKER_DIR}/${dir}"
    done

    # Set specific permissions
    touch "${JACKER_DIR}/data/traefik/acme/acme.json"
    chmod 600 "${JACKER_DIR}/data/traefik/acme/acme.json"

    # Loki needs special permissions for UID 10001
    chmod -R 777 "${JACKER_DIR}/data/loki/data"

    # Secrets directory should be restricted
    chmod 700 "${JACKER_DIR}/secrets"

    log_success "Directory structure created"
}

#########################################
# Configuration Files
#########################################

create_configuration_files() {
    log_info "Creating configuration files..."

    # Source the .env file
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Process templates
    local templates_dir="${JACKER_DIR}/assets/templates"

    if [[ -d "$templates_dir" ]]; then
        # Traefik configuration
        if [[ -f "$templates_dir/traefik.yml.template" ]]; then
            envsubst < "$templates_dir/traefik.yml.template" > "${JACKER_DIR}/data/traefik/traefik.yml"
        fi

        # Loki configuration
        if [[ -f "$templates_dir/loki-config.yml.template" ]]; then
            envsubst < "$templates_dir/loki-config.yml.template" > "${JACKER_DIR}/data/loki/loki-config.yml"
        fi

        # Promtail configuration
        if [[ -f "$templates_dir/promtail-config.yml.template" ]]; then
            envsubst < "$templates_dir/promtail-config.yml.template" > "${JACKER_DIR}/data/loki/promtail-config.yml"
        fi

        # CrowdSec configuration
        if [[ -f "$templates_dir/config.yaml.local.template" ]]; then
            envsubst < "$templates_dir/config.yaml.local.template" > "${JACKER_DIR}/data/crowdsec/config/config.yaml.local"
        fi

        # Homepage configuration
        if [[ -f "$templates_dir/homepage-settings.yaml.template" ]]; then
            envsubst < "$templates_dir/homepage-settings.yaml.template" > "${JACKER_DIR}/data/homepage/config/settings.yaml"
        fi

        # Homepage custom CSS and JS
        if [[ -f "$templates_dir/homepage-custom.css.template" ]]; then
            cp "$templates_dir/homepage-custom.css.template" "${JACKER_DIR}/data/homepage/custom.css"
        fi
        if [[ -f "$templates_dir/homepage-custom.js.template" ]]; then
            cp "$templates_dir/homepage-custom.js.template" "${JACKER_DIR}/data/homepage/custom.js"
        fi
    fi

    # Create Traefik middleware files
    create_traefik_middlewares

    # Create secrets files
    create_secrets_files

    log_success "Configuration files created"
}

create_traefik_middlewares() {
    local rules_dir="${JACKER_DIR}/data/traefik/rules"

    # OAuth middleware
    cat > "${rules_dir}/middlewares-oauth.yml" <<EOF
http:
  middlewares:
    oauth:
      forwardAuth:
        address: "http://oauth:4181"
        trustForwardHeader: true
        authResponseHeaders:
          - "X-Forwarded-User"
EOF

    # Rate limiting middleware
    cat > "${rules_dir}/middlewares-rate-limit.yml" <<EOF
http:
  middlewares:
    rate-limit-default:
      rateLimit:
        average: 100
        burst: 200
    rate-limit-strict:
      rateLimit:
        average: 10
        burst: 20
    rate-limit-api:
      rateLimit:
        average: 50
        burst: 100
EOF

    # Security headers middleware
    cat > "${rules_dir}/middlewares-secure-headers.yml" <<EOF
http:
  middlewares:
    middlewares-secure-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
EOF

    # Compression middleware
    cat > "${rules_dir}/middlewares-compress.yml" <<EOF
http:
  middlewares:
    middlewares-compress:
      compress:
        minResponseBodyBytes: 1024
EOF

    # CORS middleware
    cat > "${rules_dir}/middlewares-cors.yml" <<EOF
http:
  middlewares:
    middlewares-cors:
      headers:
        accessControlAllowMethods:
          - "GET"
          - "POST"
          - "PUT"
          - "DELETE"
          - "OPTIONS"
        accessControlAllowHeaders:
          - "*"
        accessControlAllowOriginList:
          - "*"
        accessControlMaxAge: 100
        addVaryHeader: true
EOF

    # Cache middleware
    cat > "${rules_dir}/middlewares-cache.yml" <<EOF
http:
  middlewares:
    middlewares-cache:
      plugin:
        cache:
          maxExpiry: 300s
EOF

    # Chain middlewares
    cat > "${rules_dir}/chain-oauth.yml" <<EOF
http:
  middlewares:
    chain-oauth:
      chain:
        middlewares:
          - rate-limit-default@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
          - oauth@file

    chain-oauth-no-crowdsec:
      chain:
        middlewares:
          - rate-limit-strict@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
          - oauth@file
EOF

    cat > "${rules_dir}/chain-no-oauth.yml" <<EOF
http:
  middlewares:
    chain-no-oauth:
      chain:
        middlewares:
          - rate-limit-default@file
          - middlewares-secure-headers@file
          - middlewares-compress@file

    chain-api:
      chain:
        middlewares:
          - rate-limit-api@file
          - middlewares-cors@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
EOF

    # TLS options
    cat > "${rules_dir}/tls-opts.yml" <<EOF
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      curvePreferences:
        - CurveP521
        - CurveP384
      sniStrict: true
EOF
}

create_secrets_files() {
    local secrets_dir="${JACKER_DIR}/secrets"

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Create individual secret files for Docker secrets
    echo "${POSTGRES_PASSWORD}" > "${secrets_dir}/postgres_password"
    echo "${OAUTH_COOKIE_SECRET}" > "${secrets_dir}/oauth_cookie_secret"
    echo "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}" > "${secrets_dir}/crowdsec_bouncer_key"
    echo "${CROWDSEC_API_LOCAL_PASSWORD}" > "${secrets_dir}/crowdsec_lapi_key"

    # Generate additional secrets if needed
    openssl rand -base64 32 > "${secrets_dir}/grafana_admin_password"
    openssl rand -base64 32 > "${secrets_dir}/redis_password"
    openssl rand -base64 48 > "${secrets_dir}/portainer_secret"
    openssl rand -base64 48 > "${secrets_dir}/traefik_forward_oauth"

    # Set restrictive permissions
    chmod 600 "${secrets_dir}"/*

    # Create .gitignore for secrets
    cat > "${secrets_dir}/.gitignore" <<EOF
# Ignore all secret files
*
# Except this file and README
!.gitignore
!README.md
EOF
}

#########################################
# System Preparation
#########################################

prepare_system() {
    log_info "Preparing system..."

    # Update package lists
    update_system_packages

    # Install Docker if needed
    if ! command -v docker &>/dev/null; then
        install_docker
    fi

    # Install Docker Compose if needed
    if ! docker compose version &>/dev/null 2>&1; then
        install_docker_compose
    fi

    # Install required packages
    install_required_packages

    # Configure Docker
    configure_docker

    # Configure UFW if requested
    if command -v ufw &>/dev/null; then
        read -p "Configure UFW firewall? (y/N): " configure_ufw
        if [[ "${configure_ufw,,}" == "y" ]]; then
            setup_ufw
        fi
    fi

    log_success "System prepared"
}

update_system_packages() {
    log_info "Updating system packages..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
    elif command -v dnf &>/dev/null; then
        sudo dnf check-update || true
    elif command -v yum &>/dev/null; then
        sudo yum check-update || true
    fi
}

install_docker() {
    log_info "Installing Docker..."

    if command -v apt-get &>/dev/null; then
        # Ubuntu/Debian
        curl -fsSL https://get.docker.com | sudo sh
    elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    elif command -v yum &>/dev/null; then
        # RHEL/CentOS
        sudo yum install -y docker-ce docker-ce-cli containerd.io
    else
        log_error "Unsupported distribution for Docker installation"
        return 1
    fi

    # Add user to docker group
    sudo usermod -aG docker "$USER"

    # Start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    log_success "Docker installed"
}

install_docker_compose() {
    log_info "Installing Docker Compose plugin..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y docker-compose-plugin
    else
        # Manual installation for other distributions
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    log_success "Docker Compose installed"
}

install_required_packages() {
    log_info "Installing required packages..."

    local packages=(
        "curl"
        "wget"
        "git"
        "python3"
        "python3-pip"
        "openssl"
        "jq"
        "htop"
        "net-tools"
    )

    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y "${packages[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${packages[@]}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "${packages[@]}"
    fi
}

configure_docker() {
    log_info "Configuring Docker..."

    # Create Docker daemon configuration
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "3"
    },
    "default-address-pools": [
        {
            "base": "192.168.64.0/18",
            "size": 24
        }
    ]
}
EOF

    # Restart Docker to apply configuration
    sudo systemctl restart docker
}

setup_ufw() {
    log_info "Configuring UFW firewall..."

    # Load UFW configuration from .env
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Enable UFW
    sudo ufw --force enable

    # Allow SSH
    if [[ -n "${UFW_ALLOW_SSH}" ]]; then
        IFS=',' read -ra SSH_SOURCES <<< "${UFW_ALLOW_SSH}"
        for source in "${SSH_SOURCES[@]}"; do
            sudo ufw allow from "${source}" to any port 22 proto tcp comment "SSH from ${source}"
        done
    else
        sudo ufw allow 22/tcp comment "SSH"
    fi

    # Allow HTTP and HTTPS
    sudo ufw allow 80/tcp comment "HTTP"
    sudo ufw allow 443/tcp comment "HTTPS"

    # Allow from specific sources if configured
    if [[ -n "${UFW_ALLOW_FROM}" ]]; then
        IFS=',' read -ra ALLOW_SOURCES <<< "${UFW_ALLOW_FROM}"
        for source in "${ALLOW_SOURCES[@]}"; do
            sudo ufw allow from "${source}" comment "Allow from ${source}"
        done
    fi

    # Docker-specific rules
    sudo ufw allow in on docker0

    # Reload UFW
    sudo ufw reload

    log_success "UFW firewall configured"
}

#########################################
# Service Initialization
#########################################

initialize_services() {
    log_info "Initializing services..."

    # Start core infrastructure services first
    log_info "Starting core services..."
    docker compose up -d socket-proxy postgres redis

    # Wait for PostgreSQL to be ready
    wait_for_postgres

    # Initialize PostgreSQL databases
    initialize_postgres_databases

    # Start remaining services
    log_info "Starting all services..."
    docker compose up -d

    # Wait for services to be healthy
    wait_for_services

    # Configure CrowdSec
    configure_crowdsec

    log_success "Services initialized"
}

wait_for_postgres() {
    log_info "Waiting for PostgreSQL to be ready..."

    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-crowdsec}" &>/dev/null; then
            log_success "PostgreSQL is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    log_error "PostgreSQL failed to start"
    return 1
}

initialize_postgres_databases() {
    log_info "Initializing PostgreSQL databases..."

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Create databases from POSTGRES_MULTIPLE_DATABASES
    if [[ -n "${POSTGRES_MULTIPLE_DATABASES}" ]]; then
        IFS=',' read -ra DATABASES <<< "${POSTGRES_MULTIPLE_DATABASES}"
        for db in "${DATABASES[@]}"; do
            db=$(echo "$db" | xargs)  # Trim whitespace
            log_info "Creating database: ${db}"

            docker compose exec -T postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE IF NOT EXISTS ${db};" 2>/dev/null || true
        done
    fi

    log_success "PostgreSQL databases initialized"
}

wait_for_services() {
    log_info "Waiting for services to be ready..."

    local services=(
        "traefik:80"
        "oauth:4181"
        "grafana:3000"
        "prometheus:9090"
    )

    for service in "${services[@]}"; do
        local service_name="${service%:*}"
        local service_port="${service#*:}"

        log_info "Checking ${service_name}..."
        local max_attempts=30
        local attempt=0

        while [[ $attempt -lt $max_attempts ]]; do
            if docker compose exec -T "${service_name}" wget -q --spider "http://localhost:${service_port}" 2>/dev/null; then
                log_success "${service_name} is ready"
                break
            fi

            attempt=$((attempt + 1))
            sleep 2
        done
    done
}

configure_crowdsec() {
    log_info "Configuring CrowdSec..."

    # Register bouncers
    docker compose exec -T crowdsec cscli bouncers add traefik-bouncer \
        -k "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}" 2>/dev/null || true

    # Install collections
    docker compose exec -T crowdsec cscli collections install crowdsecurity/traefik 2>/dev/null || true
    docker compose exec -T crowdsec cscli collections install crowdsecurity/http-cve 2>/dev/null || true

    # Reload CrowdSec
    docker compose exec -T crowdsec cscli reload 2>/dev/null || true

    log_success "CrowdSec configured"
}

#########################################
# Main Setup Function
#########################################

setup_jacker() {
    local mode="${1:-interactive}"

    log_section "Jacker Setup"

    # Check if already installed
    if [[ -f "${JACKER_DIR}/.env" ]]; then
        log_warn "Existing installation detected"
        echo "1. Reinstall (preserve configuration)"
        echo "2. Fresh install (backup and start over)"
        echo "3. Cancel"
        read -p "Choose option [1]: " install_choice
        install_choice="${install_choice:-1}"

        case "$install_choice" in
            1)
                backup_existing_installation
                ;;
            2)
                backup_existing_installation
                rm -f "${JACKER_DIR}/.env"
                ;;
            3)
                log_info "Installation cancelled"
                return 0
                ;;
        esac
    fi

    # Detect system configuration
    detect_system_config

    # Create environment configuration
    if [[ "$mode" == "quick" ]]; then
        create_env_file true
    else
        create_env_file false
    fi

    # Create directory structure
    create_directory_structure

    # Create configuration files
    create_configuration_files

    # Prepare system
    prepare_system

    # Initialize services
    initialize_services

    # Show completion message
    show_completion_message
}

backup_existing_installation() {
    log_info "Backing up existing installation..."

    local backup_dir="${JACKER_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup .env
    [[ -f "${JACKER_DIR}/.env" ]] && cp "${JACKER_DIR}/.env" "$backup_dir/"

    # Backup data directory
    [[ -d "${JACKER_DIR}/data" ]] && tar -czf "$backup_dir/data.tar.gz" -C "${JACKER_DIR}" data

    # Backup secrets
    [[ -d "${JACKER_DIR}/secrets" ]] && tar -czf "$backup_dir/secrets.tar.gz" -C "${JACKER_DIR}" secrets

    log_success "Backup created at: $backup_dir"
}

show_completion_message() {
    log_section "Installation Complete!"

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    echo
    echo "Jacker has been successfully installed!"
    echo
    echo "Access your services at:"
    echo "  Dashboard:    https://homepage.${PUBLIC_FQDN}"
    echo "  Traefik:      https://traefik.${PUBLIC_FQDN}"
    echo "  Grafana:      https://grafana.${PUBLIC_FQDN}"
    echo "  Prometheus:   https://prometheus.${PUBLIC_FQDN}"
    echo "  Portainer:    https://portainer.${PUBLIC_FQDN}"

    if [[ -n "${AUTHENTIK_SECRET_KEY}" ]]; then
        echo "  Authentik:    https://auth.${PUBLIC_FQDN}"
    fi

    echo
    echo "Management commands:"
    echo "  ./jacker start     - Start all services"
    echo "  ./jacker stop      - Stop all services"
    echo "  ./jacker status    - Check service status"
    echo "  ./jacker health    - Run health check"
    echo "  ./jacker help      - Show all commands"
    echo

    if [[ -z "${OAUTH_CLIENT_ID}" ]] && [[ -z "${AUTHENTIK_SECRET_KEY}" ]]; then
        log_warn "No authentication configured - services are publicly accessible!"
        echo "Run './jacker config oauth' to configure authentication"
    fi
}

# Export functions for use by jacker CLI
export -f setup_jacker
export -f detect_system_config
export -f create_env_file
export -f create_directory_structure
export -f create_configuration_files
export -f prepare_system
export -f initialize_services
export -f backup_existing_installation