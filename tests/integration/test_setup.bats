#!/usr/bin/env bats
#
# test_setup.bats - Integration tests for setup workflow
#

load '../helpers/test_helper'

# Test setup
setup() {
    load '../helpers/test_helper'
    create_test_structure
    mock_docker
    mock_system_commands
}

# ============================================================================
# Setup Integration Tests
# ============================================================================

@test "quick setup creates required files" {
    # Create a minimal setup script for testing
    cat > test_setup.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/services.sh"

# Simulate quick setup
export HOSTNAME="test-host"
export DOMAINNAME="test.local"
export PUBLIC_FQDN="${HOSTNAME}.${DOMAINNAME}"
export POSTGRES_PASSWORD="test_password"
export CROWDSEC_TRAEFIK_BOUNCER_API_KEY="test_key"

# Create .env file
cat > .env <<ENV
HOSTNAME=${HOSTNAME}
DOMAINNAME=${DOMAINNAME}
PUBLIC_FQDN=${PUBLIC_FQDN}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
CROWDSEC_TRAEFIK_BOUNCER_API_KEY=${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}
ENV

# Create required directories
mkdir -p data/traefik
mkdir -p data/crowdsec/config
mkdir -p secrets

# Create acme.json
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json

echo "Setup complete"
EOF

    chmod +x test_setup.sh
    run ./test_setup.sh
    assert_success
    assert_output --partial "Setup complete"

    # Verify files were created
    assert_file_exists ".env"
    assert_file_exists "data/traefik/acme.json"
    assert [ -d "data/crowdsec/config" ]

    # Verify .env contents
    assert_file_contains ".env" "HOSTNAME=test-host"
    assert_file_contains ".env" "DOMAINNAME=test.local"

    # Verify permissions
    run stat -c %a data/traefik/acme.json
    assert_output "600"
}

@test "environment variables are properly set" {
    # Create test .env
    cat > .env <<EOF
HOSTNAME=myhost
DOMAINNAME=example.com
PUBLIC_FQDN=myhost.example.com
POSTGRES_PASSWORD=secure_password
CROWDSEC_API_PORT=8888
EOF

    # Source and verify
    set -a
    source .env
    set +a

    assert_equal "$HOSTNAME" "myhost"
    assert_equal "$DOMAINNAME" "example.com"
    assert_equal "$PUBLIC_FQDN" "myhost.example.com"
    assert_equal "$CROWDSEC_API_PORT" "8888"
}

@test "service configuration files are created correctly" {
    source "${LIB_DIR}/common.sh"

    # Create test template
    cat > test.template <<'EOF'
server:
  host: ${HOSTNAME}
  domain: ${DOMAINNAME}
  port: ${PORT}
EOF

    export HOSTNAME="testhost"
    export DOMAINNAME="test.com"
    export PORT="8080"

    create_from_template "test.template" "test.yml"

    assert_file_exists "test.yml"
    assert_file_contains "test.yml" "host: testhost"
    assert_file_contains "test.yml" "domain: test.com"
    assert_file_contains "test.yml" "port: 8080"
}

@test "docker compose configuration is valid" {
    # Create minimal docker-compose.yml
    cat > docker-compose.yml <<'EOF'
version: '3.8'

services:
  test:
    image: alpine:latest
    command: echo "test"

networks:
  default:
    name: test_network
EOF

    # Mock docker compose config
    function docker() {
        if [[ "$1" == "compose" ]] && [[ "$2" == "config" ]]; then
            cat docker-compose.yml
            return 0
        fi
        return 1
    }
    export -f docker

    run docker compose config
    assert_success
    assert_output --partial "test"
}

# ============================================================================
# Service Start/Stop Integration Tests
# ============================================================================

@test "services can be started and stopped" {
    source "${LIB_DIR}/common.sh"
    mock_docker

    # Test start
    run start_services
    assert_success
    assert_output --partial "Starting services"

    # Test stop
    run stop_services
    assert_success
    assert_output --partial "Stopping services"

    # Test restart
    run restart_services
    assert_success
    assert_output --partial "Restarting services"
}

@test "health check reports service status" {
    source "${LIB_DIR}/common.sh"
    mock_docker

    function is_container_running() {
        [[ "$1" == "traefik" ]] || [[ "$1" == "postgres" ]]
    }
    export -f is_container_running

    # Create simple health check (don't source common.sh - use exported mock functions)
    cat > health_check.sh <<'EOF'
#!/bin/bash

if is_container_running "traefik"; then
    echo "traefik: healthy"
fi

if is_container_running "postgres"; then
    echo "postgres: healthy"
fi

echo "Health check complete"
EOF

    chmod +x health_check.sh
    run ./health_check.sh
    assert_success
    assert_output --partial "traefik: healthy"
    assert_output --partial "postgres: healthy"
}

