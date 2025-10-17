#!/usr/bin/env bash
# ==============================================================================
# Jacker Secrets Initialization Script
# ==============================================================================
# This script initializes Docker secrets from environment variables or generates
# new secure random values. It reads from .env file and creates individual
# secret files in the secrets/ directory.
#
# Usage:
#   ./scripts/init-secrets.sh [--force] [--rotate]
#
# Options:
#   --force    Overwrite existing secrets (WARNING: use with caution)
#   --rotate   Rotate all secrets with new random values
#
# Security Notice:
#   - After initial setup, rotate all production credentials
#   - Never commit secrets/ directory contents to version control
#   - Use strong, unique passwords for production environments
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Configuration
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_DIR="${PROJECT_ROOT}/secrets"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FORCE_OVERWRITE=false
ROTATE_SECRETS=false

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Generate a secure random string
generate_random() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d '\n'
}

# Generate a hex string
generate_hex() {
    local length="${1:-32}"
    openssl rand -hex "$length" | tr -d '\n'
}

# Create a secret file with proper permissions
create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local secret_file="${SECRETS_DIR}/${secret_name}"

    if [[ -f "$secret_file" ]] && [[ "$FORCE_OVERWRITE" != true ]] && [[ "$ROTATE_SECRETS" != true ]]; then
        log_info "Secret already exists: ${secret_name} (skipping)"
        return 0
    fi

    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"

    if [[ "$ROTATE_SECRETS" == true ]]; then
        log_success "Rotated secret: ${secret_name}"
    else
        log_success "Created secret: ${secret_name}"
    fi
}

# Load environment variable or use default
get_env_or_generate() {
    local var_name="$1"
    local default_value="${2:-}"
    local generator="${3:-generate_random}"

    # Try to load from .env file
    if [[ -f "$ENV_FILE" ]]; then
        local value
        value=$(grep "^${var_name}=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"' | tr -d "'")

        if [[ -n "$value" ]] && [[ "$value" != "changeme_"* ]] && [[ "$ROTATE_SECRETS" != true ]]; then
            echo "$value"
            return 0
        fi
    fi

    # Generate new value if not in env or rotating
    if [[ -n "$default_value" ]]; then
        echo "$default_value"
    else
        $generator
    fi
}

# ==============================================================================
# Parse Command Line Arguments
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        --rotate)
            ROTATE_SECRETS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--rotate]"
            echo ""
            echo "Options:"
            echo "  --force    Overwrite existing secrets"
            echo "  --rotate   Rotate all secrets with new values"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Pre-flight Checks
# ==============================================================================

log_info "Starting secrets initialization..."
log_info "Project root: ${PROJECT_ROOT}"
log_info "Secrets directory: ${SECRETS_DIR}"

# Create secrets directory if it doesn't exist
if [[ ! -d "$SECRETS_DIR" ]]; then
    log_info "Creating secrets directory..."
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
fi

# Verify secrets directory permissions
if [[ $(stat -c %a "$SECRETS_DIR" 2>/dev/null || stat -f %A "$SECRETS_DIR" 2>/dev/null) != "700" ]]; then
    log_warning "Fixing secrets directory permissions..."
    chmod 700 "$SECRETS_DIR"
fi

# Warning for rotation
if [[ "$ROTATE_SECRETS" == true ]]; then
    log_warning "ROTATION MODE ENABLED - All secrets will be regenerated!"
    log_warning "This will require restarting all services and may cause downtime."
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Rotation cancelled."
        exit 0
    fi
fi

# Warning for force overwrite
if [[ "$FORCE_OVERWRITE" == true ]]; then
    log_warning "FORCE MODE ENABLED - Existing secrets will be overwritten!"
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled."
        exit 0
    fi
fi

# ==============================================================================
# Initialize Secrets
# ==============================================================================

log_info ""
log_info "Initializing secrets from environment variables or generating new ones..."
log_info ""

# OAuth Secrets
log_info "--- OAuth Secrets ---"
create_secret "oauth_client_secret" "$(get_env_or_generate "OAUTH_CLIENT_SECRET")"
create_secret "oauth_cookie_secret" "$(get_env_or_generate "OAUTH_COOKIE_SECRET")"
create_secret "traefik_forward_oauth" "$(get_env_or_generate "OAUTH_SECRET")"

# Database & Cache Secrets
log_info ""
log_info "--- Database & Cache Secrets ---"
create_secret "postgres_password" "$(get_env_or_generate "POSTGRES_PASSWORD")"
create_secret "redis_password" "$(get_env_or_generate "REDIS_PASSWORD")"
create_secret "redis_oauth_password" "$(get_env_or_generate "REDIS_OAUTH_PASSWORD")"
create_secret "redis_ratelimit_password" "$(get_env_or_generate "REDIS_RATELIMIT_PASSWORD")"
create_secret "redis_exporter_password" "$(get_env_or_generate "REDIS_EXPORTER_PASSWORD")"

