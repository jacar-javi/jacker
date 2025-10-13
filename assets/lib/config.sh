#!/usr/bin/env bash
# Jacker Configuration Management Library
# Handles all configuration operations for services

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

#########################################
# Environment Configuration
#########################################

show_env_config() {
    log_section "Current Configuration"

    if [[ ! -f "${JACKER_DIR}/.env" ]]; then
        log_error "No configuration found. Run './jacker init' first."
        return 1
    fi

    # Load and display key configuration
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    echo "Domain Configuration:"
    echo "  Domain:        ${DOMAINNAME}"
    echo "  Hostname:      ${HOSTNAME}"
    echo "  Public FQDN:   ${PUBLIC_FQDN}"
    echo

    echo "Authentication:"
    if [[ -n "${OAUTH_CLIENT_ID:-}" ]]; then
        echo "  Provider:      Google OAuth"
        echo "  Client ID:     ${OAUTH_CLIENT_ID:0:20}..."
        echo "  Whitelist:     ${OAUTH_WHITELIST:-not configured}"
    elif [[ -n "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        echo "  Provider:      Authentik (self-hosted)"
        echo "  URL:           https://auth.${PUBLIC_FQDN}"
    else
        echo "  Provider:      None (public access)"
    fi
    echo

    echo "SSL/TLS:"
    echo "  Let's Encrypt: ${LETSENCRYPT_EMAIL:-not configured}"
    echo

    echo "Services:"
    echo "  PostgreSQL:    ${POSTGRES_DB}@${POSTGRES_USER}"
    echo "  Redis:         Enabled"
    echo "  CrowdSec:      Enabled"
    echo

    echo "Paths:"
    echo "  User Dir:      ${USERDIR}"
    echo "  Docker Dir:    ${DOCKERDIR}"
    echo "  Data Dir:      ${DATADIR}"
}

edit_env_config() {
    if [[ ! -f "${JACKER_DIR}/.env" ]]; then
        log_error "No configuration found. Run './jacker init' first."
        return 1
    fi

    # Use default editor or nano
    local editor="${EDITOR:-nano}"
    $editor "${JACKER_DIR}/.env"

    # Validate after editing
    validate_env_config
}

validate_env_config() {
    log_info "Validating configuration..."

    local errors=0

    # Check required variables
    local required_vars=(
        "DOMAINNAME"
        "HOSTNAME"
        "PUBLIC_FQDN"
        "PUID"
        "PGID"
        "DOCKERDIR"
        "DATADIR"
    )

    set -a
    source "${JACKER_DIR}/.env"
    set +a

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Missing required variable: $var"
            ((errors++))
        fi
    done

    # Check domain validity
    if [[ "${DOMAINNAME}" == "example.com" ]]; then
        log_warn "Using example.com domain - SSL certificates will not work"
    fi

    # Check authentication
    if [[ -z "${OAUTH_CLIENT_ID:-}" ]] && [[ -z "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        log_warn "No authentication configured - services will be publicly accessible"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Configuration has $errors error(s)"
        return 1
    fi

    log_success "Configuration is valid"
    return 0
}

#########################################
# Service Configuration
#########################################

configure_oauth() {
    log_section "OAuth Configuration"

    if [[ ! -f "${JACKER_DIR}/.env" ]]; then
        log_error "No configuration found. Run './jacker init' first."
        return 1
    fi

    echo "OAuth Provider Options:"
    echo "1. Google OAuth"
    echo "2. GitHub OAuth"
    echo "3. Generic OIDC"
    echo "4. Disable OAuth"
    read -rp "Choose provider [1]: " provider_choice
    provider_choice="${provider_choice:-1}"

    case "$provider_choice" in
        1)
            configure_google_oauth_interactive
            ;;
        2)
            configure_github_oauth
            ;;
        3)
            configure_oidc
            ;;
        4)
            disable_oauth
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac

    # Restart OAuth service
    docker compose restart oauth 2>/dev/null || true
    log_success "OAuth configuration updated"
}

