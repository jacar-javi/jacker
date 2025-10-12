#!/bin/bash
# validate-socket-proxy.sh - Validates Docker Socket Proxy integration with Jacker components
# This script checks that all services are properly configured to use socket-proxy instead of direct Docker socket access

set -euo pipefail

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi
cd "$JACKER_DIR" || exit 1

# Source .env file if it exists
if [[ -f .env ]]; then
    source .env
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Results tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

    case $status in
        "PASS")
            echo -e "${GREEN}✓${NC} $message"
            ((PASSED_CHECKS++))
            ;;
        "FAIL")
            echo -e "${RED}✗${NC} $message"
            ((FAILED_CHECKS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠${NC} $message"
            ((WARNINGS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
        "HEADER")
            echo -e "\n${BLUE}═══ $message ═══${NC}"
            ;;
    esac

    if [[ "$status" != "INFO" && "$status" != "HEADER" ]]; then
        ((TOTAL_CHECKS++))
    fi
}

echo "======================================"
echo "Docker Socket Proxy Validation"
echo "======================================"
echo "Validating socket-proxy integration across all Jacker services"

# 1. Check socket-proxy configuration
print_status "HEADER" "Socket Proxy Configuration"

# Check if socket-proxy.yml exists
if [[ -f compose/socket-proxy.yml ]]; then
    print_status "PASS" "Socket proxy compose file exists"
else
    print_status "FAIL" "Socket proxy compose file not found"
fi

# Check socket-proxy service configuration
if grep -q "image: tecnativa/docker-socket-proxy" compose/socket-proxy.yml 2>/dev/null; then
    print_status "PASS" "Using official tecnativa/docker-socket-proxy image"
else
    print_status "FAIL" "Not using official tecnativa/docker-socket-proxy image"
fi

# Check if Docker socket is properly mounted
if grep -q "/var/run/docker.sock:/var/run/docker.sock" compose/socket-proxy.yml 2>/dev/null; then
    print_status "PASS" "Docker socket mounted in socket-proxy"
else
    print_status "FAIL" "Docker socket not mounted in socket-proxy"
fi

# Check socket-proxy permissions
print_status "HEADER" "Socket Proxy Permissions"

declare -A required_permissions=(
    ["CONTAINERS"]="1"  # Required for Traefik, Portainer, Promtail, Authentik
    ["IMAGES"]="1"      # Required for Portainer
    ["NETWORKS"]="1"    # Required for Portainer
    ["SERVICES"]="1"    # Required for Portainer
    ["TASKS"]="1"       # Required for Portainer
    ["VOLUMES"]="1"     # Required for Portainer
    ["INFO"]="1"        # Required for Portainer, Traefik
    ["PING"]="1"        # Required for health checks
    ["VERSION"]="1"     # Required for version checks
    ["EVENTS"]="1"      # Required for event monitoring
    ["POST"]="1"        # Required for Watchtower updates
)

for perm in "${!required_permissions[@]}"; do
    expected="${required_permissions[$perm]}"
    if grep -q "- ${perm}=${expected}" compose/socket-proxy.yml 2>/dev/null; then
        print_status "PASS" "Permission ${perm}=${expected} correctly set"
    else
        print_status "WARN" "Permission ${perm} may not be set to ${expected}"
    fi
done

# Security-critical permissions that should be disabled
declare -A forbidden_permissions=(
    ["AUTH"]="0"
    ["SECRETS"]="0"
    ["BUILD"]="0"
    ["COMMIT"]="0"
    ["CONFIGS"]="0"
    ["EXEC"]="0"
)

for perm in "${!forbidden_permissions[@]}"; do
    if grep -q "- ${perm}=0" compose/socket-proxy.yml 2>/dev/null || ! grep -q "- ${perm}=1" compose/socket-proxy.yml 2>/dev/null; then
        print_status "PASS" "Security permission ${perm} is disabled"
    else
        print_status "FAIL" "Security permission ${perm} should be disabled"
    fi
done

# 2. Check Traefik integration
print_status "HEADER" "Traefik Integration"

# Check if Traefik uses socket-proxy
if grep -q "endpoint: tcp://socket-proxy:2375" data/traefik/traefik.yml 2>/dev/null; then
    print_status "PASS" "Traefik configured to use socket-proxy"
else
    print_status "FAIL" "Traefik not configured to use socket-proxy"
fi

# Check Traefik depends on socket-proxy
if grep -q "socket-proxy:" compose/traefik.yml 2>/dev/null && grep -q "condition: service_healthy" compose/traefik.yml 2>/dev/null; then
    print_status "PASS" "Traefik depends on socket-proxy health"
else
    print_status "WARN" "Traefik dependency on socket-proxy not properly configured"
fi

# Check Traefik networks
if grep -q "socket_proxy:" compose/traefik.yml 2>/dev/null; then
    print_status "PASS" "Traefik connected to socket_proxy network"
else
    print_status "FAIL" "Traefik not connected to socket_proxy network"
fi

# 3. Check Portainer integration
print_status "HEADER" "Portainer Integration"

# Check if Portainer uses socket-proxy
if grep -q "command: -H tcp://socket-proxy:2375" compose/portainer.yml 2>/dev/null; then
    print_status "PASS" "Portainer configured to use socket-proxy"
else
    print_status "FAIL" "Portainer not configured to use socket-proxy"
fi

# Check Portainer networks
if grep -q "socket_proxy" compose/portainer.yml 2>/dev/null; then
    print_status "PASS" "Portainer connected to socket_proxy network"
else
    print_status "FAIL" "Portainer not connected to socket_proxy network"
fi

# 4. Check Homepage integration
print_status "HEADER" "Homepage Integration"

# Check Homepage Docker configuration
if [[ -f data/homepage/docker.yaml ]]; then
    if grep -q "host: socket-proxy" data/homepage/docker.yaml 2>/dev/null && grep -q "port: 2375" data/homepage/docker.yaml 2>/dev/null; then
        print_status "PASS" "Homepage configured to use socket-proxy"
    else
        print_status "FAIL" "Homepage not configured to use socket-proxy"
    fi
else
    print_status "WARN" "Homepage docker.yaml not found"
fi

# Check Homepage networks
if grep -q "socket_proxy" compose/homepage.yml 2>/dev/null; then
    print_status "PASS" "Homepage connected to socket_proxy network"
else
    print_status "FAIL" "Homepage not connected to socket_proxy network"
fi

# 5. Check Promtail integration
print_status "HEADER" "Promtail Integration"

# Check if Promtail uses socket-proxy in config
if grep -q "host: tcp://socket-proxy:2375" data/loki/promtail-config.yml 2>/dev/null; then
    print_status "PASS" "Promtail configured to use socket-proxy for Docker discovery"
else
    print_status "FAIL" "Promtail not configured to use socket-proxy"
fi

# Check Promtail compose file
if grep -q "socket_proxy" compose/promtail.yml 2>/dev/null; then
    print_status "PASS" "Promtail connected to socket_proxy network"
else
    print_status "FAIL" "Promtail not connected to socket_proxy network"
fi

# Check if direct Docker socket mount is removed
if grep -q "^[[:space:]]*- /var/run/docker.sock:/var/run/docker.sock" compose/promtail.yml 2>/dev/null; then
    print_status "FAIL" "Promtail still has direct Docker socket mount (security risk)"
else
    print_status "PASS" "Promtail Docker socket mount properly removed"
fi

# 6. Check Authentik integration
print_status "HEADER" "Authentik Integration"

# Check if Authentik worker uses socket-proxy
if grep -q "DOCKER_HOST: tcp://socket-proxy:2375" compose/authentik.yml 2>/dev/null; then
    print_status "PASS" "Authentik worker configured to use socket-proxy"
else
    print_status "WARN" "Authentik worker may not be configured for socket-proxy (check if Authentik is enabled)"
fi

# Check Authentik networks
if grep -q "socket_proxy" compose/authentik.yml 2>/dev/null; then
    print_status "PASS" "Authentik connected to socket_proxy network"
else
    print_status "WARN" "Authentik not connected to socket_proxy network (check if Authentik is enabled)"
fi

# Check if direct Docker socket mount is removed from Authentik
if grep -q "^[[:space:]]*- /var/run/docker.sock:/var/run/docker.sock" compose/authentik.yml 2>/dev/null; then
    print_status "FAIL" "Authentik still has direct Docker socket mount (security risk)"
else
    print_status "PASS" "Authentik Docker socket mount properly removed"
fi

# 7. Check for any remaining direct Docker socket mounts
print_status "HEADER" "Security Audit"

# Find all compose files with direct Docker socket mounts
echo -e "${BLUE}ℹ${NC} Scanning for direct Docker socket mounts..."
DIRECT_MOUNTS=$(grep -l "^[[:space:]]*- /var/run/docker.sock:/var/run/docker.sock" compose/*.yml 2>/dev/null | grep -v socket-proxy.yml || true)

if [[ -z "$DIRECT_MOUNTS" ]]; then
    print_status "PASS" "No services have direct Docker socket access (except socket-proxy)"
else
    print_status "FAIL" "Services with direct Docker socket access found:"
    for file in $DIRECT_MOUNTS; do
        service=$(basename "$file" .yml)
        echo -e "  ${RED}→${NC} $service"
    done
fi

# Check network definitions
print_status "HEADER" "Network Configuration"

# Check if socket_proxy network is defined in main docker-compose.yml
if grep -q "^[[:space:]]*socket_proxy:" docker-compose.yml 2>/dev/null; then
    print_status "PASS" "socket_proxy network defined in docker-compose.yml"
else
    print_status "FAIL" "socket_proxy network not defined in docker-compose.yml"
fi

# 8. Check environment variables
print_status "HEADER" "Environment Configuration"

# Check if SOCKET_PROXY_IP is set
if [[ -n "${SOCKET_PROXY_IP:-}" ]]; then
    print_status "PASS" "SOCKET_PROXY_IP is set: $SOCKET_PROXY_IP"
else
    print_status "WARN" "SOCKET_PROXY_IP not set in environment"
fi

# Summary
echo
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo "Total checks: $TOTAL_CHECKS"
echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
if [[ $WARNINGS -gt 0 ]]; then
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
fi
if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
fi

echo
# Overall status
if [[ $FAILED_CHECKS -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ Socket proxy integration is fully secured and operational!${NC}"
        echo "All services are properly configured to use socket-proxy instead of direct Docker socket access."
        exit 0
    else
        echo -e "${YELLOW}⚠ Socket proxy integration is operational with warnings.${NC}"
        echo "Review the warnings above for potential improvements."
        exit 0
    fi
else
    echo -e "${RED}✗ Socket proxy integration has security issues.${NC}"
    echo "Please address the failed checks above to secure your Docker API access."
    echo
    echo "Common fixes:"
    echo "1. Ensure socket-proxy service is included in docker-compose.yml"
    echo "2. Update service configurations to use 'tcp://socket-proxy:2375'"
    echo "3. Remove direct Docker socket mounts from all services except socket-proxy"
    echo "4. Add socket_proxy network to services that need Docker API access"
    exit 1
fi