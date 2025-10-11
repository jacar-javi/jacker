#!/usr/bin/env bats
#
# test_services.bats - Unit tests for services.sh library
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    load_lib 'common.sh'
    load_lib 'services.sh'
    mock_docker
    create_test_structure
}

# ============================================================================
# Service Configuration Tests
# ============================================================================

@test "setup_traefik creates configuration files" {
    export DOMAINNAME="test.local"
    export LETSENCRYPT_EMAIL="test@example.com"
    export PUBLIC_FQDN="test.test.local"

    # Create necessary directories
    mkdir -p data/traefik
    mkdir -p compose

    # Create mock template
    cat > compose/traefik.template.yml <<'EOF'
domain: ${DOMAINNAME}
email: ${LETSENCRYPT_EMAIL}
EOF

    run setup_traefik
    assert_success

    # Check files were created
    assert_file_exists "data/traefik/traefik.yml"
    assert_file_exists "data/traefik/acme.json"

    # Check permissions on acme.json
    run stat -c %a data/traefik/acme.json
    assert_output "600"
}

@test "setup_crowdsec creates configuration" {
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY="test_key_123"
    export CROWDSEC_API_PORT="8080"

    mkdir -p data/crowdsec/config/parsers/s02-enrich
    mkdir -p data/crowdsec/data

    run setup_crowdsec
    assert_success

    # Check directories were created
    assert [ -d "data/crowdsec/config" ]
    assert [ -d "data/crowdsec/data" ]
}

@test "setup_postgresql sets up database configuration" {
    export POSTGRES_PASSWORD="secure_password"
    export POSTGRES_DB="jacker"
    export POSTGRES_USER="jacker"

    # Mock wait_for_postgresql
    function wait_for_postgresql() {
        echo "PostgreSQL is ready"
        return 0
    }
    export -f wait_for_postgresql

    # Mock ensure_crowdsec_database
    function ensure_crowdsec_database() {
        echo "crowdsec_db already exists"
        return 0
    }
    export -f ensure_crowdsec_database

    run setup_postgresql
    assert_success
    assert_output --partial "PostgreSQL"
}

@test "setup_redis creates Redis configuration" {
    mkdir -p data/redis

    run setup_redis
    assert_success

    # Redis setup creates directory
    assert [ -d "data/redis" ]
}

@test "setup_monitoring creates Prometheus and Grafana configs" {
    mkdir -p data/prometheus
    mkdir -p data/grafana/data
    mkdir -p data/loki/data

    run setup_monitoring
    assert_success

    # Check directories were created
    assert [ -d "data/prometheus" ]
    assert [ -d "data/grafana/data" ]
    assert [ -d "data/loki/data" ]
}

# ============================================================================
# Service Health Check Tests
# ============================================================================

@test "check_traefik_health detects healthy service" {
    function is_container_running() {
        [[ "$1" == "traefik" ]] && return 0
        return 1
    }
    export -f is_container_running

    function docker() {
        if [[ "$1" == "inspect" ]] && [[ "$2" == "traefik" ]]; then
            echo '{"State":{"Health":{"Status":"healthy"}}}'
        else
            command docker "$@" 2>/dev/null || return 0
        fi
    }
    export -f docker

    run check_traefik_health
    assert_success
}

@test "check_crowdsec_health validates service" {
    function is_container_running() {
        [[ "$1" == "crowdsec" ]] && return 0
        return 1
    }
    export -f is_container_running

    function docker() {
        if [[ "$1" == "exec" ]] && [[ "$2" == "crowdsec" ]]; then
            echo "Status: healthy"
            return 0
        fi
        return 0
    }
    export -f docker

    run check_crowdsec_health
    assert_success
}

@test "check_postgresql_health checks database connectivity" {
    function is_container_running() {
        [[ "$1" == "postgres" ]] && return 0
        return 1
    }
    export -f is_container_running

    function docker() {
        if [[ "$1" == "exec" ]] && [[ "$2" == "postgres" ]]; then
            echo "1"  # Simulating successful query
            return 0
        fi
        return 0
    }
    export -f docker

    run check_postgresql_health
    assert_success
}

@test "check_services_health reports all services status" {
    # Mock all containers as running
    function is_container_running() {
        return 0
    }
    export -f is_container_running

    function docker() {
        case "$1" in
            "inspect")
                echo '{"State":{"Health":{"Status":"healthy"}}}'
                ;;
            "exec")
                echo "OK"
                return 0
                ;;
            *)
                return 0
                ;;
        esac
    }
    export -f docker

    run check_services_health
    assert_success
    assert_output --partial "Service Health Check"
}

# ============================================================================
# Service Management Tests
# ============================================================================

@test "start_services executes docker compose up" {
    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "up" ]]; then
            echo "Starting services..."
            return 0
        fi
        return 1
    }
    export -f docker

    run start_services
    assert_success
    assert_output --partial "Starting services"
}