# CrowdSec Secrets
log_info ""
log_info "--- CrowdSec Secrets ---"
create_secret "crowdsec_lapi_key" "$(get_env_or_generate "CROWDSEC_API_LOCAL_PASSWORD")"
create_secret "crowdsec_bouncer_key" "$(get_env_or_generate "CROWDSEC_TRAEFIK_BOUNCER_API_KEY")"

# Monitoring Secrets
log_info ""
log_info "--- Monitoring Secrets ---"
create_secret "grafana_admin_password" "$(get_env_or_generate "GF_SECURITY_ADMIN_PASSWORD")"
create_secret "alertmanager_gmail_password" "$(get_env_or_generate "SMTP_PASSWORD" "" generate_random)"

# Service Secrets
log_info ""
log_info "--- Service Secrets ---"
create_secret "portainer_secret" "$(get_env_or_generate "PORTAINER_ADMIN_PASSWORD" "" generate_random)"

# Authentik Secrets (optional)
if [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]]; then
    log_info ""
    log_info "--- Authentik Secrets (Optional) ---"
    create_secret "authentik_secret_key" "$(get_env_or_generate "AUTHENTIK_SECRET_KEY" "" "generate_random 60")"
    create_secret "authentik_postgres_password" "$(get_env_or_generate "AUTHENTIK_POSTGRES_PASSWORD")"
    create_secret "authentik_api_token" "$(get_env_or_generate "AUTHENTIK_API_TOKEN" "" generate_hex)"
fi

# ==============================================================================
# Post-initialization Tasks
# ==============================================================================

log_info ""
log_info "--- Verifying Secrets ---"

# Count created secrets
SECRET_COUNT=$(find "$SECRETS_DIR" -type f ! -name "README.md" ! -name ".gitignore" ! -name ".gitkeep" | wc -l)
log_success "Total secrets created: ${SECRET_COUNT}"

# Verify permissions
log_info "Verifying file permissions..."
find "$SECRETS_DIR" -type f ! -name "README.md" ! -name ".gitignore" ! -name ".gitkeep" -exec chmod 600 {} \;

# List all secrets (not showing values)
log_info ""
log_info "--- Secret Files Created ---"
ls -lh "$SECRETS_DIR" | grep -v "^total" | grep -v "README.md" | grep -v ".gitignore" | grep -v ".gitkeep" || true

# ==============================================================================
# Security Warnings and Next Steps
# ==============================================================================

log_info ""
log_success "========================================================================"
log_success "Secrets initialization complete!"
log_success "========================================================================"
log_info ""

if [[ "$ROTATE_SECRETS" != true ]]; then
    log_warning "IMPORTANT SECURITY NOTICES:"
    log_warning ""
    log_warning "1. PRODUCTION DEPLOYMENT:"
    log_warning "   - Review all generated secrets and replace test/weak values"
    log_warning "   - Generate OAuth client secret from your provider"
    log_warning "   - Set strong unique passwords for all services"
    log_warning ""
    log_warning "2. CREDENTIAL ROTATION:"
    log_warning "   - Rotate all secrets after initial setup: ./scripts/init-secrets.sh --rotate"
    log_warning "   - Establish a regular rotation schedule (monthly/quarterly)"
    log_warning ""
    log_warning "3. BACKUP:"
    log_warning "   - Backup secrets directory in encrypted form"
    log_warning "   - Example: tar -czf - secrets/ | gpg --symmetric > secrets-backup.tar.gz.gpg"
    log_warning ""
    log_warning "4. ACCESS CONTROL:"
    log_warning "   - Never commit secrets to version control (.gitignore already configured)"
    log_warning "   - Restrict access to secrets directory (chmod 700)"
    log_warning "   - Use secret scanning tools to detect exposed credentials"
else
    log_warning "ROTATION COMPLETE - RESTART REQUIRED:"
    log_warning "All services must be restarted to use the new secrets:"
    log_warning "  docker compose down"
    log_warning "  docker compose up -d"
fi

log_info ""
log_info "Next steps:"
log_info "  1. Review secrets in: ${SECRETS_DIR}"
log_info "  2. Update OAuth client secret with production values"
log_info "  3. Run: docker compose config (to validate configuration)"
log_info "  4. Run: docker compose up -d (to start services)"
log_info ""
log_success "For more information, see: docs/SECRETS_MANAGEMENT.md"
log_info ""
