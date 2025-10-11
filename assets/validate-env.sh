#!/usr/bin/env bash
#
# validate-env.sh - Validate and report on .env file configuration
#

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

cd_jacker_root

section "Jacker .env File Validation"

# Check if .env exists
if [ ! -f ".env" ]; then
    error ".env file not found!"
    echo ""
    echo "Run 'make install' to create configuration."
    exit 1
fi

# Check if .env.defaults exists
if [ ! -f ".env.defaults" ]; then
    error ".env.defaults file not found!"
    exit 1
fi

success ".env file exists"
echo ""

# Load .env
set -a
# shellcheck source=/dev/null
source .env
set +a

# Critical variables that must not be empty
CRITICAL_VARS=(
    "PUID"
    "PGID"
    "TZ"
    "USERDIR"
    "DOCKERDIR"
    "DATADIR"
    "HOSTNAME"
    "DOMAINNAME"
    "PUBLIC_FQDN"
    "LOCAL_IPS"
    "DOCKER_DEFAULT_SUBNET"
    "SOCKET_PROXY_SUBNET"
    "TRAEFIK_PROXY_SUBNET"
    "SOCKET_PROXY_IP"
    "TRAEFIK_PROXY_IP"
    "POSTGRES_DB"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "CROWDSEC_API_PORT"
    "CROWDSEC_TRAEFIK_BOUNCER_API_KEY"
    "CROWDSEC_IPTABLES_BOUNCER_API_KEY"
    "CROWDSEC_API_LOCAL_PASSWORD"
)

# Check critical variables
subsection "Critical Variables"

MISSING_COUNT=0
EMPTY_COUNT=0

for var in "${CRITICAL_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        error "$var is NOT SET or EMPTY"
        ((EMPTY_COUNT++))
    else
        success "$var is set"
    fi
done

echo ""

# Optional variables (warn if empty)
OPTIONAL_VARS=(
    "OAUTH_CLIENT_ID"
    "OAUTH_CLIENT_SECRET"
    "LETSENCRYPT_EMAIL"
)

subsection "Optional Variables"

for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        warning "$var is empty (optional)"
    else
        success "$var is set"
    fi
done

echo ""

# Summary
section "Validation Summary"

if [ "$EMPTY_COUNT" -gt 0 ]; then
    error "Found $EMPTY_COUNT critical variables that are missing or empty"
    echo ""
    echo "Your .env file is INVALID and services will not start correctly."
    echo ""
    echo "RECOMMENDED FIX:"
    echo "  1. Backup current .env:"
    echo "     cp .env .env.broken-backup"
    echo ""
    echo "  2. Run setup again to regenerate .env:"
    echo "     make install"
    echo ""
    echo "     Choose option [1] to reinstall (keeps existing values)"
    echo ""
    exit 1
else
    success "All critical variables are set!"
    echo ""
    info "Configuration looks valid"
    echo ""
    echo "If services still don't work, check:"
    echo "  • Docker Compose config: make validate"
    echo "  • Service logs: make logs SERVICE=traefik"
    echo "  • Network diagnostics: make diagnose"
    echo ""
fi
