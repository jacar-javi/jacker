#!/bin/bash
################################################################################
# Jacker Stack Pre-Deployment Validation Script
################################################################################
# Comprehensive validation to catch permission and configuration issues
# BEFORE services start. This prevents runtime failures and data corruption.
#
# Usage: ./scripts/validate-deployment.sh
# Exit: 0 if all checks pass, non-zero if any fail
################################################################################

set -o pipefail

# ============================================================================
# Color codes and formatting
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Checkmarks
CHECK_MARK="${GREEN}✅${NC}"
CROSS_MARK="${RED}❌${NC}"
WARN_MARK="${YELLOW}⚠️${NC}"
INFO_MARK="${BLUE}ℹ️${NC}"

# ============================================================================
# Global variables
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0
VALIDATION_PASSED=0

# Arrays to track issues
declare -a ERRORS
declare -a WARNINGS
declare -a PASSED

# ============================================================================
# Utility functions
# ============================================================================

log_section() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

log_pass() {
    echo -e "  ${CHECK_MARK} $1"
    PASSED+=("$1")
    ((VALIDATION_PASSED++))
}

log_fail() {
    echo -e "  ${CROSS_MARK} $1"
    if [ -n "$2" ]; then
        echo -e "    ${YELLOW}Fix:${NC} $2"
    fi
    ERRORS+=("$1")
    ((VALIDATION_ERRORS++))
}

log_warn() {
    echo -e "  ${WARN_MARK} $1"
    if [ -n "$2" ]; then
        echo -e "    ${YELLOW}Note:${NC} $2"
    fi
    WARNINGS+=("$1")
    ((VALIDATION_WARNINGS++))
}

log_info() {
    echo -e "  ${INFO_MARK} $1"
}

# ============================================================================
# Check if running from correct directory
# ============================================================================

check_working_directory() {
    log_section "Checking Working Directory"

    log_check "Verifying script is run from project root or scripts directory"

    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        log_fail "Cannot find docker-compose.yml in $PROJECT_ROOT" \
                 "Run this script from the project root or scripts directory"
        return 1
    fi

    log_pass "Found docker-compose.yml in $PROJECT_ROOT"

    # Change to project root for all subsequent checks
    cd "$PROJECT_ROOT" || {
        log_fail "Cannot change to project root: $PROJECT_ROOT"
        return 1
    }

    log_pass "Working directory set to $PROJECT_ROOT"
}

# ============================================================================
# Environment variable validation
# ============================================================================

