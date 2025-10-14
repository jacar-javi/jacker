#!/usr/bin/env bash
set -euo pipefail

# Validation script for Jacker platform
# Checks all critical requirements before deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
PASSED=0
FAILED=0
WARNINGS=0

# Print functions
pass() { echo -e "${GREEN}✓${NC} $*"; ((PASSED++)); }
fail() { echo -e "${RED}✗${NC} $*"; ((FAILED++)); }
warn() { echo -e "${YELLOW}⚠${NC} $*"; ((WARNINGS++)); }
info() { echo "ℹ $*"; }

echo "================================"
echo "Jacker Pre-Deployment Validation"
echo "================================"
echo ""

# ==========================================
# 1. REQUIRED COMMANDS
# ==========================================
echo "Checking required commands..."

check_command() {
    if command -v "$1" &>/dev/null; then
        pass "$1 is installed"
        return 0
    else
        fail "$1 is not installed"
        return 1
    fi
}

check_command docker

# Check docker compose (v2 plugin style)
if docker compose version &>/dev/null; then
    pass "docker compose is available"
else
    fail "docker compose is not available"
fi

echo ""

# ==========================================
# 2. ENVIRONMENT FILES
# ==========================================
echo "Checking environment files..."

if [[ -f .env ]]; then
    pass ".env file exists"

    if [[ -r .env ]]; then
        pass ".env is readable"
    else
        fail ".env is not readable"
    fi

    env_perms=$(stat -c %a .env)
    if [[ "$env_perms" == "600" ]]; then
        pass ".env has correct permissions (600)"
    else
        warn ".env permissions are $env_perms, should be 600"
        info "Run: chmod 600 .env"
    fi
else
    fail ".env file not found"
    info "Create .env file from .env.example"
fi

echo ""

# ==========================================
# 3. REQUIRED ENVIRONMENT VARIABLES
# ==========================================
echo "Checking required environment variables..."

required_vars=(
    "PUBLIC_FQDN"
    "LETSENCRYPT_EMAIL"
    "OAUTH_CLIENT_ID"
    "OAUTH_CLIENT_SECRET"
)

if [[ -f .env ]]; then
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" .env 2>/dev/null; then
            value=$(grep "^${var}=" .env | cut -d= -f2-)
            # Check if value is not empty or placeholder
            if [[ -n "$value" && "$value" != "your-"* && "$value" != "example"* ]]; then
                pass "Environment variable $var is set"
            else
                fail "Environment variable $var is set but appears to be a placeholder"
            fi
        else
            fail "Environment variable $var is not set in .env"
        fi
    done
else
    for var in "${required_vars[@]}"; do
        fail "Cannot check $var - .env file missing"
    done
fi

echo ""

# ==========================================
# 4. DOCKER SECRETS
# ==========================================
echo "Checking Docker secrets..."