configure_google_oauth_interactive() {
    echo
    echo "Google OAuth Configuration"
    echo "Create credentials at: https://console.cloud.google.com/apis/credentials"
    echo

    read -rp "OAuth Client ID: " client_id
    read -rp "OAuth Client Secret: " client_secret
    read -rp "Allowed email addresses (comma-separated): " whitelist

    # Update .env file
    update_env_var "OAUTH_PROVIDER" "google"
    update_env_var "OAUTH_CLIENT_ID" "$client_id"
    update_env_var "OAUTH_CLIENT_SECRET" "$client_secret"
    update_env_var "OAUTH_WHITELIST" "$whitelist"

    # Generate cookie secret if needed
    if ! grep -q "^OAUTH_COOKIE_SECRET=.\+" "${JACKER_DIR}/.env"; then
        local cookie_secret=$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')
        update_env_var "OAUTH_COOKIE_SECRET" "$cookie_secret"
    fi

    # Update OAuth middleware
    update_oauth_middleware "google"
}

configure_github_oauth() {
    echo
    echo "GitHub OAuth Configuration"
    echo "Create OAuth App at: https://github.com/settings/developers"
    echo

    read -rp "OAuth Client ID: " client_id
    read -rp "OAuth Client Secret: " client_secret
    read -rp "GitHub Organization (optional): " github_org
    read -rp "GitHub Team (optional): " github_team
    read -rp "Allowed email addresses (comma-separated): " whitelist

    update_env_var "OAUTH_PROVIDER" "github"
    update_env_var "OAUTH_CLIENT_ID" "$client_id"
    update_env_var "OAUTH_CLIENT_SECRET" "$client_secret"
    update_env_var "OAUTH_GITHUB_ORG" "$github_org"
    update_env_var "OAUTH_GITHUB_TEAM" "$github_team"
    update_env_var "OAUTH_WHITELIST" "$whitelist"

    update_oauth_middleware "github"
}

configure_oidc() {
    echo
    echo "Generic OIDC Configuration"
    echo

    read -rp "OIDC Issuer URL: " issuer_url
    read -rp "OAuth Client ID: " client_id
    read -rp "OAuth Client Secret: " client_secret
    read -rp "JWKS URL (optional): " jwks_url
    read -rp "Allowed email addresses (comma-separated): " whitelist

    update_env_var "OAUTH_PROVIDER" "oidc"
    update_env_var "OAUTH_CLIENT_ID" "$client_id"
    update_env_var "OAUTH_CLIENT_SECRET" "$client_secret"
    update_env_var "OAUTH_OIDC_ISSUER_URL" "$issuer_url"
    update_env_var "OAUTH_OIDC_JWKS_URL" "$jwks_url"
    update_env_var "OAUTH_WHITELIST" "$whitelist"

    update_oauth_middleware "oidc"
}

disable_oauth() {
    log_warn "Disabling OAuth - services will be publicly accessible!"
    read -rp "Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        log_info "OAuth configuration unchanged"
        return
    fi

    # Clear OAuth variables
    update_env_var "OAUTH_CLIENT_ID" ""
    update_env_var "OAUTH_CLIENT_SECRET" ""

    # Update middleware to remove OAuth
    local rules_dir="${JACKER_DIR}/data/traefik/rules"
    cat > "${rules_dir}/chain-oauth.yml" <<EOF
http:
  middlewares:
    chain-oauth:
      chain:
        middlewares:
          - rate-limit-default@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
    chain-oauth-no-crowdsec:
      chain:
        middlewares:
          - rate-limit-strict@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
EOF

    log_success "OAuth disabled"
}

update_oauth_middleware() {
    local provider="$1"
    local rules_dir="${JACKER_DIR}/data/traefik/rules"

    # Update OAuth middleware configuration
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

    # Ensure chain includes OAuth
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
}

#########################################
# SSL Configuration
#########################################

configure_ssl() {
    log_section "SSL/TLS Configuration"

    if [[ ! -f "${JACKER_DIR}/.env" ]]; then
        log_error "No configuration found. Run './jacker init' first."
        return 1
    fi

    echo "SSL Certificate Options:"
    echo "1. Let's Encrypt (recommended)"
    echo "2. Custom certificates"
    echo "3. Self-signed (development only)"
    read -rp "Choose option [1]: " ssl_choice
    ssl_choice="${ssl_choice:-1}"

    case "$ssl_choice" in
        1)
            configure_letsencrypt
            ;;
        2)
            configure_custom_certs
            ;;
        3)
            configure_self_signed
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac

    # Restart Traefik
    docker compose restart traefik
    log_success "SSL configuration updated"
}

