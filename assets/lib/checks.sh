#!/usr/bin/env bash
#
# checks.sh - Diagnostic and validation checks
#

# Source common functions if not already loaded
if [[ -z "${JACKER_ROOT:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Check Jacker configuration
check_config() {
    section "Checking Jacker Configuration"

    local issues=0

    # Check .env file
    if [[ ! -f "$JACKER_ROOT/.env" ]]; then
        error ".env file not found"
        ((issues++))
    else
        success ".env file exists"
        load_env

        # Check critical variables
        local required_vars=(
            "DOMAINNAME"
            "PUBLIC_FQDN"
            "DOCKERDIR"
            "DATADIR"
            "TZ"
            "PUID"
            "PGID"
        )

        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                error "$var is not set"
                ((issues++))
            else
                success "$var is configured"
            fi
        done

        # Check OAuth configuration
        if [[ -n "${OAUTH_CLIENT_ID:-}" ]]; then
            success "OAuth is configured"
            if [[ -z "${OAUTH_CLIENT_SECRET:-}" ]]; then
                error "OAuth client secret is missing"
                ((issues++))
            fi
            if [[ -z "${OAUTH_WHITELIST:-}" ]]; then
                warning "OAuth whitelist is empty"
            fi
        else
            warning "OAuth is not configured"
        fi

        # Check Let's Encrypt
        if [[ "${DOMAINNAME}" == "example.com" ]]; then
            error "Using placeholder domain (example.com)"
            ((issues++))
        fi

        if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
            error "Let's Encrypt email not configured"
            ((issues++))
        else
            success "Let's Encrypt configured"
        fi
    fi

    # Check Docker Compose configuration
    if docker compose config &>/dev/null; then
        success "Docker Compose configuration is valid"
    else
        error "Docker Compose configuration is invalid"
        docker compose config
        ((issues++))
    fi

    # Check secrets
    if [[ -f "$JACKER_ROOT/secrets/traefik_forward_oauth" ]]; then
        success "OAuth secrets file exists"
    else
        warning "OAuth secrets file not found"
    fi

    # Check acme.json
    if [[ -f "$JACKER_ROOT/data/traefik/acme/acme.json" ]]; then
        local perms=$(stat -c %a "$JACKER_ROOT/data/traefik/acme/acme.json")
        if [[ "$perms" == "600" ]]; then
            success "acme.json has correct permissions (600)"
        else
            error "acme.json has incorrect permissions: $perms (should be 600)"
            ((issues++))
        fi
    else
        warning "acme.json not found (will be created on first run)"
    fi

    echo
    if [[ $issues -eq 0 ]]; then
        success "Configuration check passed"
        return 0
    else
        error "Found $issues configuration issue(s)"
        return 1
    fi
}

# Check network connectivity
check_network() {
    section "Checking Network Connectivity"

    local issues=0

    # Check Docker network
    if docker network ls | grep -q traefik_proxy; then
        success "Docker network 'traefik_proxy' exists"
    else
        error "Docker network 'traefik_proxy' not found"
        ((issues++))
    fi

    # Check DNS resolution
    load_env
    if [[ -n "${PUBLIC_FQDN:-}" ]]; then
        if host "${PUBLIC_FQDN}" &>/dev/null; then
            success "DNS resolves for ${PUBLIC_FQDN}"
            local ip=$(dig +short "${PUBLIC_FQDN}" | head -1)
            info "Resolves to: $ip"
        else
            error "DNS does not resolve for ${PUBLIC_FQDN}"
            ((issues++))
        fi
    fi

    # Check ports
    local ports=(80 443)
    for port in "${ports[@]}"; do
        if lsof -i ":$port" &>/dev/null; then
            success "Port $port is in use (good)"
        else
            warning "Port $port is not in use"
        fi
    done

    # Check external connectivity
    if curl -s --max-time 5 https://api.github.com &>/dev/null; then
        success "External internet connectivity OK"
    else
        error "Cannot reach external services"
        ((issues++))
    fi

    # Check internal service communication
    if is_container_running traefik; then
        if docker exec traefik wget -q -O /dev/null http://socket-proxy:2375/version; then
            success "Internal service communication OK"
        else
            error "Internal service communication failed"
            ((issues++))
        fi
    fi

    echo
    if [[ $issues -eq 0 ]]; then
        success "Network check passed"
        return 0
    else
        error "Found $issues network issue(s)"
        return 1
    fi
}

# Check PostgreSQL status
check_postgres() {
    section "Checking PostgreSQL Status"

    local issues=0

    if ! is_container_running postgres; then
        error "PostgreSQL container not running"
        return 1
    fi

    success "PostgreSQL container is running"

    load_env

    # Check database connection
    if docker exec postgres pg_isready -U "${POSTGRES_USER:-postgres}" &>/dev/null; then
        success "PostgreSQL is accepting connections"
    else
        error "PostgreSQL is not accepting connections"
        ((issues++))
    fi

    # Check CrowdSec database
    local db_exists=$(docker exec postgres psql -U "${POSTGRES_USER:-postgres}" -tc \
        "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB:-crowdsec_db}'" 2>/dev/null | grep -c 1)

    if [[ "$db_exists" -eq 1 ]]; then
        success "CrowdSec database exists"
    else
        warning "CrowdSec database does not exist"
        info "Run: jacker fix crowdsec"
    fi

    # Check database size
    local db_size=$(docker exec postgres psql -U "${POSTGRES_USER:-postgres}" -tc \
        "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB:-crowdsec_db}'))" 2>/dev/null | xargs)
    if [[ -n "$db_size" ]]; then
        info "Database size: $db_size"
    fi

    echo
    if [[ $issues -eq 0 ]]; then
        success "PostgreSQL check passed"
        return 0
    else
        error "Found $issues PostgreSQL issue(s)"
        return 1
    fi
}

# Check environment variables
check_env() {
    section "Checking Environment Variables"

    if [[ ! -f "$JACKER_ROOT/.env" ]]; then
        error ".env file not found"
        return 1
    fi

    load_env

    # Group variables by category
    echo
    subsection "Core Settings"
    echo "DOMAINNAME=${DOMAINNAME:-<not set>}"
    echo "PUBLIC_FQDN=${PUBLIC_FQDN:-<not set>}"
    echo "SERVER_IP=${SERVER_IP:-<not set>}"
    echo "TZ=${TZ:-<not set>}"
    echo "PUID=${PUID:-<not set>}"
    echo "PGID=${PGID:-<not set>}"

    echo
    subsection "Directories"
    echo "USERDIR=${USERDIR:-<not set>}"
    echo "DOCKERDIR=${DOCKERDIR:-<not set>}"
    echo "DATADIR=${DATADIR:-<not set>}"

    echo
    subsection "OAuth Configuration"
    if [[ -n "${OAUTH_CLIENT_ID:-}" ]]; then
        echo "OAUTH_CLIENT_ID=***${OAUTH_CLIENT_ID: -4}"
        echo "OAUTH_CLIENT_SECRET=***${OAUTH_CLIENT_SECRET: -4}"
        echo "OAUTH_WHITELIST=${OAUTH_WHITELIST:-<not set>}"
    else
        echo "OAuth not configured"
    fi

    echo
    subsection "Database"
    echo "POSTGRES_USER=${POSTGRES_USER:-<not set>}"
    echo "POSTGRES_DB=${POSTGRES_DB:-<not set>}"
    if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
        echo "POSTGRES_PASSWORD=***${POSTGRES_PASSWORD: -4}"
    else
        echo "POSTGRES_PASSWORD=<not set>"
    fi

    echo
    subsection "Let's Encrypt"
    echo "LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-<not set>}"

    # Validate critical settings
    echo
    local valid=true
    if [[ "${DOMAINNAME}" == "example.com" ]]; then
        error "Using placeholder domain"
        valid=false
    fi

    if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
        warning "Let's Encrypt email not set"
    fi

    if $valid; then
        success "Environment variables are configured"
        return 0
    else
        return 1
    fi
}

# Run all checks
check_all() {
    section "Running All Diagnostic Checks"

    local failed=0

    # Run each check
    for check in check_config check_network check_postgres check_env; do
        if ! $check; then
            ((failed++))
        fi
        echo
    done

    # Summary
    if [[ $failed -eq 0 ]]; then
        success "All checks passed"
        return 0
    else
        error "$failed check(s) failed"
        return 1
    fi
}