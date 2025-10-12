#!/usr/bin/env bash
# Jacker Monitoring Library
# Health checks, metrics, and monitoring functions

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"

#########################################
# Health Check Functions
#########################################

run_health_check() {
    local verbose="${1:-false}"
    local check_type="${2:-all}"

    log_section "Jacker Health Check"

    local total_checks=0
    local passed_checks=0
    local warnings=0
    local failures=0

    # Run checks based on type
    case "$check_type" in
        all)
            check_containers
            check_networks
            check_volumes
            check_services
            check_authentication
            check_ssl
            check_database
            check_monitoring_stack
            ;;
        containers)
            check_containers
            ;;
        network)
            check_networks
            ;;
        services)
            check_services
            ;;
        auth)
            check_authentication
            ;;
        ssl)
            check_ssl
            ;;
        database)
            check_database
            ;;
        monitoring)
            check_monitoring_stack
            ;;
    esac

    # Summary
    log_section "Health Check Summary"
    echo "Total checks: $TOTAL_CHECKS"
    echo "Passed:      $PASSED_CHECKS"
    echo "Warnings:    $WARNINGS"
    echo "Failed:      $FAILURES"
    echo

    if [[ $FAILURES -gt 0 ]]; then
        log_error "Health check failed with $FAILURES error(s)"
        return 1
    elif [[ $WARNINGS -gt 0 ]]; then
        log_warn "Health check completed with $WARNINGS warning(s)"
        return 0
    else
        log_success "All health checks passed!"
        return 0
    fi
}

# Global counters for health checks
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNINGS=0
FAILURES=0

health_check() {
    local check_name="$1"
    local check_command="$2"
    local severity="${3:-error}"  # error or warning

    ((TOTAL_CHECKS++))

    if eval "$check_command" &>/dev/null; then
        log_success "✓ $check_name"
        ((PASSED_CHECKS++))
        return 0
    else
        if [[ "$severity" == "warning" ]]; then
            log_warn "⚠ $check_name"
            ((WARNINGS++))
        else
            log_error "✗ $check_name"
            ((FAILURES++))
        fi
        return 1
    fi
}

#########################################
# Container Checks
#########################################

check_containers() {
    log_subsection "Container Health"

    # Get expected containers from compose files
    local expected_containers=$(get_expected_containers)
    local running_containers=$(docker ps --format "{{.Names}}")

    for container in $expected_containers; do
        health_check "Container $container is running" \
            "docker ps --format '{{.Names}}' | grep -q '^${container}$'"

        # Check container health status if available
        local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
        if [[ "$health_status" == "unhealthy" ]]; then
            health_check "Container $container is healthy" "false" "error"
        elif [[ "$health_status" == "healthy" ]]; then
            health_check "Container $container is healthy" "true" "warning"
        fi
    done

    # Check for unexpected containers
    for container in $running_containers; do
        if [[ "$container" == jacker-* ]] && ! echo "$expected_containers" | grep -q "$container"; then
            log_warn "Unexpected container running: $container"
        fi
    done
}

get_expected_containers() {
    # Parse docker-compose.yml for service names
    local services=""

    if [[ -f "${JACKER_DIR}/docker-compose.yml" ]]; then
        # Get service names from included compose files
        services=$(grep "path: compose/" "${JACKER_DIR}/docker-compose.yml" | \
                   grep -v "^#" | \
                   sed 's/.*compose\/\(.*\)\.yml/\1/' | \
                   tr '\n' ' ')
    fi

    # Prefix with jacker- (default project name)
    for service in $services; do
        echo "jacker-${service}-1"
    done
}

#########################################
# Network Checks
#########################################

check_networks() {
    log_subsection "Network Configuration"

    # Check Docker networks
    health_check "Docker default network exists" \
        "docker network ls | grep -q bridge"

    health_check "Jacker network exists" \
        "docker network ls | grep -q jacker_default"

    # Check network connectivity
    health_check "Internet connectivity" \
        "curl -s -o /dev/null -w '%{http_code}' https://www.google.com | grep -q '200'"

    # Check DNS resolution
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    if [[ -n "${PUBLIC_FQDN:-}" ]]; then
        health_check "DNS resolution for ${PUBLIC_FQDN}" \
            "nslookup ${PUBLIC_FQDN} &>/dev/null || host ${PUBLIC_FQDN} &>/dev/null" \
            "warning"
    fi

    # Check ports
    local required_ports="80 443"
    for port in $required_ports; do
        health_check "Port $port is accessible" \
            "! sudo lsof -i:$port &>/dev/null || netstat -tuln | grep -q :$port" \
            "warning"
    done
}

