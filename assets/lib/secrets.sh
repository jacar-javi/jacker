#!/usr/bin/env bash
#
# secrets.sh - Docker Secrets Management Library
# Handles generation and management of Docker secrets
#

# Source common library
# shellcheck source=assets/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================================
# Secrets Configuration
# ============================================================================

# Get secrets directory
get_secrets_dir() {
    local jacker_root="$(get_jacker_root)"
    echo "$jacker_root/secrets"
}

# Ensure secrets directory exists with correct permissions
init_secrets_dir() {
    local secrets_dir="$(get_secrets_dir)"

    ensure_dir "$secrets_dir"
    chmod 700 "$secrets_dir"

    # Create .gitignore to prevent secrets from being committed
    cat > "$secrets_dir/.gitignore" << 'EOF'
# Ignore all secrets
*
!.gitignore
!README.md
EOF

    # Create README
    cat > "$secrets_dir/README.md" << 'EOF'
# Docker Secrets Directory

This directory contains sensitive data used by Docker services as secrets.

**IMPORTANT**: Never commit these files to git. They contain passwords, API keys, and other sensitive information.

## Files

- `oauth_client_secret` - Google OAuth client secret
- `oauth_cookie_secret` - OAuth2-proxy cookie secret
- `postgres_password` - PostgreSQL database password
- `redis_password` - Redis cache password
- `crowdsec_lapi_key` - CrowdSec LAPI key
- `crowdsec_bouncer_key` - CrowdSec bouncer API key
- `grafana_admin_password` - Grafana admin password
- `alertmanager_gmail_password` - AlertManager Gmail app password
- `authentik_secret_key` - Authentik secret key (optional)
- `authentik_postgres_password` - Authentik database password (optional)
- `authentik_api_token` - Authentik API token (optional)
- `portainer_secret` - Portainer agent secret
- `traefik_forward_oauth` - Traefik OAuth forward secret

## Security

- Directory permissions: 700 (owner only)
- File permissions: 600 (owner read/write only)
- Never share these files
- Regenerate if compromised
EOF
}

# ============================================================================
# Secret Generation Functions
# ============================================================================

# Generate a random password
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Generate a hex secret
generate_hex_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Generate OAuth cookie secret (32 bytes base64)
generate_oauth_cookie_secret() {
    # OAuth2-proxy requires exactly 32 bytes
    openssl rand -base64 32 | tr -d '\n'
}

# Write secret to file with correct permissions
write_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secrets_dir="$(get_secrets_dir)"
    local secret_file="$secrets_dir/$secret_name"

    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"

    success "Created secret: $secret_name"
}

# Read secret from file
read_secret() {
    local secret_name="$1"
    local secrets_dir="$(get_secrets_dir)"
    local secret_file="$secrets_dir/$secret_name"

    if [[ -f "$secret_file" ]]; then
        cat "$secret_file"
    else
        return 1
    fi
}

# Check if secret exists
secret_exists() {
    local secret_name="$1"
    local secrets_dir="$(get_secrets_dir)"
    local secret_file="$secrets_dir/$secret_name"

    [[ -f "$secret_file" ]]
}

# ============================================================================
# Secrets Migration Functions
# ============================================================================

