#!/usr/bin/env bash
#
# Script: health-check.sh
# Description: Check health status of all Jacker services
# Usage: ./health-check.sh [--watch]
# Options:
#   --watch    Continuously monitor services (refresh every 5 seconds)
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

WATCH_MODE=false
if [ "${1:-}" = "--watch" ]; then
    WATCH_MODE=true
fi

check_health() {
    clear 2>/dev/null || true

    echo -e "${BLUE}=== Jacker Health Check ===${NC}"
    echo "Last check: $(date)"
    echo ""

    # Check if .env exists
    if [ ! -f .env ]; then
        echo -e "${RED}ERROR: .env file not found${NC}"
        return 1
    fi

# shellcheck source=/dev/null
    source .env

    # Check Docker daemon
    echo -e "${BLUE}=== Docker Daemon ===${NC}"
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker daemon is running"
    else
        echo -e "${RED}✗${NC} Docker daemon is not accessible"
        return 1
    fi
    echo ""

    # Check running containers
    echo -e "${BLUE}=== Container Status ===${NC}"

    EXPECTED_CONTAINERS=(
        "socket-proxy:Socket Proxy"
        "traefik:Traefik Reverse Proxy"
        "oauth:OAuth Authentication"
        "crowdsec:CrowdSec IPS"
        "traefik-bouncer:Traefik Bouncer"
        "mariadb:MariaDB Database"
        "grafana:Grafana Monitoring"
        "prometheus:Prometheus Metrics"
        "node-exporter:Node Exporter"
        "portainer:Portainer Management"
    )

    for item in "${EXPECTED_CONTAINERS[@]}"; do
        container="${item%%:*}"
        name="${item#*:}"

        if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")

            case $status in
                healthy)
                    echo -e "${GREEN}✓${NC} $name (healthy)"
                    ;;
                unhealthy)
                    echo -e "${RED}✗${NC} $name (unhealthy)"
                    ;;
                starting)
                    echo -e "${YELLOW}⏳${NC} $name (starting)"
                    ;;
                no-healthcheck)
                    # Check if container is running
                    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
                    if [ "$state" = "running" ]; then
                        echo -e "${GREEN}✓${NC} $name (running, no healthcheck)"
                    else
                        echo -e "${RED}✗${NC} $name ($state)"
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}?${NC} $name (unknown: $status)"
                    ;;
            esac
        else
            echo -e "${RED}✗${NC} $name (not running)"
        fi
    done
    echo ""

    # Check networks
    echo -e "${BLUE}=== Docker Networks ===${NC}"

    REQUIRED_NETWORKS=(
        "socket_proxy"
        "traefik_proxy"
    )

    for network in "${REQUIRED_NETWORKS[@]}"; do
        if docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
            # Count connected containers
            container_count=$(docker network inspect "$network" --format='{{len .Containers}}' 2>/dev/null || echo "0")
            echo -e "${GREEN}✓${NC} $network ($container_count containers)"
        else
            echo -e "${RED}✗${NC} $network (not found)"
        fi
    done
    echo ""

    # Check critical ports
    echo -e "${BLUE}=== Port Status ===${NC}"

    CRITICAL_PORTS=(
        "80:HTTP"
        "443:HTTPS (TCP)"
        "443:HTTPS (UDP/HTTP3)"
    )

    for item in "${CRITICAL_PORTS[@]}"; do
        port="${item%%:*}"
        name="${item#*:}"

        if sudo netstat -tulpn 2>/dev/null | grep -q ":${port} " || sudo ss -tulpn 2>/dev/null | grep -q ":${port} "; then
            echo -e "${GREEN}✓${NC} Port $port ($name) is listening"
        else
            echo -e "${RED}✗${NC} Port $port ($name) is not listening"
        fi
    done
    echo ""

    # Check Traefik
    echo -e "${BLUE}=== Traefik Status ===${NC}"
    if curl -sf http://localhost:8080/ping &> /dev/null; then
        echo -e "${GREEN}✓${NC} Traefik API is accessible"
    else
        echo -e "${RED}✗${NC} Traefik API is not accessible"
    fi
    echo ""

    # Check CrowdSec
    echo -e "${BLUE}=== CrowdSec Status ===${NC}"
    if command -v cscli &> /dev/null; then
        if cscli metrics &> /dev/null; then
            decisions=$(cscli decisions list -o json 2>/dev/null | grep -c '"duration"' || echo "0")
            bouncers=$(cscli bouncers list -o json 2>/dev/null | grep -c '"name"' || echo "0")
            echo -e "${GREEN}✓${NC} CrowdSec is operational"
            echo "  Active decisions: $decisions"
            echo "  Connected bouncers: $bouncers"
        else
            echo -e "${YELLOW}⚠${NC} CrowdSec is running but cscli cannot connect"
        fi
    else
        echo -e "${YELLOW}⚠${NC} cscli not installed"
    fi
    echo ""

    # Check disk usage
    echo -e "${BLUE}=== Disk Usage ===${NC}"
    df -h . | tail -1 | awk '{
        used = substr($5, 1, length($5)-1);
        if (used >= 90) {
            printf "\033[0;31m✗\033[0m Disk usage: %s (critical)\n", $5;
        } else if (used >= 75) {
            printf "\033[1;33m⚠\033[0m Disk usage: %s (warning)\n", $5;
        } else {
            printf "\033[0;32m✓\033[0m Disk usage: %s\n", $5;
        }
    }'

    # Check Docker disk usage
    DOCKER_USAGE=$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null || true)
    if [ -n "$DOCKER_USAGE" ]; then
        echo "Docker disk usage:"
        echo "$DOCKER_USAGE" | while read -r line; do
            echo "  $line"
        done
    fi
    echo ""

    # Check SSL certificates
    echo -e "${BLUE}=== SSL Certificates ===${NC}"
    if [ -f data/traefik/acme.json ]; then
        cert_count=$(grep -o '"domain"' data/traefik/acme.json 2>/dev/null | wc -l || echo "0")
        echo -e "${GREEN}✓${NC} ACME certificates file exists ($cert_count certificates)"
    else
        echo -e "${YELLOW}⚠${NC} ACME certificates file not found"
    fi
    echo ""

    # UFW Status
    echo -e "${BLUE}=== Firewall Status ===${NC}"
    if command -v ufw &> /dev/null; then
        if sudo ufw status | grep -q "Status: active"; then
            echo -e "${GREEN}✓${NC} UFW is active"
            active_rules=$(sudo ufw status numbered | grep -c '^\[' || echo "0")
            echo "  Active rules: $active_rules"
        else
            echo -e "${YELLOW}⚠${NC} UFW is installed but not active"
        fi
    else
        echo -e "${YELLOW}⚠${NC} UFW is not installed"
    fi
    echo ""

    echo -e "${BLUE}=== Quick Links ===${NC}"
    echo "Traefik Dashboard: https://traefik.${PUBLIC_FQDN}"
    echo "Portainer: https://portainer.${PUBLIC_FQDN}"
    echo "Grafana: https://grafana.${PUBLIC_FQDN}"
    echo "Homepage: https://home.${PUBLIC_FQDN}"
    echo ""
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
    echo "Starting watch mode (press Ctrl+C to exit)..."
    sleep 1
    while true; do
        check_health
        sleep 5
    done
else
    check_health
fi
