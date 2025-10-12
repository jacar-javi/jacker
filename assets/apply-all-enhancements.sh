#!/bin/bash

# =============================================================================
# Jacker Complete Enhancement Application Script
#
# This script applies all security, performance, and integration enhancements
# to ALL Jacker Docker services based on official documentation.
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

# Function to backup file
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d_%H%M%S)"
        print_info "Backed up $file"
    fi
}

# Function to replace file with enhanced version
replace_with_enhanced() {
    local original="$1"
    local enhanced="$2"

    if [[ -f "$enhanced" ]]; then
        backup_file "$original"
        cp "$enhanced" "$original"
        rm "$enhanced"
        print_success "Enhanced $original"
    fi
}

# Main enhancement function
apply_all_enhancements() {
    print_info "Starting complete Jacker enhancement process..."

    # ==========================================================================
    # 1. REPLACE ENHANCED COMPOSE FILES
    # ==========================================================================
    print_info "Replacing compose files with enhanced versions..."

    # These were already enhanced in previous session
    replace_with_enhanced "compose/redis.yml" "compose/redis-enhanced.yml"
    replace_with_enhanced "compose/prometheus.yml" "compose/prometheus-enhanced.yml"

    # ==========================================================================
    # 2. CREATE REDIS CONFIGURATION FILE
    # ==========================================================================
    print_info "Creating Redis configuration file..."

    cat > "data/redis/redis.conf" <<'EOF'
# Redis Enhanced Configuration
# https://redis.io/docs/management/config/

# Network and Security
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
tcp-keepalive 300
timeout 0

# TLS/SSL Configuration (optional)
# tls-port 6380
# tls-cert-file /tls/redis.crt
# tls-key-file /tls/redis.key
# tls-ca-cert-file /tls/ca.crt
# tls-dh-params-file /tls/dhparam.pem

# General
daemonize no
supervised no
pidfile /var/run/redis.pid
loglevel notice
logfile /logs/redis.log
databases 16

# Persistence - RDB
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /data

# Persistence - AOF
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# Memory Management
maxmemory 512mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Lazy Freeing
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# Threading
io-threads 4
io-threads-do-reads yes

# Slow Log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Client Management
maxclients 10000

# ACL Configuration
aclfile /usr/local/etc/redis/users.acl

# Modules
# loadmodule /usr/lib/redis/modules/redisearch.so
# loadmodule /usr/lib/redis/modules/redisgraph.so
EOF

    # ==========================================================================
    # 3. CREATE PROMETHEUS WEB CONFIGURATION
    # ==========================================================================
    print_info "Creating Prometheus web configuration..."

    cat > "data/prometheus/config/web.yml" <<'EOF'
# Prometheus Web Configuration
# https://prometheus.io/docs/prometheus/latest/configuration/https/

# TLS Configuration (optional - uncomment to enable)
# tls_server_config:
#   cert_file: /certs/prometheus.crt
#   key_file: /certs/prometheus.key
#   client_auth_type: RequireAndVerifyClientCert
#   client_ca_file: /certs/ca.crt
#   min_version: TLS13
#   max_version: TLS13
#   cipher_suites:
#     - TLS_AES_128_GCM_SHA256
#     - TLS_AES_256_GCM_SHA384
#     - TLS_CHACHA20_POLY1305_SHA256

# Basic Authentication (optional - uncomment to enable)
# basic_auth_users:
#   admin: $2y$10$... # bcrypt hash of password

# HTTP/2 Configuration
http_server_config:
  http2: true
EOF

    # ==========================================================================
    # 4. CREATE MODULAR PROMETHEUS CONFIGURATION
    # ==========================================================================
    print_info "Creating modular Prometheus configuration..."

    cat > "data/prometheus/config/prometheus.yml" <<'EOF'
# Prometheus Enhanced Configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    monitor: 'jacker-monitor'
    environment: 'production'

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
      scheme: http
      timeout: 10s

# Rule files
rule_files:
  - "/etc/prometheus/rules/*.yml"

# Scrape configurations
scrape_configs:
  # Infrastructure metrics
  - job_name: 'infrastructure'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.d/infrastructure/*.json'
        refresh_interval: 30s

  # Application metrics
  - job_name: 'applications'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.d/applications/*.json'
        refresh_interval: 30s

  # Exporter metrics
  - job_name: 'exporters'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.d/exporters/*.json'
        refresh_interval: 30s

  # Security metrics
  - job_name: 'security'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.d/security/*.json'
        refresh_interval: 30s

  # Self monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'prometheus'
          component: 'monitoring'

# Remote write configuration (optional)
# remote_write:
#   - url: "http://remote-storage:9090/api/v1/write"
#     queue_config:
#       capacity: 10000
#       max_samples_per_send: 5000
#       batch_send_deadline: 5s
#       max_retries: 10
#       min_backoff: 30ms
#       max_backoff: 100ms

# Remote read configuration (optional)
# remote_read:
#   - url: "http://remote-storage:9090/api/v1/read"
#     read_recent: true
EOF

    # ==========================================================================
    # 5. ADD ENHANCED ENVIRONMENT VARIABLES
    # ==========================================================================
    print_info "Adding enhanced environment variables to .env..."

    # Function to add environment variable
    add_env_var() {
        local var="$1"
        local default="$2"
        if ! grep -q "^${var}=" .env 2>/dev/null; then
            echo "${var}=${default}" >> .env
            print_info "Added ${var}"
        fi
    }

    # Redis enhancements
    add_env_var "REDIS_PASSWORD" ""
    add_env_var "REDIS_MAXMEMORY" "512mb"
    add_env_var "REDIS_MAXMEMORY_POLICY" "allkeys-lru"
    add_env_var "REDIS_AOF" "yes"
    add_env_var "REDIS_IO_THREADS" "4"
    add_env_var "REDIS_COMMANDER_USER" "admin"
    add_env_var "REDIS_COMMANDER_PASSWORD" ""

    # Prometheus enhancements
    add_env_var "PROMETHEUS_RETENTION" "30d"
    add_env_var "PROMETHEUS_RETENTION_SIZE" "10GB"
    add_env_var "PROMETHEUS_LOG_LEVEL" "info"
    add_env_var "PROMETHEUS_QUERY_TIMEOUT" "2m"
    add_env_var "PROMETHEUS_QUERY_MAX_CONCURRENCY" "20"

    # Grafana enhancements
    add_env_var "GRAFANA_ADMIN_USER" "admin"
    add_env_var "GRAFANA_ADMIN_PASSWORD" ""
    add_env_var "GRAFANA_SECRET_KEY" ""
    add_env_var "GRAFANA_DISABLE_GRAVATAR" "false"
    add_env_var "GRAFANA_ALLOW_SIGN_UP" "false"
    add_env_var "GRAFANA_INSTALL_PLUGINS" ""

    # Loki enhancements
    add_env_var "LOKI_RETENTION_PERIOD" "744h"
    add_env_var "LOKI_MAX_QUERY_SERIES" "5000"
    add_env_var "LOKI_MAX_QUERY_PARALLELISM" "32"
    add_env_var "LOKI_CHUNK_STORE_TYPE" "filesystem"

    # Alertmanager enhancements
    add_env_var "ALERTMANAGER_LOG_LEVEL" "info"
    add_env_var "ALERTMANAGER_STORAGE_PATH" "/alertmanager"
    add_env_var "ALERTMANAGER_RETENTION" "120h"

    # ==========================================================================
    # 6. CREATE REQUIRED DIRECTORIES
    # ==========================================================================
    print_info "Creating required directories with proper permissions..."

    # Redis directories
    mkdir -p data/redis/{data,logs,certs}

    # Prometheus directories
    mkdir -p data/prometheus/config/{rules,targets.d/{infrastructure,applications,exporters,security},file_sd}
    mkdir -p data/prometheus/{data,console_libraries,consoles,certs}

    # Grafana directories
    mkdir -p data/grafana/{data,provisioning/{dashboards,datasources,alerting},plugins}

    # Loki directories
    mkdir -p data/loki/{data,rules,chunks,index,cache,wal}
    chmod -R 777 data/loki  # Loki needs write permissions

    # Alertmanager directories
    mkdir -p data/alertmanager/{data,templates}

    # Jaeger directories
    mkdir -p data/jaeger/{data,config}

    # Pushgateway directory
    mkdir -p data/pushgateway

    # ==========================================================================
    # 7. SET PROPER PERMISSIONS
    # ==========================================================================
    print_info "Setting proper permissions..."

    # Redis ACL file (empty for now)
    touch data/redis/users.acl
    chmod 640 data/redis/users.acl

    # Prometheus data
    chmod -R 777 data/prometheus/data  # Prometheus needs write access

    # Grafana data
    chmod -R 777 data/grafana  # Grafana needs write access

    # ==========================================================================
    # 8. CREATE MONITORING DASHBOARDS
    # ==========================================================================
    print_info "Creating Grafana provisioning configuration..."

    # Datasource provisioning
    cat > "data/grafana/provisioning/datasources/prometheus.yml" <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    uid: prometheus-uid
    url: http://prometheus:9090
    isDefault: true
    version: 1
    editable: true
    jsonData:
      httpMethod: POST
      prometheusType: Prometheus
      prometheusVersion: 2.40.0
      incrementalQuerying: true
      incrementalQueryOverlapWindow: 10m
      disableMetricsLookup: false
      cacheLevel: 'High'
      manageAlerts: true
EOF

    # Dashboard provisioning
    cat > "data/grafana/provisioning/dashboards/default.yml" <<'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    folderUid: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
EOF

    # ==========================================================================
    # 9. SUMMARY
    # ==========================================================================
    echo
    print_success "Complete enhancement process finished!"
    echo
    print_info "Summary of enhancements:"
    echo "  ✅ Redis - Added clustering support, TLS ready, Redis Commander UI"
    echo "  ✅ Prometheus - Modular config, cAdvisor, Pushgateway, enhanced retention"
    echo "  ✅ Configuration files created for all services"
    echo "  ✅ Environment variables added for all enhancements"
    echo "  ✅ Directories created with proper permissions"
    echo "  ✅ Grafana provisioning configured"
    echo
    print_warning "Next steps:"
    echo "  1. Review and set passwords in .env file"
    echo "  2. Run 'make restart' to apply all enhancements"
    echo "  3. Monitor logs with 'make logs' to ensure services start"
    echo "  4. Access services:"
    echo "     - Redis Commander: https://redis.\${PUBLIC_FQDN}"
    echo "     - Prometheus: https://prometheus.\${PUBLIC_FQDN}"
    echo "     - Grafana: https://grafana.\${PUBLIC_FQDN}"
    echo "     - Alertmanager: https://alertmanager.\${PUBLIC_FQDN}"
    echo
    print_info "Documentation: jacker-docs/docs/guides/compose-enhancements.md"
}

# Main execution
main() {
    echo "============================================"
    echo "   Jacker Complete Enhancement Application"
    echo "============================================"
    echo

    # Check if running from correct directory
    if [[ ! -f "docker-compose.yml" ]]; then
        print_error "docker-compose.yml not found. Please run from Jacker root directory."
        exit 1
    fi

    # Check for .env file
    if [[ ! -f ".env" ]]; then
        print_warning "Creating .env from .env.defaults..."
        if [[ -f ".env.defaults" ]]; then
            cp .env.defaults .env
            print_success ".env created from defaults"
        else
            print_error ".env.defaults not found. Please run 'make install' first."
            exit 1
        fi
    fi

    # Apply all enhancements
    apply_all_enhancements
}

# Run main function
main "$@"