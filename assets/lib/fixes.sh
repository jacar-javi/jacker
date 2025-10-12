#!/usr/bin/env bash
#
# fixes.sh - Consolidated fix functions for common issues
#

# Source common functions if not already loaded
if [[ -z "${JACKER_ROOT:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Fix Loki permissions and configuration
fix_loki() {
    section "Fixing Loki Configuration"

    info "Creating Loki directories..."
    ensure_dir "$JACKER_ROOT/data/loki/data"
    ensure_dir "$JACKER_ROOT/data/loki/data/rules"
    ensure_dir "$JACKER_ROOT/data/loki/data/chunks"
    ensure_dir "$JACKER_ROOT/data/loki/data/compactor"

    info "Setting permissions (UID 10001)..."
    sudo chown -R 10001:10001 "$JACKER_ROOT/data/loki" 2>/dev/null || \
        chown -R 10001:10001 "$JACKER_ROOT/data/loki"
    sudo chmod -R 755 "$JACKER_ROOT/data/loki/data"

    info "Updating configuration..."
    if [[ -f "$JACKER_ROOT/assets/templates/loki-config.yml.template" ]]; then
        create_from_template \
            "$JACKER_ROOT/assets/templates/loki-config.yml.template" \
            "$JACKER_ROOT/config/loki/loki-config.yml"
    fi

    info "Restarting Loki..."
    docker restart loki 2>/dev/null || true

    if wait_for_healthy "loki" 30; then
        success "Loki fixed and running"
    else
        warning "Loki restarted but health check failed"
        docker logs loki --tail 20
    fi
}

# Fix Alertmanager configuration
fix_alertmanager() {
    section "Fixing Alertmanager Configuration"

    info "Creating Alertmanager directories..."
    ensure_dir "$JACKER_ROOT/data/alertmanager"

    info "Creating minimal configuration..."
    cat > "$JACKER_ROOT/config/alertmanager/alertmanager.yml" << 'EOF'
global:
  resolve_timeout: 5m

templates:
  - '/etc/alertmanager/templates/*.tmpl'

route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h

  routes:
    - receiver: 'critical-alerts'
      matchers:
        - severity = critical
      group_wait: 0s
      repeat_interval: 5m

    - receiver: 'warning-alerts'
      matchers:
        - severity = warning
      group_wait: 30s
      repeat_interval: 1h

receivers:
  - name: 'default-receiver'
  - name: 'critical-alerts'
  - name: 'warning-alerts'

inhibit_rules:
  - source_matchers:
      - severity = critical
    target_matchers:
      - severity = warning
    equal: ['alertname', 'cluster', 'service']
EOF

    info "Setting permissions (UID 65534)..."
    sudo chown -R 65534:65534 "$JACKER_ROOT/data/alertmanager" 2>/dev/null || \
        chown -R 65534:65534 "$JACKER_ROOT/data/alertmanager"
    sudo chmod -R 755 "$JACKER_ROOT/data/alertmanager"

    info "Restarting Alertmanager..."
    docker restart alertmanager 2>/dev/null || true

    if wait_for_healthy "alertmanager" 30; then
        success "Alertmanager fixed and running"
    else
        warning "Alertmanager restarted but health check failed"
        docker logs alertmanager --tail 20
    fi
}

# Fix CrowdSec database connection
fix_crowdsec() {
    section "Fixing CrowdSec Database Connection"

    load_env

    info "Checking PostgreSQL..."
    if ! is_container_running "postgres"; then
        error "PostgreSQL is not running"
        return 1
    fi

    info "Creating CrowdSec database if needed..."
    docker exec postgres psql -U "${POSTGRES_USER:-postgres}" -tc \
        "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB:-crowdsec_db}'" | grep -q 1 || \
        docker exec postgres psql -U "${POSTGRES_USER:-postgres}" -c \
            "CREATE DATABASE ${POSTGRES_DB:-crowdsec_db};"

    info "Updating CrowdSec configuration..."
    if [[ -f "$JACKER_ROOT/config/crowdsec/config/config.yaml.local" ]]; then
        sed -i "s|db_name:.*|db_name: ${POSTGRES_DB:-crowdsec_db}|g" \
            "$JACKER_ROOT/config/crowdsec/config/config.yaml.local"
        sed -i "s|user:.*|user: ${POSTGRES_USER:-postgres}|g" \
            "$JACKER_ROOT/config/crowdsec/config/config.yaml.local"
        sed -i "s|password:.*|password: ${POSTGRES_PASSWORD}|g" \
            "$JACKER_ROOT/config/crowdsec/config/config.yaml.local"
    fi

    info "Restarting CrowdSec..."
    docker restart crowdsec 2>/dev/null || true

    if wait_for_healthy "crowdsec" 30; then
        success "CrowdSec fixed and running"
    else
        warning "CrowdSec restarted but health check failed"
        docker logs crowdsec --tail 20
    fi
}

# Fix PostgreSQL permissions
fix_postgres() {
    section "Fixing PostgreSQL Permissions"

    info "Creating PostgreSQL directories..."
    ensure_dir "$JACKER_ROOT/data/postgres"

    info "Setting permissions..."
    sudo chown -R 999:999 "$JACKER_ROOT/data/postgres" 2>/dev/null || \
        chown -R 999:999 "$JACKER_ROOT/data/postgres"
    sudo chmod 700 "$JACKER_ROOT/data/postgres"

    info "Restarting PostgreSQL..."
    docker restart postgres 2>/dev/null || true

    if wait_for_healthy "postgres" 30; then
        success "PostgreSQL fixed and running"
    else
        warning "PostgreSQL restarted but health check failed"
        docker logs postgres --tail 20
    fi
}

# Fix Traefik certificates
fix_traefik() {
    section "Fixing Traefik Certificates"

    info "Creating acme.json if missing..."
    if [[ ! -f "$JACKER_ROOT/data/traefik/acme/acme.json" ]]; then
        ensure_dir "$JACKER_ROOT/data/traefik/acme"
        touch "$JACKER_ROOT/data/traefik/acme/acme.json"
    fi

    info "Setting correct permissions..."
    chmod 600 "$JACKER_ROOT/data/traefik/acme/acme.json"

    info "Backing up existing certificates..."
    if [[ -s "$JACKER_ROOT/data/traefik/acme/acme.json" ]]; then
        backup_file "$JACKER_ROOT/data/traefik/acme/acme.json"
    fi

    if confirm_action "Clear certificates and request new ones?"; then
        echo "{}" > "$JACKER_ROOT/data/traefik/acme/acme.json"
        chmod 600 "$JACKER_ROOT/data/traefik/acme/acme.json"

        info "Restarting Traefik..."
        docker restart traefik 2>/dev/null || true

        info "Certificates will be regenerated on first access"
        info "This may take a few minutes"
    fi

    success "Traefik certificate configuration fixed"
}

# Fix all directory permissions
fix_permissions() {
    section "Fixing All Directory Permissions"

    local dirs=(
        "traefik:root:root"
        "loki:10001:10001"
        "grafana:472:472"
        "prometheus:65534:65534"
        "alertmanager:65534:65534"
        "postgres:999:999"
        "crowdsec:root:root"
    )

    for dir_spec in "${dirs[@]}"; do
        IFS=':' read -r dir uid gid <<< "$dir_spec"
        if [[ -d "$JACKER_ROOT/data/$dir" ]]; then
            info "Fixing $dir (${uid}:${gid})..."
            sudo chown -R "${uid}:${gid}" "$JACKER_ROOT/data/$dir" 2>/dev/null || \
                chown -R "${uid}:${gid}" "$JACKER_ROOT/data/$dir"
        fi
    done

    # Special permissions
    if [[ -f "$JACKER_ROOT/data/traefik/acme/acme.json" ]]; then
        chmod 600 "$JACKER_ROOT/data/traefik/acme/acme.json"
    fi

    if [[ -d "$JACKER_ROOT/data/postgres" ]]; then
        chmod 700 "$JACKER_ROOT/data/postgres"
    fi

    success "All permissions fixed"
}

# Fix all known issues
fix_all() {
    section "Running All Fixes"

    local fixes=(
        "fix_permissions"
        "fix_postgres"
        "fix_loki"
        "fix_alertmanager"
        "fix_crowdsec"
    )

    local failed=0
    for fix in "${fixes[@]}"; do
        info "Running: $fix"
        if ! $fix; then
            warning "$fix failed"
            ((failed++))
        fi
        echo
    done

    if [[ $failed -eq 0 ]]; then
        success "All fixes completed successfully"
    else
        warning "$failed fix(es) failed"
    fi

    # Run health check
    info "Running health check..."
    if command_exists jacker; then
        jacker health
    else
        "$JACKER_ROOT/assets/lib/health-check.sh"
    fi
}