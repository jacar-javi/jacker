#!/bin/bash
# Service Health Check Script
# Validates all running services are healthy
# Created by Puto Amo Enhancement Project

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

UNHEALTHY=0
RESTARTING=0

echo "=========================================="
echo "  Service Health Check"
echo "=========================================="
echo ""

# Function to print status
print_status() {
    local service=$1
    local status=$2
    local health=$3

    case $status in
        running)
            if [[ "$health" == "healthy" ]]; then
                echo -e "${GREEN}✓${NC} $service: ${GREEN}healthy${NC}"
            elif [[ "$health" == "starting" ]]; then
                echo -e "${YELLOW}⟳${NC} $service: ${YELLOW}starting${NC}"
            elif [[ "$health" == "unhealthy" ]]; then
                echo -e "${RED}✗${NC} $service: ${RED}unhealthy${NC}"
                ((UNHEALTHY++))
            else
                echo -e "${BLUE}●${NC} $service: running (no health check)"
            fi
            ;;
        restarting)
            echo -e "${YELLOW}⟳${NC} $service: ${YELLOW}restarting${NC}"
            ((RESTARTING++))
            ;;
        exited)
            echo -e "${RED}✗${NC} $service: ${RED}stopped${NC}"
            ((UNHEALTHY++))
            ;;
        *)
            echo -e "${RED}?${NC} $service: ${RED}$status${NC}"
            ((UNHEALTHY++))
            ;;
    esac
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}ERROR: Docker command not found${NC}"
    echo "This script must run in an environment with Docker access"
    exit 1
fi

# Check if compose is available
if ! docker compose version &> /dev/null; then
    echo -e "${RED}ERROR: docker compose not available${NC}"
    exit 1
fi

# Get list of services
echo "Checking services..."
echo ""

# Parse docker compose ps output
while IFS= read -r line; do
    # Skip header line
    if [[ "$line" =~ ^NAME ]]; then
        continue
    fi

    # Parse line (format: NAME IMAGE COMMAND SERVICE CREATED STATUS PORTS)
    if [[ -n "$line" ]]; then
        service_name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $7}')

        # Extract health status if available
        health=""
        if echo "$line" | grep -q "healthy"; then
            health="healthy"
        elif echo "$line" | grep -q "unhealthy"; then
            health="unhealthy"
        elif echo "$line" | grep -q "starting"; then
            health="starting"
        fi

        print_status "$service_name" "$status" "$health"
    fi
done < <(docker compose ps --format "table {{.Name}}\t{{.Image}}\t{{.Command}}\t{{.Service}}\t{{.CreatedAt}}\t{{.Status}}\t{{.Ports}}")

# Check for services with excessive restarts
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Restart Count Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

while IFS= read -r line; do
    container_id=$(echo "$line" | awk '{print $1}')
    container_name=$(echo "$line" | awk '{print $2}')
    restart_count=$(docker inspect "$container_id" --format='{{.RestartCount}}' 2>/dev/null || echo "0")

    if [[ $restart_count -gt 5 ]]; then
        echo -e "${RED}⚠${NC} $container_name: ${RED}$restart_count restarts${NC} (check logs!)"
        ((UNHEALTHY++))
    elif [[ $restart_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠${NC} $container_name: ${YELLOW}$restart_count restarts${NC}"
    else
        echo -e "${GREEN}✓${NC} $container_name: no restarts"
    fi
done < <(docker compose ps -q | xargs docker inspect --format='{{.Id}} {{.Name}}' 2>/dev/null)

# Check critical services specifically
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Critical Service Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CRITICAL_SERVICES=("traefik" "oauth" "redis" "postgres")

for service in "${CRITICAL_SERVICES[@]}"; do
    if docker compose ps "$service" --format json 2>/dev/null | grep -q "\"State\":\"running\""; then
        echo -e "${GREEN}✓${NC} $service: running"
    else
        echo -e "${RED}✗${NC} $service: NOT RUNNING (critical service!)"
        ((UNHEALTHY++))
    fi
done

# OAuth-specific health check
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  OAuth Configuration Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if docker compose ps oauth --format json 2>/dev/null | grep -q "\"State\":\"running\""; then
    # Check OAuth logs for errors
    oauth_errors=$(docker compose logs oauth --tail 50 2>&1 | grep -c -i "error" || echo "0")
    csrf_errors=$(docker compose logs oauth --tail 50 2>&1 | grep -c "CSRF" || echo "0")

    if [[ $csrf_errors -gt 0 ]]; then
        echo -e "${RED}✗${NC} OAuth: ${RED}CSRF errors detected${NC} (check SameSite cookie config)"
        ((UNHEALTHY++))
    elif [[ $oauth_errors -gt 5 ]]; then
        echo -e "${YELLOW}⚠${NC} OAuth: ${YELLOW}$oauth_errors errors in last 50 logs${NC}"
    else
        echo -e "${GREEN}✓${NC} OAuth: no critical errors"
    fi

    # Check for correct cookie configuration in logs
    if docker compose logs oauth --tail 100 2>&1 | grep -q "samesite.*none"; then
        echo -e "${GREEN}✓${NC} OAuth: SameSite=none configured (correct for OAuth)"
    else
        echo -e "${YELLOW}⚠${NC} OAuth: SameSite configuration not visible in logs"
    fi
fi

# Redis connection check
echo ""
if docker compose ps redis --format json 2>/dev/null | grep -q "\"State\":\"running\""; then
    if docker compose exec -T redis redis-cli --no-auth-warning -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✓${NC} Redis: accepting connections"
    else
        echo -e "${RED}✗${NC} Redis: NOT accepting connections"
        ((UNHEALTHY++))
    fi
fi

# Traefik dashboard check
echo ""
if docker compose ps traefik --format json 2>/dev/null | grep -q "\"State\":\"running\""; then
    # Check Traefik logs for errors
    traefik_errors=$(docker compose logs traefik --tail 50 2>&1 | grep -c -i "error" || echo "0")

    if [[ $traefik_errors -gt 5 ]]; then
        echo -e "${YELLOW}⚠${NC} Traefik: ${YELLOW}$traefik_errors errors in last 50 logs${NC}"
    else
        echo -e "${GREEN}✓${NC} Traefik: no critical errors"
    fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Health Check Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ $UNHEALTHY -eq 0 ]] && [[ $RESTARTING -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL SERVICES HEALTHY${NC}"
    echo "System is operating normally"
    exit 0
elif [[ $UNHEALTHY -eq 0 ]]; then
    echo -e "${YELLOW}⚠ SERVICES STARTING${NC}"
    echo "Restarting services: $RESTARTING"
    echo "Wait and re-run health check"
    exit 0
else
    echo -e "${RED}✗ UNHEALTHY SERVICES DETECTED${NC}"
    echo "Unhealthy/Stopped: $UNHEALTHY | Restarting: $RESTARTING"
    echo ""
    echo "Recommended actions:"
    echo "1. Check logs: docker compose logs <service>"
    echo "2. Review configuration: ./scripts/validate-deployment.sh"
    echo "3. Restart failed services: docker compose up -d <service> --force-recreate"
    exit 1
fi