# Migrate secrets from .env to files
migrate_env_to_secrets() {
    section "Migrating secrets from .env to Docker secrets"

    local secrets_dir="$(get_secrets_dir)"
    init_secrets_dir

    # Load environment variables
    if [[ -f ".env" ]]; then
        load_env
    else
        error ".env file not found"
        return 1
    fi

    # OAuth secrets
    if [[ -n "${OAUTH_CLIENT_SECRET:-}" ]]; then
        write_secret "oauth_client_secret" "$OAUTH_CLIENT_SECRET"
    fi

    if [[ -n "${OAUTH_COOKIE_SECRET:-}" ]]; then
        write_secret "oauth_cookie_secret" "$OAUTH_COOKIE_SECRET"
    else
        # Generate if not exists
        local cookie_secret="$(generate_oauth_cookie_secret)"
        write_secret "oauth_cookie_secret" "$cookie_secret"
    fi

    # Database passwords
    if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
        write_secret "postgres_password" "$POSTGRES_PASSWORD"
    fi

    if [[ -n "${REDIS_PASSWORD:-}" ]]; then
        write_secret "redis_password" "$REDIS_PASSWORD"
    fi

    # CrowdSec keys
    if [[ -n "${CROWDSEC_LAPI_KEY:-}" ]]; then
        write_secret "crowdsec_lapi_key" "$CROWDSEC_LAPI_KEY"
    fi

    if [[ -n "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY:-}" ]]; then
        write_secret "crowdsec_bouncer_key" "$CROWDSEC_TRAEFIK_BOUNCER_API_KEY"
    fi

    # Monitoring passwords
    if [[ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        write_secret "grafana_admin_password" "$GRAFANA_ADMIN_PASSWORD"
    fi

    if [[ -n "${ALERTMANAGER_GMAIL_APP_PASSWORD:-}" ]]; then
        write_secret "alertmanager_gmail_password" "$ALERTMANAGER_GMAIL_APP_PASSWORD"
    fi

    # Authentik secrets (if configured)
    if [[ -n "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        write_secret "authentik_secret_key" "$AUTHENTIK_SECRET_KEY"
    fi

    if [[ -n "${AUTHENTIK_POSTGRES_PASSWORD:-}" ]]; then
        write_secret "authentik_postgres_password" "$AUTHENTIK_POSTGRES_PASSWORD"
    fi

    if [[ -n "${AUTHENTIK_API_TOKEN:-}" ]]; then
        write_secret "authentik_api_token" "$AUTHENTIK_API_TOKEN"
    fi

    # Portainer secret
    if [[ -n "${PORTAINER_SECRET:-}" ]]; then
        write_secret "portainer_secret" "$PORTAINER_SECRET"
    fi

    # Traefik OAuth forward
    if [[ -n "${TRAEFIK_FORWARD_OAUTH_SECRET:-}" ]]; then
        write_secret "traefik_forward_oauth" "$TRAEFIK_FORWARD_OAUTH_SECRET"
    fi

    success "Secrets migration complete"
}

# Generate all required secrets
generate_all_secrets() {
    section "Generating Docker secrets"

    local secrets_dir="$(get_secrets_dir)"
    init_secrets_dir

    # OAuth secrets (use environment variable if available)
    if ! secret_exists "oauth_client_secret"; then
        if [[ -n "${OAUTH_CLIENT_SECRET:-}" ]]; then
            write_secret "oauth_client_secret" "$OAUTH_CLIENT_SECRET"
        elif [[ -n "${1:-}" ]]; then
            # If passed as argument (from setup.sh)
            write_secret "oauth_client_secret" "$1"
        else
            warning "OAuth client secret not found - services requiring OAuth will not work"
            warning "Add oauth_client_secret to secrets/ when you have it"
        fi
    fi

    # Generate OAuth cookie secret
    if ! secret_exists "oauth_cookie_secret"; then
        local cookie_secret="$(generate_oauth_cookie_secret)"
        write_secret "oauth_cookie_secret" "$cookie_secret"
    fi

    # Generate database passwords
    if ! secret_exists "postgres_password"; then
        local postgres_pass="$(generate_password 24)"
        write_secret "postgres_password" "$postgres_pass"
    fi

    if ! secret_exists "redis_password"; then
        local redis_pass="$(generate_password 24)"
        write_secret "redis_password" "$redis_pass"
    fi

    # Generate CrowdSec keys
    if ! secret_exists "crowdsec_lapi_key"; then
        local lapi_key="$(generate_hex_secret 32)"
        write_secret "crowdsec_lapi_key" "$lapi_key"
    fi

    if ! secret_exists "crowdsec_bouncer_key"; then
        local bouncer_key="$(generate_hex_secret 32)"
        write_secret "crowdsec_bouncer_key" "$bouncer_key"
    fi

    # Generate monitoring passwords
    if ! secret_exists "grafana_admin_password"; then
        local grafana_pass="$(generate_password 16)"
        write_secret "grafana_admin_password" "$grafana_pass"
    fi

    # Portainer secret
    if ! secret_exists "portainer_secret"; then
        local portainer_secret="$(generate_hex_secret 32)"
        write_secret "portainer_secret" "$portainer_secret"
    fi

    # Traefik forward OAuth
    if ! secret_exists "traefik_forward_oauth"; then
        local forward_secret="$(generate_hex_secret 32)"
        write_secret "traefik_forward_oauth" "$forward_secret"
    fi

    success "Secrets generation complete"
}

# Verify all required secrets exist
verify_secrets() {
    section "Verifying Docker secrets"

    local all_ok=true
    local required_secrets=(
        "postgres_password"
        "redis_password"
        "crowdsec_lapi_key"
        "crowdsec_bouncer_key"
        "grafana_admin_password"
        "oauth_cookie_secret"
        "portainer_secret"
        "traefik_forward_oauth"
    )

    for secret in "${required_secrets[@]}"; do
        if secret_exists "$secret"; then
            success "✓ $secret"
        else
            error "✗ $secret - missing"
            all_ok=false
        fi
    done

    # Optional secrets
    local optional_secrets=(
        "oauth_client_secret"
        "alertmanager_gmail_password"
        "authentik_secret_key"
        "authentik_postgres_password"
        "authentik_api_token"
    )

    echo ""
    info "Optional secrets:"
    for secret in "${optional_secrets[@]}"; do
        if secret_exists "$secret"; then
            success "✓ $secret"
        else
            warning "○ $secret - not configured"
        fi
    done

    if [[ "$all_ok" == true ]]; then
        success "All required secrets are present"
        return 0
    else
        error "Some required secrets are missing"
        return 1
    fi
}

# Clean up old environment variables from .env
cleanup_env_secrets() {
    section "Cleaning up secrets from .env"

    if [[ ! -f ".env" ]]; then
        warning ".env file not found"
        return 0
    fi

    # Create backup
    cp .env ".env.backup.$(date +%Y%m%d_%H%M%S)"

    # Remove sensitive variables
    local sensitive_vars=(
        "OAUTH_CLIENT_SECRET"
        "OAUTH_COOKIE_SECRET"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "CROWDSEC_LAPI_KEY"
        "CROWDSEC_TRAEFIK_BOUNCER_API_KEY"
        "CROWDSEC_FIREWALL_BOUNCER_API_KEY"
        "CROWDSEC_CLOUDFLARE_BOUNCER_API_KEY"
        "GRAFANA_ADMIN_PASSWORD"
        "ALERTMANAGER_GMAIL_APP_PASSWORD"
        "AUTHENTIK_SECRET_KEY"
        "AUTHENTIK_POSTGRES_PASSWORD"
        "AUTHENTIK_API_TOKEN"
        "PORTAINER_SECRET"
        "TRAEFIK_FORWARD_OAUTH_SECRET"
    )

    for var in "${sensitive_vars[@]}"; do
        sed -i "/^$var=/d" .env
    done

    # Add comment about secrets
    if ! grep -q "# Secrets are now managed via Docker secrets" .env; then
        echo "" >> .env
        echo "# Secrets are now managed via Docker secrets in the secrets/ directory" >> .env
        echo "# Run 'make secrets' to manage secrets" >> .env
    fi

    success "Cleaned up sensitive variables from .env"
    info "Backup created: .env.backup.$(date +%Y%m%d_%H%M%S)"
}

# ============================================================================
# Export Functions
# ============================================================================

export -f get_secrets_dir init_secrets_dir
export -f generate_password generate_hex_secret generate_oauth_cookie_secret
export -f write_secret read_secret secret_exists
export -f migrate_env_to_secrets generate_all_secrets verify_secrets cleanup_env_secrets