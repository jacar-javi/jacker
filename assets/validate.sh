#!/usr/bin/env bash
#
# Script: validate.sh
# Description: Validate Jacker installation and configuration
# Usage: ./validate.sh
# Requirements: .env file must exist
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "=== Jacker Installation Validator ==="
echo ""

# Function to print success
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print error
error() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

# Function to print warning
warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# Check .env file
echo "=== Configuration Files ==="
if [ -f .env ]; then
    success ".env file exists"
    source .env
else
    error ".env file not found"
fi

if [ -f .env.defaults ]; then
    success ".env.defaults file exists"
else
    warning ".env.defaults file not found"
fi

# Check required environment variables
echo ""
echo "=== Environment Variables ==="
REQUIRED_VARS=(
    "HOSTNAME"
    "DOMAINNAME"
    "OAUTH_CLIENT_ID"
    "OAUTH_CLIENT_SECRET"
    "OAUTH_SECRET"
    "OAUTH_WHITELIST"
    "LETSENCRYPT_EMAIL"
    "CROWDSEC_TRAEFIK_BOUNCER_API_KEY"
    "CROWDSEC_IPTABLES_BOUNCER_API_KEY"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        success "$var is set"
    else
        error "$var is not set or empty"
    fi
done

# Check system requirements
echo ""
echo "=== System Requirements ==="

# Check Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    success "Docker installed: $DOCKER_VERSION"

    # Check Docker is running
    if docker info &> /dev/null; then
        success "Docker daemon is running"
    else
        error "Docker daemon is not running"
    fi
else
    error "Docker is not installed"
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short)
    success "Docker Compose installed: $COMPOSE_VERSION"
else
    error "Docker Compose is not installed"
fi

# Check UFW
if command -v ufw &> /dev/null; then
    success "UFW is installed"

    # Check if UFW is enabled
    if sudo ufw status | grep -q "Status: active"; then
        success "UFW is active"
    else
        warning "UFW is installed but not active"
    fi
else
    warning "UFW is not installed"
fi

# Check cscli
if command -v cscli &> /dev/null; then
    success "cscli is installed"
else
    warning "cscli is not installed"
fi

# Check directory structure
echo ""
echo "=== Directory Structure ==="

REQUIRED_DIRS=(
    "data"
    "data/traefik"
    "data/crowdsec"
    "data/grafana"
    "data/prometheus"
    "compose"
    "assets"
    "logs"
    "secrets"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        success "$dir/ exists"
    else
        warning "$dir/ does not exist"
    fi
done

# Check critical files
echo ""
echo "=== Critical Files ==="

REQUIRED_FILES=(
    "docker-compose.yml"
    "data/traefik/acme.json"
    "secrets/traefik_forward_oauth"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        success "$file exists"
    else
        error "$file does not exist"
    fi
done

# Check file permissions
echo ""
echo "=== File Permissions ==="

if [ -f "data/traefik/acme.json" ]; then
    PERMS=$(stat -c '%a' data/traefik/acme.json)
    if [ "$PERMS" = "600" ]; then
        success "acme.json has correct permissions (600)"
    else
        error "acme.json has incorrect permissions ($PERMS, should be 600)"
    fi
fi

# Check Docker networks
echo ""
echo "=== Docker Networks ==="

REQUIRED_NETWORKS=(
    "socket_proxy"
    "traefik_proxy"
)

for network in "${REQUIRED_NETWORKS[@]}"; do
    if docker network ls | grep -q "$network"; then
        success "Network $network exists"
    else
        warning "Network $network does not exist"
    fi
done

# Check running containers
echo ""
echo "=== Running Containers ==="

EXPECTED_CONTAINERS=(
    "traefik"
    "crowdsec"
    "oauth"
    "socket-proxy"
)

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        success "Container $container is running"
    else
        warning "Container $container is not running"
    fi
done

# Check port bindings
echo ""
echo "=== Port Bindings ==="

REQUIRED_PORTS=(
    "80"
    "443"
)

for port in "${REQUIRED_PORTS[@]}"; do
    if sudo netstat -tulpn 2>/dev/null | grep -q ":${port} " || sudo ss -tulpn 2>/dev/null | grep -q ":${port} "; then
        success "Port $port is in use"
    else
        warning "Port $port is not in use"
    fi
done

# Summary
echo ""
echo "=== Validation Summary ==="
echo -e "Errors: ${RED}${ERRORS}${NC}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "\n${GREEN}All checks passed!${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "\n${YELLOW}Validation passed with warnings.${NC}"
    exit 0
else
    echo -e "\n${RED}Validation failed with $ERRORS error(s).${NC}"
    exit 1
fi
