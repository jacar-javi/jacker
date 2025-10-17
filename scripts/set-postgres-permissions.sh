#!/usr/bin/env bash
# ====================================================================
# PostgreSQL File Permissions Setup Script
# ====================================================================
# This script sets proper file permissions for PostgreSQL security-sensitive files.
#
# USAGE:
#   ./scripts/set-postgres-permissions.sh
#
# SECURITY REQUIREMENTS:
#   - pg_hba.conf: 0600 (read/write owner only)
#   - postgresql.conf: 0600 (read/write owner only)
#   - SSL certificates (.crt): 0644 (readable by all)
#   - SSL keys (.key): 0600 (read/write owner only)
#
# NOTES:
#   - This script should be run after configuration changes
#   - PostgreSQL will refuse to start if permissions are too open
#   - In Docker environments, the postgres user (UID 70 or 999) needs ownership
# ====================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source environment variables
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

# Set default values
CONFIGDIR="${CONFIGDIR:-${PROJECT_ROOT}/config}"
DATADIR="${DATADIR:-${PROJECT_ROOT}/data}"
CONFIG_DIR="${CONFIGDIR}/postgres"
SSL_DIR="${DATADIR}/postgres/ssl"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_directories() {
    log_info "Checking directory structure..."

    if [[ ! -d "${CONFIG_DIR}" ]]; then
        log_error "Configuration directory not found: ${CONFIG_DIR}"
        exit 1
    fi

    if [[ ! -d "${SSL_DIR}" ]]; then
        log_warn "SSL directory not found: ${SSL_DIR}"
        log_warn "Run: ./scripts/generate-postgres-ssl.sh to create SSL certificates"
    fi
}

set_config_permissions() {
    log_info "Setting permissions for PostgreSQL configuration files..."

    # pg_hba.conf - Authentication configuration (sensitive)
    if [[ -f "${CONFIG_DIR}/pg_hba.conf" ]]; then
        chmod 0600 "${CONFIG_DIR}/pg_hba.conf"
        log_info "Set pg_hba.conf permissions to 0600"
    else
        log_warn "File not found: ${CONFIG_DIR}/pg_hba.conf"
    fi

    # postgresql.conf - Main configuration file (sensitive)
    if [[ -f "${CONFIG_DIR}/postgresql.conf" ]]; then
        chmod 0600 "${CONFIG_DIR}/postgresql.conf"
        log_info "Set postgresql.conf permissions to 0600"
    else
        log_warn "File not found: ${CONFIG_DIR}/postgresql.conf"
    fi

    # Set directory permissions
    chmod 0755 "${CONFIG_DIR}"
    log_info "Set config directory permissions to 0755"
}

set_ssl_permissions() {
    if [[ ! -d "${SSL_DIR}" ]]; then
        log_warn "Skipping SSL permissions (directory not found)"
        return
    fi

    log_info "Setting permissions for SSL certificates and keys..."

    # CA certificate (public) - readable by all
    if [[ -f "${SSL_DIR}/ca.crt" ]]; then
        chmod 0644 "${SSL_DIR}/ca.crt"
        log_info "Set ca.crt permissions to 0644"
    fi

    # CA key (private) - readable only by owner
    if [[ -f "${SSL_DIR}/ca.key" ]]; then
        chmod 0600 "${SSL_DIR}/ca.key"
        log_info "Set ca.key permissions to 0600"
    fi

    # Server certificate (public) - readable by all
    if [[ -f "${SSL_DIR}/server.crt" ]]; then
        chmod 0644 "${SSL_DIR}/server.crt"
        log_info "Set server.crt permissions to 0644"
    fi

    # Server key (private) - readable only by owner
    if [[ -f "${SSL_DIR}/server.key" ]]; then
        chmod 0600 "${SSL_DIR}/server.key"
        log_info "Set server.key permissions to 0600"
    fi

    # Set directory permissions
    chmod 0755 "${SSL_DIR}"
    log_info "Set SSL directory permissions to 0755"
}