configure_letsencrypt() {
    echo
    echo "Let's Encrypt Configuration"

    read -rp "Email address for certificates: " le_email
    update_env_var "LETSENCRYPT_EMAIL" "$le_email"

    # Ensure ACME configuration in Traefik
    local traefik_config="${JACKER_DIR}/data/traefik/traefik.yml"

    # Check if Let's Encrypt is already configured
    if ! grep -q "acme:" "$traefik_config" 2>/dev/null; then
        cat >> "$traefik_config" <<EOF

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${le_email}
      storage: /acme.json
      httpChallenge:
        entryPoint: web
      caServer: https://acme-v02.api.letsencrypt.org/directory
EOF
    fi

    log_success "Let's Encrypt configured"
}

configure_custom_certs() {
    echo
    echo "Custom Certificate Configuration"

    read -rp "Path to certificate file: " cert_path
    read -rp "Path to private key file: " key_path

    if [[ ! -f "$cert_path" ]] || [[ ! -f "$key_path" ]]; then
        log_error "Certificate files not found"
        return 1
    fi

    # Copy certificates to Traefik directory
    cp "$cert_path" "${JACKER_DIR}/data/traefik/certs/cert.pem"
    cp "$key_path" "${JACKER_DIR}/data/traefik/certs/key.pem"
    chmod 600 "${JACKER_DIR}/data/traefik/certs/"*

    # Update Traefik configuration
    local traefik_config="${JACKER_DIR}/data/traefik/traefik.yml"
    cat >> "$traefik_config" <<EOF

tls:
  certificates:
    - certFile: /certs/cert.pem
      keyFile: /certs/key.pem
EOF

    log_success "Custom certificates configured"
}

