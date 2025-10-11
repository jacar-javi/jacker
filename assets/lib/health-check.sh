#!/usr/bin/env bash
#
# health-check.sh - Service health monitoring module
# Provides comprehensive health checks for all Jacker services
#

# Source common library
# shellcheck source=assets/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Service definitions
declare -A SERVICES=(
    ["traefik"]="Reverse Proxy"
    ["crowdsec"]="Security IPS"
    ["postgres"]="PostgreSQL Database"
    ["redis"]="Redis Cache"
    ["oauth"]="OAuth Authentication"
    ["prometheus"]="Metrics Collection"
    ["grafana"]="Visualization"
    ["loki"]="Log Aggregation"
    ["alertmanager"]="Alert Management"
    ["portainer"]="Container Management"
    ["homepage"]="Dashboard"
)

# Optional services
declare -A OPTIONAL_SERVICES=(
    ["jaeger"]="Distributed Tracing"
    ["authentik-server"]="Identity Provider"
)

# ============================================================================
# Health Check Functions
# ============================================================================

# Check single service health
check_service_health() {
    local service="$1"
    local description="${2:-$service}"

    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${service}$"; then
        echo "⚪ $description: Not deployed"
        return 2
    fi

    # Check if container is running
    if ! is_container_running "$service"; then
        echo "$(print_color "$RED" "$CROSS_MARK") $description: Stopped"
        return 1
    fi

    # Check container health status if available
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "none")

    case "$health_status" in
        healthy)
            echo "$(print_color "$GREEN" "$CHECK_MARK") $description: Healthy"
            return 0
            ;;
        unhealthy)
            echo "$(print_color "$RED" "$CROSS_MARK") $description: Unhealthy"
            return 1
            ;;
        starting)
            echo "$(print_color "$YELLOW" "⟳") $description: Starting..."
            return 0
            ;;
        none|"")
            # No health check defined, check if running
            echo "$(print_color "$GREEN" "$CHECK_MARK") $description: Running"
            return 0
            ;;
        *)
            echo "$(print_color "$YELLOW" "$WARNING_SIGN") $description: Unknown ($health_status)"
            return 1
            ;;
    esac
}