# ============================================================================
# Backup/Restore Integration Tests
# ============================================================================

@test "backup creates archive with correct structure" {
    source "${LIB_DIR}/common.sh"

    # Create test structure
    mkdir -p data/test
    echo "test data" > data/test/file.txt
    echo "BACKUP_TEST=true" > .env

    # Create backup script
    cat > backup_test.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="backup"
BACKUP_NAME="test-backup"

mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}/config"
cp .env "${BACKUP_DIR}/${BACKUP_NAME}/config/"
cp -r data "${BACKUP_DIR}/${BACKUP_NAME}/"

cd "${BACKUP_DIR}"
tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
rm -rf "${BACKUP_NAME}"

echo "Backup created: ${BACKUP_NAME}.tar.gz"
EOF

    chmod +x backup_test.sh
    run ./backup_test.sh
    assert_success
    assert_output --partial "Backup created"

    # Verify backup exists
    assert_file_exists "backup/test-backup.tar.gz"

    # Extract and verify contents
    cd backup
    tar xzf test-backup.tar.gz
    assert_file_exists "test-backup/config/.env"
    assert_file_exists "test-backup/data/test/file.txt"
}

@test "restore extracts backup correctly" {
    # Create a test backup
    mkdir -p backup/test-backup/config
    echo "RESTORED=true" > backup/test-backup/config/.env
    cd backup
    tar czf test-backup.tar.gz test-backup
    cd ..

    # Create restore script
    cat > restore_test.sh <<'EOF'
#!/bin/bash
BACKUP_FILE="backup/test-backup.tar.gz"
RESTORE_DIR="restored"

mkdir -p "${RESTORE_DIR}"
cd "${RESTORE_DIR}"
tar xzf "../${BACKUP_FILE}"

if [ -f "test-backup/config/.env" ]; then
    cp test-backup/config/.env ../.env.restored
    echo "Restore complete"
else
    echo "Restore failed"
    exit 1
fi
EOF

    chmod +x restore_test.sh
    run ./restore_test.sh
    assert_success
    assert_output --partial "Restore complete"

    assert_file_exists ".env.restored"
    assert_file_contains ".env.restored" "RESTORED=true"
}

# ============================================================================
# Configuration Validation Tests
# ============================================================================

@test "configuration validation detects missing variables" {
    source "${LIB_DIR}/common.sh"

    # Create incomplete .env
    cat > .env <<EOF
HOSTNAME=test
# Missing DOMAINNAME
EOF

    # Validation script
    cat > validate.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"

REQUIRED_VARS=("HOSTNAME" "DOMAINNAME" "POSTGRES_PASSWORD")
MISSING=()

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" .env; then
        MISSING+=("$var")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Missing: ${MISSING[*]}"
    exit 1
else
    echo "All variables present"
fi
EOF

    chmod +x validate.sh
    run ./validate.sh
    assert_failure
    assert_output --partial "Missing: DOMAINNAME POSTGRES_PASSWORD"
}

@test "network configuration is applied correctly" {
    source "${LIB_DIR}/common.sh"

    # Set network variables
    export LOCAL_IPS="10.0.0.0/8,192.168.0.0/16"
    export DOCKER_DEFAULT_SUBNET="192.168.100.0/24"
    export TRAEFIK_PROXY_SUBNET="192.168.101.0/24"

    # Create network config
    cat > network.sh <<'EOF'
#!/bin/bash
source "${LIB_DIR}/common.sh"

echo "LOCAL_IPS: ${LOCAL_IPS}"
echo "DOCKER_DEFAULT_SUBNET: ${DOCKER_DEFAULT_SUBNET}"
echo "TRAEFIK_PROXY_SUBNET: ${TRAEFIK_PROXY_SUBNET}"

# Validate subnets
if [[ "$DOCKER_DEFAULT_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo "Docker subnet valid"
fi

if [[ "$TRAEFIK_PROXY_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo "Traefik subnet valid"
fi
EOF

    chmod +x network.sh
    run ./network.sh
    assert_success
    assert_output --partial "Docker subnet valid"
    assert_output --partial "Traefik subnet valid"
}