configure_self_signed() {
    log_warn "Self-signed certificates are for development only!"

    # Generate self-signed certificate
    local certs_dir="${JACKER_DIR}/data/traefik/certs"
    mkdir -p "$certs_dir"

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$certs_dir/key.pem" \
        -out "$certs_dir/cert.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=*.${DOMAINNAME}"

    chmod 600 "$certs_dir"/*

    # Update Traefik configuration
    local traefik_config="${JACKER_DIR}/data/traefik/traefik.yml"
    cat >> "$traefik_config" <<EOF

tls:
  certificates:
    - certFile: /certs/cert.pem
      keyFile: /certs/key.pem
EOF

    log_success "Self-signed certificate generated"
}

#########################################
# Domain Configuration
#########################################

configure_domain() {
    log_section "Domain Configuration"

    if [[ ! -f "${JACKER_DIR}/.env" ]]; then
        log_error "No configuration found. Run './jacker init' first."
        return 1
    fi

    # Load current configuration
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    echo "Current domain: ${DOMAINNAME}"
    echo "Current hostname: ${HOSTNAME}"
    echo "Current FQDN: ${PUBLIC_FQDN}"
    echo

    read -rp "New domain name [${DOMAINNAME}]: " new_domain
    new_domain="${new_domain:-${DOMAINNAME}}"

    read -rp "New hostname [${HOSTNAME}]: " new_hostname
    new_hostname="${new_hostname:-${HOSTNAME}}"

    local new_fqdn="${new_hostname}.${new_domain}"

    # Update configuration
    update_env_var "DOMAINNAME" "$new_domain"
    update_env_var "HOSTNAME" "$new_hostname"
    update_env_var "PUBLIC_FQDN" "$new_fqdn"

    log_info "Domain configuration updated"
    log_warn "You may need to update DNS records and restart services"
}

#########################################
# Secrets Management
#########################################

regenerate_secrets() {
    log_section "Regenerate Secrets"

    echo "Which secrets to regenerate?"
    echo "1. All secrets (requires service restart)"
    echo "2. OAuth secrets"
    echo "3. Database passwords"
    echo "4. API keys"
    echo "5. Cancel"
    read -rp "Choose option [5]: " secrets_choice
    secrets_choice="${secrets_choice:-5}"

    case "$secrets_choice" in
        1)
            regenerate_all_secrets
            ;;
        2)
            regenerate_oauth_secrets
            ;;
        3)
            regenerate_database_passwords
            ;;
        4)
            regenerate_api_keys
            ;;
        5)
            log_info "Cancelled"
            return
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

regenerate_all_secrets() {
    log_warn "This will regenerate ALL secrets and require service restart!"
    read -rp "Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    regenerate_oauth_secrets
    regenerate_database_passwords
    regenerate_api_keys

    log_success "All secrets regenerated"
    log_warn "Restart services with './jacker restart' for changes to take effect"
}

regenerate_oauth_secrets() {
    log_info "Regenerating OAuth secrets..."

    local oauth_secret=$(openssl rand -base64 32 | tr -d '\n')
    local cookie_secret=$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')
    local signature_key=$(openssl rand -base64 32 | tr -d '\n')

    update_env_var "OAUTH_SECRET" "$oauth_secret"
    update_env_var "OAUTH_COOKIE_SECRET" "$cookie_secret"
    update_env_var "OAUTH_SIGNATURE_KEY" "$signature_key"

    # Update secrets files
    echo "$cookie_secret" > "${JACKER_DIR}/secrets/oauth_cookie_secret"
    chmod 600 "${JACKER_DIR}/secrets/oauth_cookie_secret"

    log_success "OAuth secrets regenerated"
}

regenerate_database_passwords() {
    log_info "Regenerating database passwords..."

    log_warn "This will break database connections until services are restarted!"
    read -rp "Continue? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    local pg_password=$(openssl rand -base64 32 | tr -d '\n')
    local redis_password=$(openssl rand -base64 32 | tr -d '\n')

    update_env_var "POSTGRES_PASSWORD" "$pg_password"

    # Update secrets files
    echo "$pg_password" > "${JACKER_DIR}/secrets/postgres_password"
    echo "$redis_password" > "${JACKER_DIR}/secrets/redis_password"
    chmod 600 "${JACKER_DIR}/secrets/"*_password

    log_success "Database passwords regenerated"
}

regenerate_api_keys() {
    log_info "Regenerating API keys..."

    local cs_traefik_key=$(openssl rand -hex 32)
    local cs_iptables_key=$(openssl rand -hex 32)
    local cs_api_pass=$(openssl rand -base64 32 | tr -d '\n')

    update_env_var "CROWDSEC_TRAEFIK_BOUNCER_API_KEY" "$cs_traefik_key"
    update_env_var "CROWDSEC_IPTABLES_BOUNCER_API_KEY" "$cs_iptables_key"
    update_env_var "CROWDSEC_API_LOCAL_PASSWORD" "$cs_api_pass"

    # Update secrets files
    echo "$cs_traefik_key" > "${JACKER_DIR}/secrets/crowdsec_bouncer_key"
    echo "$cs_api_pass" > "${JACKER_DIR}/secrets/crowdsec_lapi_key"
    chmod 600 "${JACKER_DIR}/secrets/"*_key

    # Re-register bouncers with CrowdSec
    docker compose exec -T crowdsec cscli bouncers delete traefik-bouncer 2>/dev/null || true
    docker compose exec -T crowdsec cscli bouncers add traefik-bouncer -k "$cs_traefik_key" 2>/dev/null || true

    log_success "API keys regenerated"
}

#########################################
# Authentik Configuration
#########################################

configure_authentik() {
    log_section "Authentik Configuration"

    if [[ -n "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        log_info "Authentik is already configured"
        echo "1. Reconfigure Authentik"
        echo "2. Disable Authentik"
        echo "3. Cancel"
        read -rp "Choose option [3]: " auth_choice
        auth_choice="${auth_choice:-3}"
    else
        echo "Authentik is a self-hosted identity provider"
        echo "It provides advanced authentication features:"
        echo "  - Multi-factor authentication"
        echo "  - LDAP/SAML support"
        echo "  - User self-service"
        echo
        read -rp "Enable Authentik? (y/N): " enable_auth
        auth_choice="1"
    fi

    case "$auth_choice" in
        1)
            setup_authentik
            ;;
        2)
            disable_authentik
            ;;
        3)
            return
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

setup_authentik() {
    log_info "Setting up Authentik..."

    # Generate secrets
    local secret_key=$(openssl rand -base64 60 | tr -d '\n')
    local pg_password=$(openssl rand -base64 32 | tr -d '\n')

    # Update .env
    update_env_var "AUTHENTIK_VERSION" "2024.10.4"
    update_env_var "AUTHENTIK_SECRET_KEY" "$secret_key"
    update_env_var "AUTHENTIK_POSTGRES_PASSWORD" "$pg_password"
    update_env_var "AUTHENTIK_POSTGRES_DB" "authentik"
    update_env_var "AUTHENTIK_POSTGRES_USER" "authentik"
    update_env_var "AUTHENTIK_LOG_LEVEL" "info"

    # Enable in docker-compose.yml
    sed -i '/path: compose\/authentik.yml/s/^#[[:space:]]*//' "${JACKER_DIR}/docker-compose.yml"

    # Create required directories
    mkdir -p "${JACKER_DIR}/data/authentik/media"
    mkdir -p "${JACKER_DIR}/data/authentik/templates"
    mkdir -p "${JACKER_DIR}/data/authentik/certs"

    # Create database
    docker compose exec -T postgres psql -U "${POSTGRES_USER}" \
        -c "CREATE DATABASE IF NOT EXISTS authentik;" 2>/dev/null || true
    docker compose exec -T postgres psql -U "${POSTGRES_USER}" \
        -c "CREATE USER IF NOT EXISTS authentik WITH PASSWORD '${pg_password}';" 2>/dev/null || true
    docker compose exec -T postgres psql -U "${POSTGRES_USER}" \
        -c "GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;" 2>/dev/null || true

    # Start Authentik services
    docker compose up -d authentik-server authentik-worker

    log_success "Authentik configured"
    echo
    echo "Access Authentik at: https://auth.${PUBLIC_FQDN}"
    echo "Initial setup: https://auth.${PUBLIC_FQDN}/if/flow/initial-setup/"
}