# Check all services
check_all_services() {
    local all_healthy=true
    local failed_services=()
    local stopped_services=()

    # Check required services
    for service in "${!SERVICES[@]}"; do
        if ! check_service_health "$service" "${SERVICES[$service]}"; then
            all_healthy=false
            if [ $? -eq 1 ]; then
                if is_container_running "$service"; then
                    failed_services+=("$service")
                else
                    stopped_services+=("$service")
                fi
            fi
        fi
    done

    # Check optional services (don't affect overall health)
    echo ""
    for service in "${!OPTIONAL_SERVICES[@]}"; do
        check_service_health "$service" "${OPTIONAL_SERVICES[$service]}" || true
    done

    # Return status
    if [ "$all_healthy" = true ]; then
        return 0
    else
        [ ${#failed_services[@]} -gt 0 ] && error "Failed services: ${failed_services[*]}"
        [ ${#stopped_services[@]} -gt 0 ] && warning "Stopped services: ${stopped_services[*]}"
        return 1
    fi
}

# Check system resources
check_system_resources() {
    subsection "System Resources"

    # Memory usage
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    local mem_used=$((mem_total - mem_available))
    local mem_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_percent" -gt 90 ]; then
        error "Memory: ${mem_percent}% used (critical)"
    elif [ "$mem_percent" -gt 75 ]; then
        warning "Memory: ${mem_percent}% used"
    else
        success "Memory: ${mem_percent}% used"
    fi

    # Disk usage
    local disk_usage=$(df / | tail -1 | awk '{print int($5)}')

    if [ "$disk_usage" -gt 90 ]; then
        error "Disk: ${disk_usage}% used (critical)"
    elif [ "$disk_usage" -gt 75 ]; then
        warning "Disk: ${disk_usage}% used"
    else
        success "Disk: ${disk_usage}% used"
    fi

    # Load average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    local cpu_cores=$(nproc)
    local load_1min=$(echo "$load_avg" | cut -d, -f1 | xargs)

    info "Load Average:$load_avg (${cpu_cores} cores)"

    # Docker disk usage
    local docker_disk=$(docker system df --format "table {{.Type}}\t{{.Size}}" | tail -n +2)
    echo ""
    echo "Docker Disk Usage:"
    echo "$docker_disk"
}

# Check network connectivity
check_network() {
    subsection "Network Connectivity"

    # Check internal Docker network
    if docker network ls | grep -q "traefik_proxy"; then
        success "Docker network: traefik_proxy exists"
    else
        error "Docker network: traefik_proxy not found"
    fi

    # Check if services can reach each other
    if is_container_running "traefik" && is_container_running "crowdsec"; then
        if docker_exec traefik wget -q -O /dev/null http://crowdsec:8080/health 2>/dev/null; then
            success "Inter-service communication: OK"
        else
            warning "Inter-service communication: Issues detected"
        fi
    fi

    # Check external connectivity (if domain is configured)
    if [ -f ".env" ]; then
        load_env
        if [ -n "${PUBLIC_FQDN:-}" ]; then
            if curl -s -o /dev/null -w "%{http_code}" "https://$PUBLIC_FQDN" 2>/dev/null | grep -q "200\|301\|302"; then
                success "External access: https://$PUBLIC_FQDN reachable"
            else
                warning "External access: https://$PUBLIC_FQDN not reachable"
            fi
        fi
    fi
}

# Check configuration
check_configuration() {
    subsection "Configuration"

    # Check .env file
    if [ -f ".env" ]; then
        success ".env file exists"

        # Check required variables
        local required_vars=(
            "HOSTNAME"
            "DOMAINNAME"
            "POSTGRES_PASSWORD"
            "CROWDSEC_TRAEFIK_BOUNCER_API_KEY"
        )

        local missing_vars=()
        for var in "${required_vars[@]}"; do
            if ! grep -q "^${var}=" .env; then
                missing_vars+=("$var")
            fi
        done

        if [ ${#missing_vars[@]} -gt 0 ]; then
            warning "Missing variables: ${missing_vars[*]}"
        else
            success "Required variables: All present"
        fi
    else
        error ".env file not found"
    fi

    # Check Docker Compose configuration
    if docker compose config > /dev/null 2>&1; then
        success "Docker Compose configuration: Valid"
    else
        error "Docker Compose configuration: Invalid"
    fi

    # Check SSL certificates
    if [ -f "data/traefik/acme.json" ]; then
        local acme_perms=$(stat -c %a data/traefik/acme.json)
        if [ "$acme_perms" = "600" ]; then
            success "SSL certificate file: Correct permissions (600)"
        else
            warning "SSL certificate file: Wrong permissions ($acme_perms, should be 600)"
        fi
    else
        warning "SSL certificate file: Not found"
    fi
}

# Watch mode
watch_health() {
    while true; do
        clear
        main_health_check
        echo ""
        echo "$(print_color "$CYAN" "Refreshing every 5 seconds... Press Ctrl+C to stop")"
        sleep 5
    done
}

# Main health check
main_health_check() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║               JACKER PLATFORM HEALTH CHECK               ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""

    section "Service Status"
    check_all_services
    local services_status=$?

    check_system_resources
    check_network
    check_configuration

    # Overall status
    section "Overall Status"

    if [ $services_status -eq 0 ]; then
        echo "$(print_color "$GREEN" "✅ SYSTEM HEALTHY")"
        echo ""
        success "All required services are running properly"
        return 0
    else
        echo "$(print_color "$YELLOW" "⚠️  SYSTEM DEGRADED")"
        echo ""
        warning "Some services need attention"
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

# Parse arguments
case "${1:-}" in
    --watch|-w)
        watch_health
        ;;
    --json|-j)
        # TODO: Implement JSON output
        error "JSON output not yet implemented"
        exit 1
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --watch, -w    Watch mode (refresh every 5 seconds)"
        echo "  --json, -j     Output in JSON format"
        echo "  --help, -h     Show this help message"
        exit 0
        ;;
    *)
        main_health_check
        ;;
esac