#########################################
# Volume Checks
#########################################

check_volumes() {
    log_subsection "Storage Volumes"

    # Check data directories
    local critical_dirs=(
        "data/traefik"
        "data/postgres"
        "data/loki/data"
        "data/prometheus"
        "data/grafana"
    )

    for dir in "${critical_dirs[@]}"; do
        health_check "Directory ${dir} exists" \
            "test -d '${JACKER_DIR}/${dir}'"

        # Check permissions for specific directories
        case "$dir" in
            "data/loki/data")
                health_check "Loki data has correct permissions (777)" \
                    "test '$(stat -c %a ${JACKER_DIR}/${dir} 2>/dev/null)' = '777'" \
                    "warning"
                ;;
            "data/traefik")
                if [[ -f "${JACKER_DIR}/data/traefik/acme/acme.json" ]]; then
                    health_check "Traefik acme.json has correct permissions (600)" \
                        "test '$(stat -c %a ${JACKER_DIR}/data/traefik/acme/acme.json)' = '600'" \
                        "warning"
                fi
                ;;
        esac
    done

    # Check disk space
    local data_usage=$(du -sh "${JACKER_DIR}/data" 2>/dev/null | awk '{print $1}')
    local disk_free=$(df -h "${JACKER_DIR}" | awk 'NR==2 {print $4}')

    log_info "Data usage: ${data_usage:-unknown}"
    log_info "Free space: ${disk_free:-unknown}"

    # Warn if less than 1GB free
    local free_bytes=$(df "${JACKER_DIR}" | awk 'NR==2 {print $4}')
    if [[ -n "$free_bytes" ]] && [[ "$free_bytes" -lt 1048576 ]]; then
        health_check "Sufficient disk space (>1GB free)" "false" "warning"
    else
        health_check "Sufficient disk space (>1GB free)" "true"
    fi
}

#########################################
# Service Checks
#########################################

check_services() {
    log_subsection "Service Endpoints"

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    if [[ -z "${PUBLIC_FQDN:-}" ]]; then
        log_warn "PUBLIC_FQDN not configured - skipping service checks"
        return
    fi

    # Check service endpoints
    local services=(
        "traefik:https://traefik.${PUBLIC_FQDN}"
        "grafana:https://grafana.${PUBLIC_FQDN}"
        "prometheus:https://prometheus.${PUBLIC_FQDN}"
        "homepage:https://homepage.${PUBLIC_FQDN}"
        "portainer:https://portainer.${PUBLIC_FQDN}"
    )

    for service_url in "${services[@]}"; do
        local service_name="${service_url%%:*}"
        local url="${service_url#*:}"

        # Check if container is running first
        if docker ps --format '{{.Names}}' | grep -q "jacker-${service_name}"; then
            health_check "Service ${service_name} is responding" \
                "curl -k -s -o /dev/null -w '%{http_code}' '$url' | grep -qE '200|301|302|401'" \
                "warning"
        fi
    done
}

#########################################
# Authentication Checks
#########################################

