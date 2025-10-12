#!/bin/bash

# =============================================================================
# Jacker Enhancement Application Script
#
# This script applies security, performance, and integration enhancements
# to the Jacker Docker stack based on official documentation and best practices.
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script location detection
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi

cd "$JACKER_DIR" || exit 1

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if file exists
check_file() {
    if [[ ! -f "$1" ]]; then
        print_error "Required file not found: $1"
        return 1
    fi
    return 0
}

# Function to create backup
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
        print_info "Backed up $file"
    fi
}

# Function to ensure directory exists
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        print_info "Created directory: $dir"
    fi
}

# Function to apply enhancements
apply_enhancements() {
    print_info "Starting Jacker enhancement process..."

    # ==========================================================================
    # 1. ENSURE REQUIRED DIRECTORIES
    # ==========================================================================
    print_info "Creating required directories..."

    ensure_dir "data/traefik/rules"
    ensure_dir "data/traefik/acme"
    ensure_dir "data/traefik/logs"
    ensure_dir "data/traefik/certs"
    ensure_dir "data/traefik/plugins"

    ensure_dir "data/postgres/init"
    ensure_dir "data/postgres/backups"
    ensure_dir "data/postgres/archive"
    ensure_dir "data/postgres/ssl"
    ensure_dir "data/pgbackrest/config"
    ensure_dir "data/pgbackrest/log"

    ensure_dir "data/crowdsec/acquis.d"
    ensure_dir "data/crowdsec/patterns"
    ensure_dir "data/crowdsec/scenarios"
    ensure_dir "data/crowdsec/hub"

    ensure_dir "data/prometheus/targets.d/infrastructure"
    ensure_dir "data/prometheus/targets.d/applications"
    ensure_dir "data/prometheus/targets.d/exporters"
    ensure_dir "data/prometheus/targets.d/security"

    ensure_dir "data/alertmanager/templates"
    ensure_dir "data/grafana/dashboards"
    ensure_dir "data/grafana/provisioning/dashboards"
    ensure_dir "data/grafana/provisioning/datasources"

    # ==========================================================================
    # 2. SET PROPER PERMISSIONS
    # ==========================================================================
    print_info "Setting proper permissions..."

    # Traefik ACME file
    if [[ ! -f "data/traefik/acme/acme.json" ]]; then
        touch "data/traefik/acme/acme.json"
    fi
    chmod 600 "data/traefik/acme/acme.json"

    # Loki permissions (UID 10001 needs write access)
    chmod -R 777 data/loki/data 2>/dev/null || true

    # ==========================================================================
    # 3. UPDATE ENVIRONMENT VARIABLES
    # ==========================================================================
    print_info "Updating environment variables..."

    # Check if .env exists
    if [[ ! -f ".env" ]]; then
        print_warning ".env file not found. Please run 'make install' first."
        exit 1
    fi

    # Add new environment variables if not present
    add_env_var() {
        local var="$1"
        local default="$2"
        if ! grep -q "^${var}=" .env; then
            echo "${var}=${default}" >> .env
            print_info "Added ${var} to .env"
        fi
    }

    # PostgreSQL enhancements
    add_env_var "POSTGRES_SHARED_BUFFERS" "256MB"
    add_env_var "POSTGRES_WORK_MEM" "4MB"
    add_env_var "POSTGRES_MAINTENANCE_WORK_MEM" "64MB"
    add_env_var "POSTGRES_EFFECTIVE_CACHE_SIZE" "1GB"
    add_env_var "POSTGRES_MAX_CONNECTIONS" "200"
    add_env_var "POSTGRES_CROWDSEC_DB" "crowdsec_db"
    add_env_var "POSTGRES_MULTIPLE_DATABASES" "crowdsec_db,authentik_db,grafana_db"
    add_env_var "PGBACKREST_STANZA" "main"
    add_env_var "PGBACKREST_LOG_LEVEL" "info"

    # CrowdSec enhancements
    add_env_var "CROWDSEC_USE_TLS" "false"
    add_env_var "CROWDSEC_METRICS_PORT" "6060"
    add_env_var "CROWDSEC_LOG_LEVEL" "info"
    add_env_var "CROWDSEC_BAN_DURATION" "4h"
    add_env_var "CROWDSEC_GEOIP" "true"
    add_env_var "CROWDSEC_NOTIFICATIONS" "false"

    # Traefik enhancements
    add_env_var "TRAEFIK_LOG_LEVEL" "INFO"
    add_env_var "TRAEFIK_ACCESS_LOG_MODE" "keep"
    add_env_var "ENVIRONMENT" "production"

    # ==========================================================================
    # 4. CREATE ENHANCED CONFIGURATION FILES
    # ==========================================================================
    print_info "Creating enhanced configuration files..."

    # Create pg_hba.conf if not exists
    if [[ ! -f "data/postgres/pg_hba.conf" ]]; then
        cat > "data/postgres/pg_hba.conf" <<'EOF'
# PostgreSQL Client Authentication Configuration
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             all                                     trust

# IPv4 local connections
host    all             all             127.0.0.1/32            md5

# IPv4 connections from Docker network
host    all             all             10.0.0.0/8              md5
host    all             all             172.16.0.0/12           md5
host    all             all             192.168.0.0/16          md5

# IPv6 local connections
host    all             all             ::1/128                 md5

# Replication connections
host    replication     replicator      10.0.0.0/8              md5
host    replication     replicator      172.16.0.0/12           md5
EOF
        print_success "Created pg_hba.conf"
    fi

    # Create PostgreSQL init script for multiple databases
    cat > "data/postgres/init/00-create-databases.sh" <<'EOF'
#!/bin/bash
set -e

# Create multiple databases from POSTGRES_MULTIPLE_DATABASES variable
if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo "Creating multiple databases: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        if [ "$db" != "$POSTGRES_DB" ]; then
            echo "Creating database: $db"
            psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
                CREATE DATABASE "$db";
                GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$POSTGRES_USER";
EOSQL
        fi
    done
fi

# Create replication user if needed
if [ -n "$POSTGRES_REPLICATION_USER" ]; then
    echo "Creating replication user: $POSTGRES_REPLICATION_USER"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE USER "$POSTGRES_REPLICATION_USER" WITH REPLICATION ENCRYPTED PASSWORD '$POSTGRES_REPLICATION_PASSWORD';
EOSQL
fi

# Enable pg_stat_statements
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL
EOF
    chmod +x "data/postgres/init/00-create-databases.sh"

    # ==========================================================================
    # 5. CREATE MONITORING TARGETS
    # ==========================================================================
    print_info "Creating monitoring target configurations..."

    # Infrastructure targets
    cat > "data/prometheus/targets.d/infrastructure/docker.json" <<'EOF'
[
  {
    "targets": ["socket-proxy:2375"],
    "labels": {
      "job": "docker",
      "service": "docker-daemon",
      "component": "container-runtime"
    }
  },
  {
    "targets": ["traefik:8080"],
    "labels": {
      "job": "traefik",
      "service": "reverse-proxy",
      "component": "ingress"
    }
  }
]
EOF

    # Security targets
    cat > "data/prometheus/targets.d/security/crowdsec.json" <<'EOF'
[
  {
    "targets": ["crowdsec:6060"],
    "labels": {
      "job": "crowdsec",
      "service": "crowdsec",
      "component": "security-ips"
    }
  }
]
EOF

    # Application targets
    cat > "data/prometheus/targets.d/applications/apps.json" <<'EOF'
[
  {
    "targets": ["oauth:9090"],
    "labels": {
      "job": "oauth2-proxy",
      "service": "oauth2-proxy",
      "component": "authentication"
    }
  },
  {
    "targets": ["grafana:3000"],
    "labels": {
      "job": "grafana",
      "service": "grafana",
      "component": "monitoring"
    }
  }
]
EOF

    # ==========================================================================
    # 6. CREATE SSL CERTIFICATES (self-signed for testing)
    # ==========================================================================
    if [[ ! -f "data/postgres/ssl/server.crt" ]]; then
        print_info "Creating self-signed SSL certificates for PostgreSQL..."
        openssl req -new -x509 -days 365 -nodes -text -out data/postgres/ssl/server.crt \
            -keyout data/postgres/ssl/server.key -subj "/CN=postgres" 2>/dev/null
        chmod 600 data/postgres/ssl/server.key
        chmod 644 data/postgres/ssl/server.crt
        cp data/postgres/ssl/server.crt data/postgres/ssl/ca.crt
    fi

    # ==========================================================================
    # 7. VALIDATE CONFIGURATION
    # ==========================================================================
    print_info "Validating configuration files..."

    # Check YAML syntax (basic validation)
    for file in docker-compose.yml compose/*.yml; do
        if [[ -f "$file" ]]; then
            # Basic YAML syntax check using Python
            if command -v python3 &> /dev/null; then
                python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null && \
                    print_success "Valid: $file" || \
                    print_warning "Potential issue in: $file"
            fi
        fi
    done

    # ==========================================================================
    # 8. SUMMARY
    # ==========================================================================
    echo
    print_success "Enhancement process completed!"
    echo
    print_info "Summary of changes:"
    echo "  - Enhanced Traefik configuration with security headers and performance tuning"
    echo "  - Enhanced PostgreSQL with optimized settings and backup support"
    echo "  - Enhanced CrowdSec with comprehensive collections and PostgreSQL backend"
    echo "  - Added monitoring networks and target configurations"
    echo "  - Created required directories with proper permissions"
    echo "  - Added new environment variables for enhanced features"
    echo
    print_warning "Next steps:"
    echo "  1. Review the changes in compose/*.yml files"
    echo "  2. Update any custom configurations as needed"
    echo "  3. Run 'make restart' to apply the enhancements"
    echo "  4. Monitor logs with 'make logs' to ensure services start correctly"
    echo
    print_info "For more details, see: jacker-docs/docs/guides/compose-enhancements.md"
}

# Main execution
main() {
    echo "========================================="
    echo "   Jacker Enhancement Application Script"
    echo "========================================="
    echo

    # Check if running from correct directory
    if [[ ! -f "docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found. Please run from Jacker root directory."
        exit 1
    fi

    # Apply enhancements
    apply_enhancements
}

# Run main function
main "$@"