if [[ -d secrets ]]; then
    pass "secrets/ directory exists"

    secret_count=0
    for secret in secrets/*; do
        if [[ -f "$secret" ]]; then
            basename_secret=$(basename "$secret")
            # Skip documentation and git files
            if [[ ! "$basename_secret" =~ (README|gitignore|gitkeep) ]]; then
                ((secret_count++))
                perms=$(stat -c %a "$secret")
                if [[ "$perms" == "600" ]]; then
                    pass "$basename_secret has correct permissions (600)"
                else
                    fail "$basename_secret has incorrect permissions ($perms, should be 600)"
                    info "Run: chmod 600 secrets/$basename_secret"
                fi

                # Check if file is not empty
                if [[ -s "$secret" ]]; then
                    pass "$basename_secret is not empty"
                else
                    fail "$basename_secret is empty"
                fi
            fi
        fi
    done

    if [[ "$secret_count" -eq 0 ]]; then
        warn "No secret files found in secrets/ directory"
        info "Expected secrets: oauth_client_id, oauth_client_secret, loki_htpasswd, etc."
    fi
else
    fail "secrets/ directory not found"
    info "Create secrets/ directory and add required secret files"
fi

echo ""

# ==========================================
# 5. CONFIGURATION DIRECTORIES
# ==========================================
echo "Checking configuration directories..."

required_dirs=(
    "config"
    "config/oauth2-proxy"
    "config/promtail"
    "config/loki"
    "config/grafana"
    "config/grafana/provisioning/datasources"
    "config/grafana/provisioning/dashboards"
    "data"
)

for dir in "${required_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        pass "Directory $dir exists"
    else
        fail "Directory $dir not found"
        info "Create directory: mkdir -p $dir"
    fi
done

echo ""

# ==========================================
# 6. DOCKER COMPOSE VALIDATION
# ==========================================
echo "Checking Docker Compose configuration..."

if [[ -f docker-compose.yml ]]; then
    pass "docker-compose.yml exists"

    if docker compose config &>/dev/null; then
        pass "Docker Compose configuration is valid"
    else
        fail "Docker Compose configuration has errors"
        info "Run 'docker compose config' to see errors"
    fi
else
    fail "docker-compose.yml not found"
fi

echo ""

# ==========================================
# 7. PORT AVAILABILITY
# ==========================================
echo "Checking port availability..."

check_port() {
    local port=$1
    if command -v ss &>/dev/null; then
        if ! ss -tuln | grep -q ":${port} "; then
            pass "Port $port is available"
        else
            warn "Port $port is already in use"
            info "Check: ss -tuln | grep :$port"
        fi
    else
        warn "Cannot check port $port - 'ss' command not available"
    fi
}

check_port 80
check_port 443

echo ""

# ==========================================
# 8. DISK SPACE
# ==========================================
echo "Checking disk space..."

available_gb=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
if [[ "$available_gb" -gt 20 ]]; then
    pass "Sufficient disk space (${available_gb}GB available)"
else
    warn "Low disk space (${available_gb}GB available, 20GB recommended)"
fi

echo ""

# ==========================================
# 9. MEMORY REQUIREMENTS
# ==========================================
echo "Checking memory requirements..."

total_mem_mb=$(free -m | awk 'NR==2 {print $2}')
if [[ "$total_mem_mb" -gt 4096 ]]; then
    pass "Sufficient memory (${total_mem_mb}MB total)"
else
    warn "Limited memory (${total_mem_mb}MB total, 4GB+ recommended)"
fi

available_mem_mb=$(free -m | awk 'NR==2 {print $7}')
if [[ "$available_mem_mb" -gt 2048 ]]; then
    pass "Sufficient available memory (${available_mem_mb}MB)"
else
    warn "Limited available memory (${available_mem_mb}MB, 2GB+ recommended)"
fi

echo ""

# ==========================================
# 10. DOCKER DAEMON
# ==========================================
echo "Checking Docker daemon..."

if docker info &>/dev/null; then
    pass "Docker daemon is running"

    # Check Docker version
    docker_version=$(docker version --format '{{.Server.Version}}')
    pass "Docker version: $docker_version"
else
    fail "Docker daemon is not running"
    info "Start Docker: sudo systemctl start docker"
fi

echo ""

# ==========================================
# 11. NETWORK CONFIGURATION
# ==========================================
echo "Checking network configuration..."

if [[ -f docker-compose.yml ]] && docker compose config &>/dev/null; then
    # Check if networks are properly defined
    if docker compose config | grep -q "networks:"; then
        pass "Docker networks are configured"
    else
        warn "No Docker networks defined in compose file"
    fi
fi

echo ""

# ==========================================
# 12. CRITICAL FILES
# ==========================================
echo "Checking critical files..."

critical_files=(
    "docker-compose.yml"
    "config/oauth2-proxy/oauth2-proxy.cfg"
    "config/promtail/promtail.yml"
    "config/loki/loki.yml"
)

for file in "${critical_files[@]}"; do
    if [[ -f "$file" ]]; then
        pass "Critical file $file exists"
    else
        fail "Critical file $file not found"
    fi
done

echo ""

# ==========================================
# FINAL SUMMARY
# ==========================================
echo "================================"
echo "Validation Summary"
echo "================================"
echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [[ "$FAILED" -gt 0 ]]; then
    echo -e "${RED}Validation FAILED${NC} - Fix errors before deploying"
    echo ""
    echo "Common fixes:"
    echo "  - Run ./init-secrets.sh to create Docker secrets"
    echo "  - Copy .env.example to .env and configure"
    echo "  - Ensure Docker daemon is running"
    echo "  - Check file permissions (600 for secrets and .env)"
    echo ""
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "${YELLOW}Validation passed with warnings${NC} - Review warnings before deploying"
    echo ""
    echo "You can proceed with deployment, but consider addressing warnings."
    echo ""
    exit 0
else
    echo -e "${GREEN}All checks PASSED${NC} - Ready to deploy!"
    echo ""
    echo "Next steps:"
    echo "  1. Review configuration: docker compose config"
    echo "  2. Deploy: docker compose up -d"
    echo "  3. Check logs: docker compose logs -f"
    echo ""
    exit 0
fi
