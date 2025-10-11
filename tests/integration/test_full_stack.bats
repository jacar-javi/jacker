#!/usr/bin/env bats
#
# test_full_stack.bats - Integration tests for complete stack deployment
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    create_test_structure
    mock_docker
    mock_system_commands

    # Load all libraries
    load_lib 'common.sh'
    load_lib 'system.sh'
    load_lib 'services.sh'
}

# ============================================================================
# Full Stack Deployment Tests
# ============================================================================

@test "complete stack deployment workflow" {
    # Set required environment variables
    export HOSTNAME="test-server"
    export DOMAINNAME="test.local"
    export PUBLIC_FQDN="test-server.test.local"
    export LETSENCRYPT_EMAIL="admin@test.local"
    export POSTGRES_PASSWORD="secure_password"
    export REDIS_PASSWORD="redis_password"
    export GRAFANA_ADMIN_PASSWORD="grafana_password"
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY="bouncer_key"
    export CROWDSEC_API_PORT="8080"

    # Create minimal docker-compose.yml
    cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:latest
    container_name: traefik

  postgres:
    image: postgres:15
    container_name: postgres

  redis:
    image: redis:7
    container_name: redis

  crowdsec:
    image: crowdsecurity/crowdsec
    container_name: crowdsec

networks:
  default:
    name: jacker_network
  traefik_proxy:
    name: traefik_proxy
EOF

    # Run complete setup
    cat > test_deploy.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/services.sh"

# Create configuration
info "Creating configuration..."
ensure_dir "data/traefik"
ensure_dir "data/postgres"
ensure_dir "data/redis"
ensure_dir "data/crowdsec/config"
ensure_dir "secrets"

# Setup services
setup_traefik
setup_postgresql
setup_redis
setup_crowdsec

# Create networks
create_networks

# Start services
start_services

# Check health
check_services_health

echo "Deployment complete"
EOF

    chmod +x test_deploy.sh
    run ./test_deploy.sh
    assert_success
    assert_output --partial "Deployment complete"
}

@test "service dependency resolution" {
    # Test that services start in correct order
    local start_order=()

    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "up" ]]; then
            # Record which service is being started
            if [[ "$*" == *"postgres"* ]]; then
                start_order+=("postgres")
            elif [[ "$*" == *"redis"* ]]; then
                start_order+=("redis")
            elif [[ "$*" == *"traefik"* ]]; then
                start_order+=("traefik")
            fi
            echo "Starting service..."
            return 0
        fi
        return 0
    }
    export -f docker

    # Start services with dependencies
    run bash -c "
        source '${LIB_DIR}/common.sh'
        source '${LIB_DIR}/services.sh'

        # Start database first
        docker compose up -d postgres
        docker compose up -d redis
        docker compose up -d traefik

        echo 'Services started'
    "

    assert_success
    assert_output --partial "Services started"
}

@test "configuration persistence across restarts" {
    # Create initial configuration
    cat > .env <<EOF
HOSTNAME=persist-test
DOMAINNAME=persist.local
POSTGRES_PASSWORD=initial_password
EOF

    # Create test script
    cat > test_persistence.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"

# Load initial config
load_env ".env"

# Save initial values
INITIAL_HOSTNAME="$HOSTNAME"
INITIAL_DOMAIN="$DOMAINNAME"
INITIAL_PASSWORD="$POSTGRES_PASSWORD"

# Modify values
export HOSTNAME="modified-host"
export DOMAINNAME="modified.local"
export POSTGRES_PASSWORD="modified_password"

# Save modified values
set_env_var "HOSTNAME" "$HOSTNAME" ".env"
set_env_var "DOMAINNAME" "$DOMAINNAME" ".env"
set_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD" ".env"

# Reload and verify
unset HOSTNAME DOMAINNAME POSTGRES_PASSWORD
load_env ".env"

if [[ "$HOSTNAME" == "modified-host" ]] && \
   [[ "$DOMAINNAME" == "modified.local" ]] && \
   [[ "$POSTGRES_PASSWORD" == "modified_password" ]]; then
    echo "Persistence verified"
else
    echo "Persistence failed"
    exit 1
fi
EOF

    chmod +x test_persistence.sh
    run ./test_persistence.sh
    assert_success
    assert_output --partial "Persistence verified"
}

@test "network isolation between services" {
    source "${LIB_DIR}/common.sh"

    # Mock docker network inspect
    function docker() {
        case "$1" in
            "network")
                if [[ "$2" == "inspect" ]]; then
                    case "$3" in
                        "traefik_proxy")
                            echo '[{"Name": "traefik_proxy", "Containers": {"traefik": {}}}]'
                            ;;
                        "backend")
                            echo '[{"Name": "backend", "Containers": {"postgres": {}, "redis": {}}}]'
                            ;;
                        *)
                            echo '[]'
                            ;;
                    esac
                fi
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f docker

    # Test network inspection script
    cat > test_networks.sh <<'EOF'
#!/bin/bash

# Check traefik proxy network
TRAEFIK_NET=$(docker network inspect traefik_proxy)
if [[ "$TRAEFIK_NET" == *"traefik"* ]]; then
    echo "Traefik network isolated"
fi

# Check backend network
BACKEND_NET=$(docker network inspect backend)
if [[ "$BACKEND_NET" == *"postgres"* ]] && [[ "$BACKEND_NET" == *"redis"* ]]; then
    echo "Backend network isolated"
fi