check_environment_variables() {
    log_section "Validating Environment Variables"

    # Check if .env exists
    log_check "Checking for .env file"
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        log_fail ".env file not found" \
                 "Copy .env.defaults to .env and configure: cp .env.defaults .env"
        return 1
    fi
    log_pass "Found .env file"

    # Source environment files
    log_check "Loading environment variables"
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env.defaults" 2>/dev/null || true
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env" 2>/dev/null || true
    set +a
    log_pass "Environment variables loaded"

    # Required variables (MUST be set and non-empty)
    local required_vars=(
        "DOCKERDIR"
        "HOSTNAME"
        "DOMAINNAME"
        "PUBLIC_FQDN"
        "LETSENCRYPT_EMAIL"
        "OAUTH_CLIENT_ID"
        "OAUTH_CLIENT_SECRET"
        "OAUTH_SECRET"
        "OAUTH_COOKIE_SECRET"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "GF_SECURITY_ADMIN_PASSWORD"
    )

    log_check "Validating required environment variables are set"
    local missing_vars=0
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_fail "Required variable $var is not set" \
                     "Set $var in .env file"
            ((missing_vars++))
        fi
    done

    if [ $missing_vars -eq 0 ]; then
        log_pass "All required environment variables are set"
    fi

    # Validate PUID and PGID are numeric
    log_check "Validating PUID and PGID are numeric"
    if ! [[ "$PUID" =~ ^[0-9]+$ ]]; then
        log_fail "PUID ($PUID) is not a valid number" \
                 "Set PUID to a numeric user ID (e.g., 1000)"
    else
        log_pass "PUID is numeric: $PUID"
    fi

    if ! [[ "$PGID" =~ ^[0-9]+$ ]]; then
        log_fail "PGID ($PGID) is not a valid number" \
                 "Set PGID to a numeric group ID (e.g., 1000)"
    else
        log_pass "PGID is numeric: $PGID"
    fi

    # Validate domain format
    log_check "Validating domain name format"
    if [[ ! "$DOMAINNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_fail "DOMAINNAME ($DOMAINNAME) is not a valid domain format" \
                 "Use format: example.com"
    else
        log_pass "DOMAINNAME format is valid: $DOMAINNAME"
    fi

    if [[ ! "$PUBLIC_FQDN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_fail "PUBLIC_FQDN ($PUBLIC_FQDN) is not a valid domain format" \
                 "Use format: server.example.com"
    else
        log_pass "PUBLIC_FQDN format is valid: $PUBLIC_FQDN"
    fi

    # Validate email format
    log_check "Validating email format"
    if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_warn "LETSENCRYPT_EMAIL ($LETSENCRYPT_EMAIL) may not be a valid email" \
                 "Verify email format is correct"
    else
        log_pass "LETSENCRYPT_EMAIL format is valid"
    fi

    # Check for default/example values that should be changed
    log_check "Checking for unchanged default values"
    local defaults_found=0

    if [ "$OAUTH_SECRET" = "CHANGE_ME" ] || [ "$OAUTH_SECRET" = "changeme" ]; then
        log_fail "OAUTH_SECRET is still set to default value" \
                 "Generate a random secret: openssl rand -base64 32"
        ((defaults_found++))
    fi

    if [ "$POSTGRES_PASSWORD" = "CHANGE_ME" ] || [ "$POSTGRES_PASSWORD" = "changeme" ]; then
        log_fail "POSTGRES_PASSWORD is still set to default value" \
                 "Generate a random password: openssl rand -base64 32"
        ((defaults_found++))
    fi

    if [ $defaults_found -eq 0 ]; then
        log_pass "No default values detected in critical variables"
    fi

    # Validate OAuth configuration
    log_check "Validating OAuth configuration"
    if [ "$OAUTH_PROVIDER" != "google" ] && [ "$OAUTH_PROVIDER" != "github" ] && \
       [ "$OAUTH_PROVIDER" != "oidc" ] && [ "$OAUTH_PROVIDER" != "azure" ] && \
       [ "$OAUTH_PROVIDER" != "gitlab" ]; then
        log_fail "OAUTH_PROVIDER ($OAUTH_PROVIDER) is not supported" \
                 "Set to one of: google, github, oidc, azure, gitlab"
    else
        log_pass "OAuth provider is valid: $OAUTH_PROVIDER"
    fi
}

# ============================================================================
# Directory structure and permissions validation
# ============================================================================

check_directory_permissions() {
    log_section "Validating Directory Permissions"

    # Ensure DOCKERDIR and DATADIR are set
    if [ -z "$DOCKERDIR" ]; then
        log_fail "DOCKERDIR is not set" \
                 "Set DOCKERDIR in .env file"
        return 1
    fi

    if [ -z "$DATADIR" ]; then
        DATADIR="$DOCKERDIR/data"
        log_info "DATADIR not set, using default: $DATADIR"
    fi

    # Define directory requirements
    # Format: "path:uid:gid:mode:description"
    local dir_checks=(
        "$DATADIR/traefik/plugins:1000:-:755:Traefik plugins directory"
        "$DATADIR/loki:10001:10001:755:Loki data directory"
        "$DATADIR/jaeger/badger:${PUID}:${PGID}:755:Jaeger storage directory"
        "$DATADIR/crowdsec:1000:-:755:CrowdSec data directory"
        "$DATADIR/postgres/data/pgdata:70:70:700:PostgreSQL data directory"
        "$DATADIR/redis/data:-:-:755:Redis data directory"
    )

    for check in "${dir_checks[@]}"; do
        IFS=':' read -r path uid gid mode desc <<< "$check"

        log_check "Checking $desc: $path"

        # Check if directory exists
        if [ ! -d "$path" ]; then
            log_warn "Directory does not exist: $path" \
                     "Will be created automatically, but consider: mkdir -p '$path'"
            continue
        fi

        # Check ownership if UID specified
        if [ "$uid" != "-" ]; then
            local actual_uid
            actual_uid=$(stat -c '%u' "$path" 2>/dev/null)

            if [ "$actual_uid" != "$uid" ]; then
                log_fail "Incorrect ownership on $path (found UID:$actual_uid, expected UID:$uid)" \
                         "Fix with: sudo chown -R $uid:${gid:--} '$path'"
            else
                log_pass "Ownership correct on $desc (UID:$uid)"
            fi
        fi

        # Check permissions if mode specified
        if [ "$mode" != "-" ]; then
            local actual_mode
            actual_mode=$(stat -c '%a' "$path" 2>/dev/null)

            if [ "$actual_mode" != "$mode" ]; then
                log_warn "Permissions on $path are $actual_mode (expected $mode)" \
                         "Consider: chmod $mode '$path'"
            else
                log_pass "Permissions correct on $desc ($mode)"
            fi
        fi

        # Check if writable (basic test)
        if [ -w "$path" ]; then
            log_pass "Directory is writable: $path"
        else
            log_fail "Directory is not writable: $path" \
                     "Fix permissions or ownership"
        fi
    done
}

# ============================================================================
# Configuration file validation
# ============================================================================

check_yaml_syntax() {
    log_section "Validating YAML Syntax"

    # Check if yq or python is available for YAML validation
    local yaml_validator=""
    if command -v yq &> /dev/null; then
        yaml_validator="yq"
    elif command -v python3 &> /dev/null; then
        if python3 -c "import yaml" 2>/dev/null; then
            yaml_validator="python"
        fi
    fi

    if [ -z "$yaml_validator" ]; then
        log_warn "No YAML validator found (yq or python3+pyyaml)" \
                 "Install yq or 'pip3 install pyyaml' for syntax validation"
        return 0
    fi

    log_info "Using $yaml_validator for YAML validation"

    # Find all YAML files in config/traefik/rules/
    local yaml_files
    if [ -d "$PROJECT_ROOT/config/traefik/rules" ]; then
        mapfile -t yaml_files < <(find "$PROJECT_ROOT/config/traefik/rules" -name "*.yml" -type f)
    else
        log_fail "Traefik rules directory not found: $PROJECT_ROOT/config/traefik/rules"
        return 1
    fi

    log_check "Validating ${#yaml_files[@]} YAML files in config/traefik/rules/"

    local yaml_errors=0
    for yaml_file in "${yaml_files[@]}"; do
        local file_name
        file_name=$(basename "$yaml_file")

        # Validate syntax
        if [ "$yaml_validator" = "yq" ]; then
            if yq eval '.' "$yaml_file" &>/dev/null; then
                log_pass "Valid YAML: $file_name"
            else
                log_fail "Invalid YAML syntax in $file_name" \
                         "Check file for syntax errors: yq eval '$yaml_file'"
                ((yaml_errors++))
            fi
        elif [ "$yaml_validator" = "python" ]; then
            if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                log_pass "Valid YAML: $file_name"
            else
                log_fail "Invalid YAML syntax in $file_name" \
                         "Check file for syntax errors"
                ((yaml_errors++))
            fi
        fi
    done

    if [ $yaml_errors -gt 0 ]; then
        log_fail "$yaml_errors YAML file(s) have syntax errors"
    fi

    # Validate docker-compose.yml
    log_check "Validating docker-compose.yml syntax"
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        if docker compose -f "$PROJECT_ROOT/docker-compose.yml" config &>/dev/null; then
            log_pass "docker-compose.yml is valid"
        else
            log_fail "docker-compose.yml has syntax or configuration errors" \
                     "Run: docker compose config"
        fi
    else
        log_warn "Docker Compose not available, skipping docker-compose.yml validation"
    fi
}

check_traefik_configuration() {
    log_section "Validating Traefik Configuration"

    # Check for forbidden Traefik v3 fields
    log_check "Checking for forbidden Traefik v3 fields"
    local forbidden_found=0

    local forbidden_fields=(
        "retryOn"           # Removed in v3
        "retryexpression"   # Removed in v3
        "bufferingBodyMode" # Changed in v3
    )

    if [ -d "$PROJECT_ROOT/config/traefik/rules" ]; then
        for field in "${forbidden_fields[@]}"; do
            local files_with_field
            files_with_field=$(grep -r -i "$field" "$PROJECT_ROOT/config/traefik/rules/" 2>/dev/null | grep -v "^\s*#" || true)

            if [ -n "$files_with_field" ]; then
                log_fail "Forbidden field '$field' found in Traefik rules" \
                         "Remove this field (incompatible with Traefik v3)"
                echo "$files_with_field" | while read -r line; do
                    log_info "  Found in: $line"
                done
                ((forbidden_found++))
            fi
        done
    fi

    if [ $forbidden_found -eq 0 ]; then
        log_pass "No forbidden Traefik v3 fields detected"
    fi

    # Check middleware chain references
    log_check "Validating middleware chain references"
    local chain_errors=0

    local chain_files
    if [ -d "$PROJECT_ROOT/config/traefik/rules" ]; then
        mapfile -t chain_files < <(find "$PROJECT_ROOT/config/traefik/rules" -name "chain-*.yml" -type f)
    fi

    for chain_file in "${chain_files[@]}"; do
        # Check for @file suffix inside chain definitions (incorrect)
        local file_suffix_count
        file_suffix_count=$(grep -c "@file" "$chain_file" 2>/dev/null || echo "0")

        if [ "$file_suffix_count" -gt 0 ]; then
            log_fail "Chain file $(basename "$chain_file") contains '@file' suffix" \
                     "Remove '@file' from middleware references inside chains"
            ((chain_errors++))
        else
            log_pass "Chain file $(basename "$chain_file") has correct middleware references"
        fi
    done

    if [ $chain_errors -eq 0 ] && [ ${#chain_files[@]} -gt 0 ]; then
        log_pass "All chain files have proper middleware references"
    fi

    # Validate traefik.yml exists and has basic required sections
    log_check "Validating traefik.yml configuration"
    if [ ! -f "$PROJECT_ROOT/config/traefik/traefik.yml" ]; then
        log_fail "traefik.yml not found" \
                 "Ensure config/traefik/traefik.yml exists"
    else
        # Check for required sections
        local required_sections=("entryPoints" "providers" "api")
        local missing_sections=0

        for section in "${required_sections[@]}"; do
            if ! grep -q "^${section}:" "$PROJECT_ROOT/config/traefik/traefik.yml"; then
                log_fail "Missing required section in traefik.yml: $section"
                ((missing_sections++))
            fi
        done

        if [ $missing_sections -eq 0 ]; then
            log_pass "traefik.yml has all required sections"
        fi
    fi
}

# ============================================================================
# Secrets validation
# ============================================================================

check_secrets() {
    log_section "Validating Secrets"

    if [ -z "$SECRETSDIR" ]; then
        SECRETSDIR="$DOCKERDIR/secrets"
        log_info "SECRETSDIR not set, using default: $SECRETSDIR"
    fi

    if [ ! -d "$SECRETSDIR" ]; then
        log_fail "Secrets directory not found: $SECRETSDIR" \
                 "Create with: mkdir -p '$SECRETSDIR'"
        return 1
    fi

    log_pass "Secrets directory exists: $SECRETSDIR"

    # Required secret files
    local required_secrets=(
        "oauth_client_secret"
        "oauth_cookie_secret"
        "postgres_password"
        "redis_password"
        "grafana_admin_password"
        "crowdsec_bouncer_key"
    )

    log_check "Checking for required secret files"
    local missing_secrets=0

    for secret in "${required_secrets[@]}"; do
        local secret_file="$SECRETSDIR/$secret"

        if [ ! -f "$secret_file" ]; then
            log_fail "Secret file missing: $secret" \
                     "Create with: echo 'your-secret' > '$secret_file' && chmod 600 '$secret_file'"
            ((missing_secrets++))
        else
            # Check file permissions (should be 600 or 400)
            local perms
            perms=$(stat -c '%a' "$secret_file")

            if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
                log_warn "Secret file $secret has insecure permissions: $perms" \
                         "Fix with: chmod 600 '$secret_file'"
            else
                log_pass "Secret file exists with correct permissions: $secret ($perms)"
            fi

            # Check if file is empty
            if [ ! -s "$secret_file" ]; then
                log_fail "Secret file is empty: $secret" \
                         "Add secret content to the file"
            fi
        fi
    done

    if [ $missing_secrets -eq 0 ]; then
        log_pass "All required secret files exist"
    fi
}

# ============================================================================
# Docker validation
# ============================================================================

check_docker() {
    log_section "Validating Docker Environment"

    # Check if Docker is installed
    log_check "Checking if Docker is installed"
    if ! command -v docker &> /dev/null; then
        log_fail "Docker is not installed" \
                 "Install Docker: https://docs.docker.com/engine/install/"
        return 1
    fi
    log_pass "Docker is installed: $(docker --version)"

    # Check if Docker daemon is running
    log_check "Checking if Docker daemon is running"
    if ! docker ps &> /dev/null; then
        log_fail "Docker daemon is not running" \
                 "Start Docker service: sudo systemctl start docker"
        return 1
    fi
    log_pass "Docker daemon is running"

    # Check if Docker Compose is installed
    log_check "Checking if Docker Compose is installed"
    if ! docker compose version &> /dev/null; then
        log_fail "Docker Compose is not installed" \
                 "Install Docker Compose: https://docs.docker.com/compose/install/"
        return 1
    fi
    log_pass "Docker Compose is installed: $(docker compose version --short)"

    # Check Docker network capability
    log_check "Checking Docker network capability"
    local test_network="jacker_validation_test_$$"
    if docker network create --subnet 192.168.99.0/24 "$test_network" &>/dev/null; then
        docker network rm "$test_network" &>/dev/null
        log_pass "Docker can create custom networks"
    else
        log_fail "Docker cannot create custom networks" \
                 "Check Docker installation and permissions"
    fi

    # Check available disk space
    log_check "Checking available disk space"
    local available_space
    available_space=$(df -BG "$DATADIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')

    if [ -z "$available_space" ]; then
        log_warn "Could not determine available disk space"
    elif [ "$available_space" -lt 10 ]; then
        log_warn "Low disk space: ${available_space}G available" \
                 "Consider freeing up space (recommended: 20G+)"
    else
        log_pass "Sufficient disk space: ${available_space}G available"
    fi

    # Check if user has Docker permissions
    log_check "Checking Docker permissions"
    if docker ps &>/dev/null; then
        log_pass "Current user has Docker permissions"
    else
        log_warn "Current user may not have Docker permissions" \
                 "Add user to docker group: sudo usermod -aG docker \$USER"
    fi
}

# ============================================================================
# Network validation
# ============================================================================

check_network_configuration() {
    log_section "Validating Network Configuration"

    # Check if required network variables are set
    local network_vars=(
        "DOCKER_DEFAULT_SUBNET"
        "SOCKET_PROXY_SUBNET"
        "TRAEFIK_PROXY_SUBNET"
        "DATABASE_SUBNET"
        "MONITORING_SUBNET"
        "CACHE_SUBNET"
    )

    log_check "Checking network subnet variables"
    local missing_networks=0
    for var in "${network_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_fail "Network variable $var is not set" \
                     "Set in .env file"
            ((missing_networks++))
        fi
    done

    if [ $missing_networks -eq 0 ]; then
        log_pass "All network subnet variables are configured"
    fi

    # Validate subnet format
    log_check "Validating subnet format"
    for var in "${network_vars[@]}"; do
        local subnet="${!var}"
        if [ -n "$subnet" ]; then
            if [[ ! "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                log_fail "$var has invalid subnet format: $subnet" \
                         "Use CIDR format: 192.168.1.0/24"
            else
                log_pass "$var format is valid: $subnet"
            fi
        fi
    done
}

# ============================================================================
# Additional validations
# ============================================================================

check_port_conflicts() {
    log_section "Checking for Port Conflicts"

    # Common ports used by the stack
    local critical_ports=(
        "80:HTTP"
        "443:HTTPS"
        "5432:PostgreSQL"
        "6379:Redis"
        "3000:Grafana"
        "9090:Prometheus"
    )

    log_check "Checking if critical ports are available"
    local port_conflicts=0

    for port_desc in "${critical_ports[@]}"; do
        IFS=':' read -r port desc <<< "$port_desc"

        # Check if port is in use
        if command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                log_warn "Port $port ($desc) is already in use" \
                         "Stop conflicting service or change port in configuration"
                ((port_conflicts++))
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":$port "; then
                log_warn "Port $port ($desc) is already in use" \
                         "Stop conflicting service or change port in configuration"
                ((port_conflicts++))
            fi
        fi
    done

    if [ $port_conflicts -eq 0 ]; then
        log_pass "No port conflicts detected"
    fi
}

check_firewall_configuration() {
    log_section "Checking Firewall Configuration"

    log_check "Checking if UFW is active"
    if command -v ufw &> /dev/null; then
        if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
            log_info "UFW is active"

            # Check if required ports are allowed
            log_check "Checking UFW rules for required ports"
            local ufw_status
            ufw_status=$(sudo ufw status 2>/dev/null)

            if echo "$ufw_status" | grep -q "80/tcp.*ALLOW"; then
                log_pass "UFW allows HTTP (80/tcp)"
            else
                log_warn "UFW may not allow HTTP traffic" \
                         "Allow with: sudo ufw allow 80/tcp"
            fi

            if echo "$ufw_status" | grep -q "443/tcp.*ALLOW"; then
                log_pass "UFW allows HTTPS (443/tcp)"
            else
                log_warn "UFW may not allow HTTPS traffic" \
                         "Allow with: sudo ufw allow 443/tcp"
            fi
        else
            log_info "UFW is not active"
        fi
    else
        log_info "UFW not installed, skipping firewall checks"
    fi
}

# ============================================================================
# Summary and reporting
# ============================================================================

print_summary() {
    log_section "Validation Summary"

    echo ""
    echo -e "${BOLD}Results:${NC}"
    echo -e "  ${GREEN}✅ Passed:${NC}  $VALIDATION_PASSED"
    echo -e "  ${YELLOW}⚠️  Warnings:${NC} $VALIDATION_WARNINGS"
    echo -e "  ${RED}❌ Errors:${NC}   $VALIDATION_ERRORS"
    echo ""

    if [ $VALIDATION_ERRORS -gt 0 ]; then
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}${BOLD}VALIDATION FAILED - CRITICAL ERRORS DETECTED${NC}"
        echo -e "${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${RED}Fix the following errors before deploying:${NC}"
        echo ""
        for error in "${ERRORS[@]}"; do
            echo -e "  ${CROSS_MARK} $error"
        done
        echo ""
        echo -e "${YELLOW}DO NOT start services until all errors are resolved!${NC}"
        echo ""
        return 1
    elif [ $VALIDATION_WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}${BOLD}VALIDATION PASSED WITH WARNINGS${NC}"
        echo -e "${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${YELLOW}Review the following warnings:${NC}"
        echo ""
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${WARN_MARK} $warning"
        done
        echo ""
        echo -e "${GREEN}You may proceed with deployment, but review warnings.${NC}"
        echo ""
        return 0
    else
        echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}${BOLD}✅ ALL VALIDATIONS PASSED${NC}"
        echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "${GREEN}Your deployment configuration is valid!${NC}"
        echo -e "${GREEN}Safe to proceed with: docker compose up -d${NC}"
        echo ""
        return 0
    fi
}

# ============================================================================
# Main execution
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}║           Jacker Stack Pre-Deployment Validation                       ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                                        ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Run all validation checks
    check_working_directory || true
    check_environment_variables || true
    check_directory_permissions || true
    check_yaml_syntax || true
    check_traefik_configuration || true
    check_secrets || true
    check_docker || true
    check_network_configuration || true
    check_port_conflicts || true
    check_firewall_configuration || true

    # Print summary and exit
    print_summary
    exit $?
}

# Run main function
main "$@"