set_ownership() {
    log_info "Setting file ownership..."

    # Determine PostgreSQL UID/GID
    # Alpine-based images use UID 70, Debian-based use UID 999
    POSTGRES_UID="${POSTGRES_UID:-70}"
    POSTGRES_GID="${POSTGRES_GID:-70}"

    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root, setting ownership to postgres user (${POSTGRES_UID}:${POSTGRES_GID})..."

        # Try UID 70 first (Alpine), then fallback to 999 (Debian)
        if chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "${CONFIG_DIR}" 2>/dev/null; then
            log_info "Set ownership using UID ${POSTGRES_UID}"
        elif chown -R 999:999 "${CONFIG_DIR}" 2>/dev/null; then
            log_info "Set ownership using UID 999"
        else
            log_warn "Failed to set ownership. Manual intervention may be required."
        fi

        # Set SSL directory ownership if it exists
        if [[ -d "${SSL_DIR}" ]]; then
            if chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "${SSL_DIR}" 2>/dev/null; then
                log_info "Set SSL directory ownership using UID ${POSTGRES_UID}"
            elif chown -R 999:999 "${SSL_DIR}" 2>/dev/null; then
                log_info "Set SSL directory ownership using UID 999"
            else
                log_warn "Failed to set SSL directory ownership."
            fi
        fi
    else
        log_warn "Not running as root. Ownership may need to be adjusted manually."
        log_warn "Run: sudo chown -R 70:70 ${CONFIG_DIR} ${SSL_DIR}"
        log_warn "Or: sudo chown -R 999:999 ${CONFIG_DIR} ${SSL_DIR}"
    fi
}

verify_permissions() {
    log_info "Verifying file permissions..."

    local errors=0

    # Check pg_hba.conf
    if [[ -f "${CONFIG_DIR}/pg_hba.conf" ]]; then
        local perm=$(stat -c "%a" "${CONFIG_DIR}/pg_hba.conf" 2>/dev/null || stat -f "%OLp" "${CONFIG_DIR}/pg_hba.conf" 2>/dev/null)
        if [[ "${perm}" == "600" ]]; then
            log_info "pg_hba.conf permissions: OK (${perm})"
        else
            log_error "pg_hba.conf permissions: WRONG (${perm}, expected 600)"
            ((errors++))
        fi
    fi

    # Check postgresql.conf
    if [[ -f "${CONFIG_DIR}/postgresql.conf" ]]; then
        local perm=$(stat -c "%a" "${CONFIG_DIR}/postgresql.conf" 2>/dev/null || stat -f "%OLp" "${CONFIG_DIR}/postgresql.conf" 2>/dev/null)
        if [[ "${perm}" == "600" ]]; then
            log_info "postgresql.conf permissions: OK (${perm})"
        else
            log_error "postgresql.conf permissions: WRONG (${perm}, expected 600)"
            ((errors++))
        fi
    fi

    # Check SSL key permissions
    if [[ -f "${SSL_DIR}/server.key" ]]; then
        local perm=$(stat -c "%a" "${SSL_DIR}/server.key" 2>/dev/null || stat -f "%OLp" "${SSL_DIR}/server.key" 2>/dev/null)
        if [[ "${perm}" == "600" ]]; then
            log_info "server.key permissions: OK (${perm})"
        else
            log_error "server.key permissions: WRONG (${perm}, expected 600)"
            ((errors++))
        fi
    fi

    if [[ ${errors} -gt 0 ]]; then
        log_error "Permission verification failed with ${errors} error(s)"
        return 1
    else
        log_info "All permissions verified successfully"
        return 0
    fi
}

show_summary() {
    log_info "Permission setup complete!"
    echo ""
    echo "File Permissions Summary:"
    echo "========================="
    echo "Configuration Files (0600):"
    if [[ -f "${CONFIG_DIR}/pg_hba.conf" ]]; then
        ls -lh "${CONFIG_DIR}/pg_hba.conf"
    fi
    if [[ -f "${CONFIG_DIR}/postgresql.conf" ]]; then
        ls -lh "${CONFIG_DIR}/postgresql.conf"
    fi

    if [[ -d "${SSL_DIR}" ]]; then
        echo ""
        echo "SSL Certificates (0644) and Keys (0600):"
        ls -lh "${SSL_DIR}"/ 2>/dev/null || true
    fi

    echo ""
    echo "Next steps:"
    echo "1. Review the permissions above"
    echo "2. Restart PostgreSQL if it's running:"
    echo "   docker compose restart postgres"
    echo "3. Check PostgreSQL logs for any permission errors:"
    echo "   docker compose logs postgres"
}

# Main execution
main() {
    log_info "Setting PostgreSQL file permissions..."
    echo ""

    check_directories
    set_config_permissions
    set_ssl_permissions
    set_ownership

    if verify_permissions; then
        show_summary
        log_info "Done!"
        exit 0
    else
        log_error "Some permissions are incorrect. Please review and fix manually."
        exit 1
    fi
}

# Run main function
main "$@"