check_authentication() {
    log_subsection "Authentication"

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    # Check OAuth configuration
    if [[ -n "${OAUTH_CLIENT_ID:-}" ]]; then
        health_check "OAuth client ID configured" "true"
        health_check "OAuth client secret configured" "test -n '${OAUTH_CLIENT_SECRET:-}'"
        health_check "OAuth whitelist configured" "test -n '${OAUTH_WHITELIST:-}'" "warning"

        # Check OAuth container
        health_check "OAuth container running" \
            "docker ps --format '{{.Names}}' | grep -q 'jacker-oauth'"

        # Check OAuth middleware file
        health_check "OAuth middleware configured" \
            "test -f '${JACKER_DIR}/data/traefik/rules/middlewares-oauth.yml'"
    elif [[ -n "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        health_check "Authentik configured" "true"
        health_check "Authentik container running" \
            "docker ps --format '{{.Names}}' | grep -q 'jacker-authentik'"
    else
        health_check "Authentication configured" "false" "warning"
        log_warn "No authentication configured - services are publicly accessible!"
    fi
}

#########################################
# SSL/TLS Checks
#########################################

check_ssl() {
    log_subsection "SSL/TLS Configuration"

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    # Check Let's Encrypt configuration
    if [[ -n "${LETSENCRYPT_EMAIL:-}" ]]; then
        health_check "Let's Encrypt email configured" "true"

        # Check ACME file
        if [[ -f "${JACKER_DIR}/data/traefik/acme/acme.json" ]]; then
            health_check "ACME certificates file exists" "true"

            # Check if certificates are present
            local cert_count=$(grep -c "certificate" "${JACKER_DIR}/data/traefik/acme/acme.json" 2>/dev/null || echo 0)
            if [[ $cert_count -gt 0 ]]; then
                health_check "SSL certificates generated" "true"
            else
                health_check "SSL certificates generated" "false" "warning"
            fi
        else
            health_check "ACME certificates file exists" "false" "warning"
        fi
    else
        health_check "Let's Encrypt configured" "false" "warning"
        log_warn "Let's Encrypt not configured - using self-signed certificates"
    fi

    # Check certificate expiry if possible
    if [[ -n "${PUBLIC_FQDN:-}" ]] && command -v openssl &>/dev/null; then
        local expiry_date=$(echo | openssl s_client -connect "${PUBLIC_FQDN}:443" -servername "${PUBLIC_FQDN}" 2>/dev/null | \
                           openssl x509 -noout -dates 2>/dev/null | \
                           grep notAfter | cut -d= -f2)

        if [[ -n "$expiry_date" ]]; then
            log_info "Certificate expires: $expiry_date"

            # Check if expiring soon (within 7 days)
            local expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            local days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))

            if [[ $days_until_expiry -lt 7 ]]; then
                health_check "SSL certificate not expiring soon" "false" "warning"
                log_warn "Certificate expires in $days_until_expiry days!"
            else
                health_check "SSL certificate valid for $days_until_expiry days" "true"
            fi
        fi
    fi
}

#########################################
# Database Checks
#########################################

check_database() {
    log_subsection "Database Services"

    # Check PostgreSQL
    health_check "PostgreSQL container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-postgres'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-postgres'; then
        # Load configuration
        set -a
        source "${JACKER_DIR}/.env" 2>/dev/null || true
        set +a

        health_check "PostgreSQL is ready" \
            "docker compose exec -T postgres pg_isready -U '${POSTGRES_USER:-crowdsec}'"

        # Check databases exist
        local databases="${POSTGRES_MULTIPLE_DATABASES:-crowdsec_db}"
        IFS=',' read -ra DB_ARRAY <<< "$databases"
        for db in "${DB_ARRAY[@]}"; do
            db=$(echo "$db" | xargs)
            health_check "Database ${db} exists" \
                "docker compose exec -T postgres psql -U '${POSTGRES_USER}' -lqt | grep -q '${db}'" \
                "warning"
        done

        # Check database size
        local db_size=$(docker compose exec -T postgres psql -U "${POSTGRES_USER}" -t -c \
                       "SELECT pg_size_pretty(pg_database_size('${POSTGRES_DB}'));" 2>/dev/null | xargs)
        if [[ -n "$db_size" ]]; then
            log_info "PostgreSQL database size: $db_size"
        fi
    fi

    # Check Redis
    health_check "Redis container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-redis'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-redis'; then
        health_check "Redis is responding" \
            "docker compose exec -T redis redis-cli ping | grep -q PONG"
    fi
}

#########################################
# Monitoring Stack Checks
#########################################