disable_authentik() {
    log_warn "This will disable Authentik authentication"
    read -rp "Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    # Stop Authentik services
    docker compose stop authentik-server authentik-worker 2>/dev/null || true

    # Comment out in docker-compose.yml
    sed -i '/path: compose\/authentik.yml/s/^/#/' "${JACKER_DIR}/docker-compose.yml"

    # Clear Authentik variables
    update_env_var "AUTHENTIK_SECRET_KEY" ""
    update_env_var "AUTHENTIK_POSTGRES_PASSWORD" ""

    log_success "Authentik disabled"
}

#########################################
# Service-Specific Configuration
#########################################

configure_grafana() {
    log_section "Grafana Configuration"

    echo "Grafana Configuration Options:"
    echo "1. Configure database backend"
    echo "2. Import dashboards"
    echo "3. Configure data sources"
    echo "4. Reset admin password"
    read -rp "Choose option: " grafana_choice

    case "$grafana_choice" in
        1)
            configure_grafana_database
            ;;
        2)
            import_grafana_dashboards
            ;;
        3)
            configure_grafana_datasources
            ;;
        4)
            reset_grafana_password
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

configure_grafana_database() {
    log_info "Configuring Grafana database..."

    echo "Database backend options:"
    echo "1. SQLite (default)"
    echo "2. PostgreSQL (recommended for HA)"
    read -rp "Choose option [1]: " db_choice
    db_choice="${db_choice:-1}"

    if [[ "$db_choice" == "2" ]]; then
        # Enable PostgreSQL for Grafana
        update_env_var "GF_DATABASE_TYPE" "postgres"
        update_env_var "GF_DATABASE_HOST" "postgres:5432"
        update_env_var "GF_DATABASE_NAME" "grafana_db"
        update_env_var "GF_DATABASE_USER" "grafana"
        update_env_var "GF_DATABASE_PASSWORD" "\${POSTGRES_PASSWORD}"
        update_env_var "GF_DATABASE_SSL_MODE" "disable"

        # Create Grafana database
        docker compose exec -T postgres psql -U "${POSTGRES_USER}" \
            -c "CREATE DATABASE IF NOT EXISTS grafana_db;" 2>/dev/null || true

        log_success "PostgreSQL backend configured for Grafana"
    else
        # Use SQLite
        update_env_var "GF_DATABASE_TYPE" ""
        log_success "Using default SQLite backend"
    fi

    # Restart Grafana
    docker compose restart grafana
}