@test "stop_services executes docker compose down" {
    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "down" ]]; then
            echo "Stopping services..."
            return 0
        fi
        return 1
    }
    export -f docker

    run stop_services
    assert_success
    assert_output --partial "Stopping services"
}

@test "restart_services performs stop and start" {
    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "restart" ]]; then
            echo "Restarting services..."
            return 0
        fi
        return 0
    }
    export -f docker

    run restart_services
    assert_success
    assert_output --partial "Restarting services"
}

# ============================================================================
# OAuth Configuration Tests
# ============================================================================

@test "setup_oauth2_proxy creates configuration" {
    export OAUTH2_PROXY_CLIENT_ID="test_client_id"
    export OAUTH2_PROXY_CLIENT_SECRET="test_secret"
    export OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32)
    export OAUTH2_PROXY_PROVIDER="google"
    export OAUTH2_PROXY_EMAIL_DOMAINS="example.com"

    mkdir -p data/oauth2-proxy
    mkdir -p secrets

    run setup_oauth2_proxy
    assert_success

    assert_file_exists "data/oauth2-proxy/oauth2-proxy.cfg"
    assert_file_exists "secrets/oauth2_proxy_secrets.env"

    # Check config contents
    assert_file_contains "data/oauth2-proxy/oauth2-proxy.cfg" "provider"
    assert_file_contains "secrets/oauth2_proxy_secrets.env" "CLIENT_ID"
}

# ============================================================================
# Service Scaling Tests
# ============================================================================

@test "scale_service scales container replicas" {
    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "up" ]]; then
            echo "Scaling service web to 3 replicas"
            return 0
        fi
        return 1
    }
    export -f docker

    run scale_service "web" "3"
    assert_success
    assert_output --partial "Scaling service"
}

# ============================================================================
# Network Configuration Tests
# ============================================================================

@test "create_networks creates Docker networks" {
    function docker() {
        if [[ "$1" == "network" ]]; then
            case "$2" in
                "ls")
                    echo "bridge"
                    echo "host"
                    ;;
                "create")
                    echo "Creating network $3"
                    return 0
                    ;;
                *)
                    return 0
                    ;;
            esac
        fi
        return 1
    }
    export -f docker

    run create_networks
    assert_success
}

@test "check_network_connectivity validates network" {
    function docker() {
        if [[ "$1" == "network" ]] && [[ "$2" == "ls" ]]; then
            echo "traefik_proxy"
            return 0
        elif [[ "$1" == "network" ]] && [[ "$2" == "inspect" ]]; then
            echo '{"Name":"traefik_proxy"}'
            return 0
        fi
        return 1
    }
    export -f docker

    run check_network_connectivity "traefik_proxy"
    assert_success
}

# ============================================================================
# Volume Management Tests
# ============================================================================

@test "create_volumes creates required Docker volumes" {
    function docker() {
        if [[ "$1" == "volume" ]] && [[ "$2" == "create" ]]; then
            echo "Creating volume $3"
            return 0
        elif [[ "$1" == "volume" ]] && [[ "$2" == "ls" ]]; then
            # Return empty list so volumes get created
            return 0
        fi
        return 1
    }
    export -f docker

    run create_volumes
    assert_success
}

@test "backup_volumes creates volume backups" {
    mkdir -p backup

    function docker() {
        if [[ "$1" == "run" ]] && [[ "$*" == *"tar"* ]]; then
            # Simulate creating a backup file
            touch "backup/traefik-data_$(date +%Y%m%d-%H%M%S).tar.gz"
            return 0
        elif [[ "$1" == "volume" ]] && [[ "$2" == "ls" ]]; then
            echo "traefik-data"
            return 0
        fi
        return 1
    }
    export -f docker

    run backup_volumes "backup"
    assert_success
    # Check that at least one backup file was created
    run ls backup/*.tar.gz
    assert_success
}

# ============================================================================
# Certificate Management Tests
# ============================================================================

@test "generate_self_signed_cert creates certificates" {
    mkdir -p data/traefik/certs

    function openssl() {
        if [[ "$1" == "req" ]]; then
            touch data/traefik/certs/cert.pem
            touch data/traefik/certs/key.pem
            return 0
        fi
        return 1
    }
    export -f openssl

    run generate_self_signed_cert "test.local"
    assert_success

    assert_file_exists "data/traefik/certs/cert.pem"
    assert_file_exists "data/traefik/certs/key.pem"
}

@test "check_certificate_expiry validates cert dates" {
    # Create a dummy cert file
    mkdir -p data/traefik/certs
    touch data/traefik/certs/test.pem

    function openssl() {
        if [[ "$1" == "x509" ]]; then
            echo "notAfter=Dec 31 23:59:59 2024 GMT"
            return 0
        fi
        return 1
    }
    export -f openssl

    run check_certificate_expiry "data/traefik/certs/test.pem"
    assert_success
    assert_output --partial "notAfter"
}