check_monitoring_stack() {
    log_subsection "Monitoring Stack"

    # Prometheus
    health_check "Prometheus container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-prometheus'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-prometheus'; then
        health_check "Prometheus is healthy" \
            "curl -s http://localhost:9090/-/healthy 2>/dev/null | grep -q 'Prometheus is Healthy'"

        # Check targets
        local unhealthy_targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | \
                                 jq -r '.data.activeTargets[] | select(.health=="down") | .labels.job' 2>/dev/null)
        if [[ -n "$unhealthy_targets" ]]; then
            health_check "All Prometheus targets healthy" "false" "warning"
            log_warn "Unhealthy targets: $unhealthy_targets"
        else
            health_check "All Prometheus targets healthy" "true"
        fi
    fi

    # Grafana
    health_check "Grafana container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-grafana'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-grafana'; then
        health_check "Grafana is healthy" \
            "curl -s http://localhost:3000/api/health 2>/dev/null | grep -q 'ok'"
    fi

    # Loki
    health_check "Loki container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-loki'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-loki'; then
        health_check "Loki is ready" \
            "curl -s http://localhost:3100/ready 2>/dev/null | grep -q 'ready'"
    fi

    # Promtail
    health_check "Promtail container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-promtail'"

    # Alertmanager
    health_check "Alertmanager container running" \
        "docker ps --format '{{.Names}}' | grep -q 'jacker-alertmanager'"

    if docker ps --format '{{.Names}}' | grep -q 'jacker-alertmanager'; then
        health_check "Alertmanager is healthy" \
            "curl -s http://localhost:9093/-/healthy 2>/dev/null | grep -q 'OK'"
    fi
}

#########################################
# Metrics and Statistics
#########################################

show_metrics() {
    log_section "System Metrics"

    # Container statistics
    log_subsection "Container Resources"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

    # System resources
    log_subsection "System Resources"

    # CPU usage
    if command -v top &>/dev/null; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        echo "CPU Usage:     ${cpu_usage}%"
    fi

    # Memory usage
    if command -v free &>/dev/null; then
        local mem_info=$(free -h | awk 'NR==2')
        local mem_total=$(echo "$mem_info" | awk '{print $2}')
        local mem_used=$(echo "$mem_info" | awk '{print $3}')
        local mem_free=$(echo "$mem_info" | awk '{print $4}')
        echo "Memory:        ${mem_used} used / ${mem_total} total (${mem_free} free)"
    fi

    # Disk usage
    local disk_info=$(df -h "${JACKER_DIR}" | awk 'NR==2')
    local disk_total=$(echo "$disk_info" | awk '{print $2}')
    local disk_used=$(echo "$disk_info" | awk '{print $3}')
    local disk_free=$(echo "$disk_info" | awk '{print $4}')
    local disk_percent=$(echo "$disk_info" | awk '{print $5}')
    echo "Disk:          ${disk_used} used / ${disk_total} total (${disk_free} free, ${disk_percent} used)"

    # Docker info
    log_subsection "Docker Information"
    docker system df
}

#########################################
# Service Logs
#########################################

show_logs() {
    local service="${1:-}"
    local lines="${2:-50}"
    local follow="${3:-false}"

    if [[ -z "$service" ]]; then
        log_error "Service name required"
        echo "Usage: jacker logs <service> [lines] [--follow]"
        return 1
    fi

    local docker_args="-n $lines"
    if [[ "$follow" == "true" ]]; then
        docker_args="$docker_args -f"
    fi

    docker compose logs $docker_args "$service"
}

show_error_logs() {
    log_section "Recent Errors"

    mapfile -t services < <(docker compose ps --format json 2>/dev/null | jq -r '.Service' 2>/dev/null)

    for service in "${services[@]}"; do
        local errors=$(docker compose logs -n 100 "$service" 2>&1 | grep -iE "error|fail|critical|fatal" | tail -5)
        if [[ -n "$errors" ]]; then
            log_subsection "$service errors"
            echo "$errors"
        fi
    done
}

#########################################
# Dashboard Functions
#########################################

show_status_dashboard() {
    clear
    log_section "Jacker Status Dashboard"

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    # System info
    echo "═══════════════════════════════════════════════════════════"
    echo " System:     $(hostname -f)"
    echo " Domain:     ${PUBLIC_FQDN:-not configured}"
    echo " Uptime:     $(uptime -p 2>/dev/null || uptime)"
    echo "═══════════════════════════════════════════════════════════"
    echo

    # Container status
    echo "Container Status:"
    docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"
    echo

    # Resource usage
    echo "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -10
    echo

    # Quick health status
    echo "Health Status:"
    local health_output=$(run_health_check false summary 2>&1)
    echo "$health_output" | tail -5
}

#########################################
# Monitoring Configuration
#########################################