import_grafana_dashboards() {
    log_info "Importing Grafana dashboards..."

    local dashboards_dir="${JACKER_DIR}/config/grafana/provisioning/dashboards"

    # Check for existing dashboards
    if [[ -d "$dashboards_dir" ]] && ls "$dashboards_dir"/*.json &>/dev/null; then
        log_info "Found dashboards in $dashboards_dir"
        docker compose restart grafana
        log_success "Dashboards will be imported on Grafana restart"
    else
        log_warn "No dashboards found in $dashboards_dir"
        echo "Place dashboard JSON files in this directory and restart Grafana"
    fi
}

configure_grafana_datasources() {
    log_info "Configuring Grafana data sources..."

    local datasources_dir="${JACKER_DIR}/config/grafana/provisioning/datasources"
    mkdir -p "$datasources_dir"

    # Create datasources configuration
    cat > "$datasources_dir/datasources.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true

  - name: Jaeger
    type: jaeger
    access: proxy
    url: http://jaeger:16686
    editable: true
EOF

    docker compose restart grafana
    log_success "Data sources configured"
}

reset_grafana_password() {
    log_info "Resetting Grafana admin password..."

    local new_password=$(openssl rand -base64 24)
    echo "$new_password" > "${JACKER_DIR}/secrets/grafana_admin_password"
    chmod 600 "${JACKER_DIR}/secrets/grafana_admin_password"

    # Reset password via Grafana CLI
    docker compose exec -T grafana grafana-cli admin reset-admin-password "$new_password" 2>/dev/null || true

    log_success "Grafana admin password reset"
    echo "New password: $new_password"
    echo "Saved to: secrets/grafana_admin_password"
}

#########################################
# Alerting Configuration
#########################################

configure_alerting() {
    log_section "Alerting Configuration"

    echo "Alerting Options:"
    echo "1. Configure email alerts"
    echo "2. Configure Slack alerts"
    echo "3. Configure webhook alerts"
    echo "4. Test alert configuration"
    read -rp "Choose option: " alert_choice

    case "$alert_choice" in
        1)
            configure_email_alerts
            ;;
        2)
            configure_slack_alerts
            ;;
        3)
            configure_webhook_alerts
            ;;
        4)
            test_alerting
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

configure_email_alerts() {
    log_info "Configuring email alerts..."

    read -rp "SMTP Host [smtp.gmail.com]: " smtp_host
    smtp_host="${smtp_host:-smtp.gmail.com}"

    read -rp "SMTP Port [587]: " smtp_port
    smtp_port="${smtp_port:-587}"

    read -rp "SMTP Username: " smtp_user
    read -rsp "SMTP Password: " smtp_pass
    echo

    read -rp "From address: " smtp_from
    read -rp "To address: " smtp_to

    update_env_var "SMTP_HOST" "$smtp_host"
    update_env_var "SMTP_PORT" "$smtp_port"
    update_env_var "SMTP_USERNAME" "$smtp_user"
    update_env_var "SMTP_PASSWORD" "$smtp_pass"
    update_env_var "SMTP_FROM" "$smtp_from"
    update_env_var "ALERT_EMAIL_TO" "$smtp_to"

    # Update Alertmanager configuration
    update_alertmanager_config

    log_success "Email alerts configured"
}

configure_slack_alerts() {
    log_info "Configuring Slack alerts..."

    read -rp "Slack Webhook URL: " webhook_url
    read -rp "Default channel [#alerts]: " channel
    channel="${channel:-#alerts}"

    update_env_var "SLACK_WEBHOOK_URL" "$webhook_url"
    update_env_var "SLACK_CHANNEL_CRITICAL" "$channel"

    update_alertmanager_config

    log_success "Slack alerts configured"
}

configure_webhook_alerts() {
    log_info "Configuring webhook alerts..."

    read -rp "Webhook URL: " webhook_url
    update_env_var "WEBHOOK_URL_CRITICAL" "$webhook_url"

    update_alertmanager_config

    log_success "Webhook alerts configured"
}

update_alertmanager_config() {
    local config_dir="${JACKER_DIR}/config/alertmanager"
    mkdir -p "$config_dir"

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Create Alertmanager configuration
    cat > "$config_dir/alertmanager.yml" <<EOF
global:
  smtp_from: '${SMTP_FROM:-alerts@example.com}'
  smtp_smarthost: '${SMTP_HOST:-smtp.gmail.com}:${SMTP_PORT:-587}'
  smtp_auth_username: '${SMTP_USERNAME:-}'
  smtp_auth_password: '${SMTP_PASSWORD:-}'
  smtp_require_tls: ${SMTP_REQUIRE_TLS:-true}

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: critical
    - match:
        severity: warning
      receiver: warning

receivers:
  - name: 'default'
    email_configs:
      - to: '${ALERT_EMAIL_TO:-admin@example.com}'

  - name: 'critical'
    email_configs:
      - to: '${ALERT_EMAIL_CRITICAL:-admin@example.com}'
EOF

    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        cat >> "$config_dir/alertmanager.yml" <<EOF
    slack_configs:
      - api_url: '${SLACK_WEBHOOK_URL}'
        channel: '${SLACK_CHANNEL_CRITICAL:-#alerts}'
EOF
    fi

    if [[ -n "${WEBHOOK_URL_CRITICAL:-}" ]]; then
        cat >> "$config_dir/alertmanager.yml" <<EOF
    webhook_configs:
      - url: '${WEBHOOK_URL_CRITICAL}'
EOF
    fi

    cat >> "$config_dir/alertmanager.yml" <<EOF

  - name: 'warning'
    email_configs:
      - to: '${ALERT_EMAIL_WARNING:-ops@example.com}'
EOF

    # Restart Alertmanager
    docker compose restart alertmanager 2>/dev/null || true
}

test_alerting() {
    log_info "Testing alert configuration..."

    # Send test alert via Alertmanager
    docker compose exec -T alertmanager amtool alert add \
        alertname="TestAlert" \
        severity="warning" \
        message="This is a test alert from Jacker" \
        2>/dev/null || true

    log_success "Test alert sent"
    echo "Check your configured notification channels"
}

#########################################
# Utility Functions
#########################################

update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="${JACKER_DIR}/.env"

    if grep -q "^${var_name}=" "$env_file"; then
        # Update existing variable
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    else
        # Add new variable
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

backup_configuration() {
    log_info "Backing up configuration..."

    local backup_dir="${JACKER_DIR}/backups/config_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup .env file
    cp "${JACKER_DIR}/.env" "$backup_dir/"

    # Backup configuration directories
    for dir in config data/traefik/rules secrets; do
        if [[ -d "${JACKER_DIR}/$dir" ]]; then
            tar -czf "$backup_dir/$(basename $dir).tar.gz" -C "${JACKER_DIR}" "$dir"
        fi
    done

    log_success "Configuration backed up to: $backup_dir"
}

restore_configuration() {
    log_section "Restore Configuration"

    local backup_dir="${JACKER_DIR}/backups"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "No backups found"
        return 1
    fi

    echo "Available backups:"
    ls -1 "$backup_dir" | sort -r | head -10

    read -rp "Enter backup name to restore: " backup_name

    if [[ ! -d "$backup_dir/$backup_name" ]]; then
        log_error "Backup not found: $backup_name"
        return 1
    fi

    log_warn "This will overwrite current configuration!"
    read -rp "Continue? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    # Restore .env
    if [[ -f "$backup_dir/$backup_name/.env" ]]; then
        cp "$backup_dir/$backup_name/.env" "${JACKER_DIR}/.env"
    fi

    # Restore other configurations
    for archive in "$backup_dir/$backup_name"/*.tar.gz; do
        if [[ -f "$archive" ]]; then
            tar -xzf "$archive" -C "${JACKER_DIR}"
        fi
    done

    log_success "Configuration restored from: $backup_name"
    log_warn "Restart services for changes to take effect"
}

# Export functions for use by jacker CLI
export -f show_env_config
export -f edit_env_config
export -f validate_env_config
export -f configure_oauth
export -f configure_ssl
export -f configure_domain
export -f regenerate_secrets
export -f configure_authentik
export -f configure_grafana
export -f configure_alerting
export -f backup_configuration
export -f restore_configuration
