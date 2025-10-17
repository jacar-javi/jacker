#!/bin/bash
# ====================================================================
# Resource Manager Entrypoint Script
# ====================================================================
# Ensures Prometheus is ready before starting monitoring

set -e

# ====================================================================
# CONFIGURATION
# ====================================================================
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus:9090}"
MAX_RETRIES="${PROMETHEUS_MAX_RETRIES:-30}"
RETRY_INTERVAL="${PROMETHEUS_RETRY_INTERVAL:-5}"

# ====================================================================
# LOGGING FUNCTIONS
# ====================================================================
log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1"
}

# ====================================================================
# STARTUP CHECKS
# ====================================================================
log_info "Resource Manager Starting..."
log_info "Configuration:"
log_info "  - Prometheus URL: $PROMETHEUS_URL"
log_info "  - Check Interval: ${CHECK_INTERVAL:-300} seconds"
log_info "  - CPU High Threshold: ${CPU_HIGH_THRESHOLD:-0.8}"
log_info "  - Memory High Threshold: ${MEMORY_HIGH_THRESHOLD:-0.8}"
log_info "  - Blue-Green Enabled: ${BLUE_GREEN_ENABLED:-true}"

# ====================================================================
# WAIT FOR DEPENDENCIES
# ====================================================================
log_info "Waiting for Prometheus to be ready..."

retries=0
while [ $retries -lt $MAX_RETRIES ]; do
    if curl -sf "${PROMETHEUS_URL}/-/ready" > /dev/null 2>&1; then
        log_info "Prometheus is ready!"
        break
    fi

    retries=$((retries + 1))
    if [ $retries -eq $MAX_RETRIES ]; then
        log_error "Prometheus is not ready after $MAX_RETRIES attempts"
        log_error "Please check Prometheus service status"
        exit 1
    fi

    log_info "Waiting for Prometheus... (attempt $retries/$MAX_RETRIES)"
    sleep $RETRY_INTERVAL
done

# Check Docker connectivity
log_info "Checking Docker connectivity..."
if ! curl -sf "${DOCKER_HOST:-tcp://docker-socket-proxy:2375}/version" > /dev/null 2>&1; then
    log_warn "Docker socket proxy may not be available"
    log_warn "Resource adjustments may fail"
fi

# Validate configuration file
if [ ! -f "/config/config.yml" ]; then
    log_error "Configuration file not found at /config/config.yml"
    exit 1
fi

log_info "Configuration file validated"

# Create log directory if it doesn't exist
LOG_DIR=$(dirname "${LOG_FILE:-/logs/resource-manager.log}")
mkdir -p "$LOG_DIR"
log_info "Log directory: $LOG_DIR"

# ====================================================================
# START APPLICATION
# ====================================================================
log_info "Starting Resource Manager monitoring..."
log_info "Press Ctrl+C to stop"

# Execute the main Python script
exec python /app/manager.py "$@"