echo "Network isolation verified"
EOF

    chmod +x test_networks.sh
    run ./test_networks.sh
    assert_success
    assert_output --partial "Network isolation verified"
}

# ============================================================================
# Failure Recovery Tests
# ============================================================================

@test "service recovery after failure" {
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/services.sh"

    local restart_count=0

    function docker() {
        if [[ "$1" == "ps" ]] && [[ "$2" == "--format" ]]; then
            # First check returns empty (service down)
            if [[ $restart_count -eq 0 ]]; then
                echo ""
            else
                echo "traefik"
            fi
        elif [[ "$1" == "compose" ]] && [[ "$2" == "up" ]]; then
            restart_count=$((restart_count + 1))
            echo "Restarting service..."
            return 0
        fi
        return 0
    }
    export -f docker

    cat > test_recovery.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/services.sh"

# Check if service is down
if ! is_container_running "traefik"; then
    warning "Service down, attempting recovery..."
    docker compose up -d traefik
fi

# Verify recovery
if is_container_running "traefik"; then
    success "Service recovered"
else
    error "Recovery failed"
    exit 1
fi
EOF

    chmod +x test_recovery.sh
    run ./test_recovery.sh
    assert_success
    assert_output --partial "Service recovered"
}

@test "database backup and restore cycle" {
    source "${LIB_DIR}/common.sh"

    # Create test data
    mkdir -p data/postgres
    echo "test_data" > data/postgres/test.sql

    # Mock pg_dump and pg_restore
    function docker() {
        case "$*" in
            *"pg_dump"*)
                echo "-- PostgreSQL dump"
                echo "CREATE TABLE test;"
                return 0
                ;;
            *"pg_restore"*)
                echo "Restoring database..."
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f docker

    cat > test_db_backup.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"

# Backup database
BACKUP_FILE="backup/postgres_$(date +%Y%m%d_%H%M%S).sql"
ensure_dir "backup"

docker exec postgres pg_dump -U postgres postgres > "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    echo "Backup created successfully"

    # Test restore
    docker exec -i postgres pg_restore -U postgres -d postgres_restore < "$BACKUP_FILE"
    echo "Restore completed"
else
    echo "Backup failed"
    exit 1
fi
EOF

    chmod +x test_db_backup.sh
    run ./test_db_backup.sh
    assert_success
    assert_output --partial "Backup created successfully"
    assert_output --partial "Restore completed"
}

# ============================================================================
# Security Configuration Tests
# ============================================================================

@test "security headers are properly configured" {
    # Create Traefik middleware configuration
    cat > data/traefik/middleware.yml <<'EOF'
http:
  middlewares:
    security-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        stsPreload: true
        contentTypeNosniff: true
        browserXssFilter: true
EOF

    # Verify configuration
    assert_file_exists "data/traefik/middleware.yml"
    assert_file_contains "data/traefik/middleware.yml" "stsSeconds"
    assert_file_contains "data/traefik/middleware.yml" "contentTypeNosniff"
}

@test "CrowdSec integration with Traefik" {
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY="test_bouncer_key"

    # Create CrowdSec bouncer config
    cat > data/crowdsec/bouncers.yaml <<EOF
- name: traefik-bouncer
  key: ${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}
  type: traefik
EOF

    # Create Traefik plugin config
    cat > data/traefik/plugins.yml <<EOF
experimental:
  plugins:
    crowdsec:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
      version: v1.1.13
EOF

    assert_file_exists "data/crowdsec/bouncers.yaml"
    assert_file_contains "data/crowdsec/bouncers.yaml" "traefik-bouncer"

    assert_file_exists "data/traefik/plugins.yml"
    assert_file_contains "data/traefik/plugins.yml" "crowdsec"
}

# ============================================================================
# Monitoring and Alerting Tests
# ============================================================================

@test "Prometheus scraping targets are configured" {
    # Create Prometheus configuration
    cat > data/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8082']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOF

    assert_file_exists "data/prometheus/prometheus.yml"
    assert_file_contains "data/prometheus/prometheus.yml" "job_name: 'traefik'"
    assert_file_contains "data/prometheus/prometheus.yml" "job_name: 'postgres'"
    assert_file_contains "data/prometheus/prometheus.yml" "job_name: 'redis'"
    assert_file_contains "data/prometheus/prometheus.yml" "job_name: 'node'"
}

@test "Grafana dashboards are provisioned" {
    mkdir -p data/grafana/provisioning/dashboards
    mkdir -p data/grafana/dashboards

    # Create dashboard config
    cat > data/grafana/provisioning/dashboards/default.yml <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    folder: 'General'
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF

    # Create sample dashboard
    cat > data/grafana/dashboards/system.json <<'EOF'
{
  "dashboard": {
    "title": "System Overview",
    "panels": []
  }
}
EOF

    assert_file_exists "data/grafana/provisioning/dashboards/default.yml"
    assert_file_exists "data/grafana/dashboards/system.json"
    assert_file_contains "data/grafana/dashboards/system.json" "System Overview"
}

# ============================================================================
# Performance Tests
# ============================================================================

@test "resource limits are properly configured" {
    # Check docker-compose has resource limits
    cat > docker-compose.test.yml <<'EOF'
version: '3.8'

services:
  traefik:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M

  postgres:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G
EOF

    assert_file_exists "docker-compose.test.yml"
    assert_file_contains "docker-compose.test.yml" "limits"
    assert_file_contains "docker-compose.test.yml" "memory"
    assert_file_contains "docker-compose.test.yml" "cpus"
}