configure_monitoring() {
    log_section "Monitoring Configuration"

    echo "Monitoring Options:"
    echo "1. Configure Prometheus scrape targets"
    echo "2. Configure Loki retention"
    echo "3. Configure alert rules"
    echo "4. Configure metric exporters"
    read -p "Choose option: " mon_choice

    case "$mon_choice" in
        1)
            configure_prometheus_targets
            ;;
        2)
            configure_loki_retention
            ;;
        3)
            configure_alert_rules
            ;;
        4)
            configure_exporters
            ;;
    esac
}

configure_prometheus_targets() {
    log_info "Configuring Prometheus targets..."

    local prom_config="${JACKER_DIR}/config/prometheus/prometheus.yml"
    mkdir -p "$(dirname "$prom_config")"

    # Create Prometheus configuration
    cat > "$prom_config" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'docker'
    static_configs:
      - targets: ['socket-proxy:9323']

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8082']

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']

  - job_name: 'promtail'
    static_configs:
      - targets: ['promtail:9080']

  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
EOF

    docker compose restart prometheus
    log_success "Prometheus targets configured"
}

configure_loki_retention() {
    log_info "Configuring Loki retention..."

    read -p "Log retention period (e.g., 7d, 30d) [7d]: " retention
    retention="${retention:-7d}"

    local loki_config="${JACKER_DIR}/data/loki/loki-config.yml"

    # Update retention in Loki config
    if [[ -f "$loki_config" ]]; then
        sed -i "s/retention_period:.*/retention_period: ${retention}/" "$loki_config"
        docker compose restart loki
        log_success "Loki retention set to ${retention}"
    else
        log_error "Loki configuration file not found"
    fi
}

configure_alert_rules() {
    log_info "Configuring alert rules..."

    local rules_dir="${JACKER_DIR}/config/prometheus/rules"
    mkdir -p "$rules_dir"

    # Create basic alert rules
    cat > "$rules_dir/basic_alerts.yml" <<'EOF'
groups:
  - name: basic_alerts
    interval: 30s
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 2 minutes."

      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on container {{ $labels.container_name }}"
          description: "Container {{ $labels.container_name }} CPU usage is above 80% (current value: {{ $value }}%)"

      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on container {{ $labels.container_name }}"
          description: "Container {{ $labels.container_name }} memory usage is above 80% (current value: {{ $value }}%)"

      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Low disk space on {{ $labels.instance }}"
          description: "Disk space on {{ $labels.instance }} is below 20% (current value: {{ $value }}%)"
EOF

    docker compose restart prometheus
    log_success "Alert rules configured"
}

configure_exporters() {
    log_info "Configuring metric exporters..."

    echo "Available exporters:"
    echo "1. PostgreSQL exporter"
    echo "2. Redis exporter"
    echo "3. Blackbox exporter (HTTP/TCP checks)"
    echo "4. Custom exporter"
    read -p "Choose exporter to configure: " exporter_choice

    case "$exporter_choice" in
        1)
            configure_postgres_exporter
            ;;
        2)
            configure_redis_exporter
            ;;
        3)
            configure_blackbox_exporter
            ;;
        4)
            configure_custom_exporter
            ;;
    esac
}

configure_postgres_exporter() {
    log_info "Configuring PostgreSQL exporter..."

    # Enable postgres exporter in compose
    # This would need a postgres-exporter.yml compose file
    log_info "PostgreSQL exporter configuration would go here"
    log_warn "Not yet implemented"
}

configure_redis_exporter() {
    log_info "Configuring Redis exporter..."

    # Enable redis exporter in compose
    log_info "Redis exporter configuration would go here"
    log_warn "Not yet implemented"
}

configure_blackbox_exporter() {
    log_info "Configuring Blackbox exporter..."

    # Configure blackbox exporter for HTTP/TCP checks
    log_info "Blackbox exporter configuration would go here"
    log_warn "Not yet implemented"
}

configure_custom_exporter() {
    log_info "Custom exporter configuration..."

    read -p "Exporter name: " exporter_name
    read -p "Exporter port: " exporter_port
    read -p "Exporter image: " exporter_image

    echo "Custom exporter configuration would be added to compose"
    log_warn "Not yet implemented"
}

# Export functions for use by jacker CLI
export -f run_health_check
export -f show_metrics
export -f show_logs
export -f show_error_logs
export -f show_status_dashboard
export -f configure_monitoring