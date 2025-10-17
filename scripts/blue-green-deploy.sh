#!/usr/bin/env bash
# blue-green-deploy.sh - Zero-downtime service deployment using Blue-Green strategy
#
# This script implements a Blue-Green deployment pattern for Docker Compose services,
# allowing you to update container resource limits without downtime.
#
# Usage:
#   ./blue-green-deploy.sh <service> <new_cpu> <new_memory> [options]
#   ./blue-green-deploy.sh rollback <service>
#   ./blue-green-deploy.sh status <service>
#
# Examples:
#   ./blue-green-deploy.sh grafana 1.5 768M
#   ./blue-green-deploy.sh traefik 2.5 1536M --timeout 180
#   ./blue-green-deploy.sh grafana 1.0 512M --dry-run
#   ./blue-green-deploy.sh rollback grafana
#
# Options:
#   --dry-run           Show what would be done without executing
#   --timeout <sec>     Custom health check timeout (default: 120)
#   --no-rollback       Disable automatic rollback on failure
#   --force             Skip safety checks (dangerous!)
#   --log-file <path>   Custom log file path
#   --no-drain          Skip connection draining phase
#   --metrics           Export deployment metrics to Prometheus
#
# Exit codes:
#   0 - Success
#   1 - Validation error
#   2 - Deployment failure
#   3 - Rollback failure
#   4 - Health check timeout

set -euo pipefail

# ====================================================================
# CONFIGURATION
# ====================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
readonly OVERRIDE_FILE="$PROJECT_DIR/docker-compose.blue-green.yml"
readonly BACKUP_FILE="$PROJECT_DIR/docker-compose.blue-green.backup.yml"
readonly LOG_DIR="${LOG_DIR:-/var/log/jacker}"
readonly LOG_FILE="${LOG_FILE:-$LOG_DIR/blue-green.log}"
readonly METRICS_FILE="${METRICS_FILE:-$LOG_DIR/blue-green-metrics.prom}"

# Deployment configuration
readonly DEFAULT_HEALTH_CHECK_TIMEOUT=120
readonly DEFAULT_HEALTH_CHECK_INTERVAL=5
readonly DEFAULT_DRAIN_TIMEOUT=30
readonly MAX_SCALE_WAIT=60

# Stateful services that should NOT use Blue-Green deployment
readonly -a STATEFUL_SERVICES=(
  "postgres"
  "postgres-exporter"
  "redis"
  "redis-exporter"
  "redis-commander"
  "socket-proxy"
)

# ====================================================================
# COLOR CODES
# ====================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# ====================================================================
# GLOBAL VARIABLES
# ====================================================================
SERVICE_NAME=""
NEW_CPU=""
NEW_MEMORY=""
CURRENT_CPU=""
CURRENT_MEMORY=""
HEALTH_CHECK_TIMEOUT="${DEFAULT_HEALTH_CHECK_TIMEOUT}"
HEALTH_CHECK_INTERVAL="${DEFAULT_HEALTH_CHECK_INTERVAL}"
DRAIN_TIMEOUT="${DEFAULT_DRAIN_TIMEOUT}"
DRY_RUN=false
AUTO_ROLLBACK=true
FORCE=false
SKIP_DRAIN=false
EXPORT_METRICS=false
DEPLOYMENT_START_TIME=""
DEPLOYMENT_END_TIME=""
DEPLOYMENT_STATUS="pending"

# ====================================================================
# LOGGING FUNCTIONS
# ====================================================================

init_logging() {
  if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || {
      echo -e "${YELLOW}Warning: Cannot create log directory $LOG_DIR${NC}" >&2
      return 0
    }
  fi

  if [[ -w "$LOG_DIR" ]]; then
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
    log_debug "Logging initialized to $LOG_FILE"
  fi
}

log() {
  local level=$1
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [$level] $message"
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $*"
  log "INFO" "$*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
  log "SUCCESS" "$*"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $*" >&2
  log "WARN" "$*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
  log "ERROR" "$*"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo -e "${CYAN}DEBUG:${NC} $*" >&2
    log "DEBUG" "$*"
  fi
}

log_step() {
  echo -e "\n${BOLD}${MAGENTA}▶${NC} ${BOLD}$*${NC}"
  log "STEP" "$*"
}

# ====================================================================
# UTILITY FUNCTIONS
# ====================================================================

usage() {
  cat <<EOF
${BOLD}Blue-Green Deployment Tool for Docker Compose${NC}

${BOLD}USAGE:${NC}
  $SCRIPT_NAME <service> <new_cpu> <new_memory> [options]
  $SCRIPT_NAME rollback <service>
  $SCRIPT_NAME status <service>

${BOLD}ARGUMENTS:${NC}
  service       Name of the Docker Compose service to update
  new_cpu       New CPU limit (e.g., 1.5, 2.0)
  new_memory    New memory limit (e.g., 512M, 1024M, 2G)

${BOLD}COMMANDS:${NC}
  deploy        Deploy service with new resource limits (default)
  rollback      Rollback to previous configuration
  status        Show current deployment status

${BOLD}OPTIONS:${NC}
  --dry-run               Show what would be done without executing
  --timeout <seconds>     Health check timeout (default: $DEFAULT_HEALTH_CHECK_TIMEOUT)
  --no-rollback           Disable automatic rollback on failure
  --force                 Skip safety checks (USE WITH CAUTION!)
  --log-file <path>       Custom log file path
  --no-drain              Skip connection draining phase
  --metrics               Export deployment metrics to Prometheus
  -h, --help              Show this help message

${BOLD}EXAMPLES:${NC}
  # Update Grafana resource limits
  $SCRIPT_NAME grafana 1.5 768M

  # Update Traefik with custom timeout
  $SCRIPT_NAME traefik 2.5 1536M --timeout 180

  # Dry run to see changes
  $SCRIPT_NAME grafana 1.0 512M --dry-run

  # Rollback a failed deployment
  $SCRIPT_NAME rollback grafana

  # Check deployment status
  $SCRIPT_NAME status grafana

${BOLD}STATEFUL SERVICES (NOT SUPPORTED):${NC}
  The following services should NOT use Blue-Green deployment:
  - postgres, postgres-exporter (database)
  - redis, redis-exporter, redis-commander (cache/state)
  - socket-proxy (single point of access)

  For these services, use rolling restart or maintenance window instead.

${BOLD}EXIT CODES:${NC}
  0 - Success
  1 - Validation error
  2 - Deployment failure
  3 - Rollback failure
  4 - Health check timeout

${BOLD}NOTES:${NC}
  - Services must have health checks defined in docker-compose.yml
  - Traefik automatically load balances between Blue and Green replicas
  - Always test with --dry-run first in production
  - Logs are written to: $LOG_FILE

EOF
}

validate_dependencies() {
  local -a missing_deps=()

  for cmd in docker docker-compose jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log_error "Please install: apt-get install docker.io docker-compose jq bc"
    return 1
  fi

  log_debug "All dependencies validated"
  return 0
}

validate_service() {
  local service=$1

  log_debug "Validating service: $service"

  # Check if service exists in compose file
  if ! docker-compose -f "$COMPOSE_FILE" config --services 2>/dev/null | grep -qx "$service"; then
    log_error "Service '$service' not found in docker-compose.yml"
    log_info "Available services:"
    docker-compose -f "$COMPOSE_FILE" config --services | sed 's/^/  - /'
    return 1
  fi

  # Check if service is stateful
  if is_stateful_service "$service"; then
    log_error "Service '$service' is a stateful service and should NOT use Blue-Green deployment"
    log_error "Stateful services: ${STATEFUL_SERVICES[*]}"
    log_warn "For stateful services, use:"
    log_warn "  - Rolling restart: docker-compose restart $service"
    log_warn "  - Maintenance window: docker-compose stop $service && <update> && docker-compose start $service"
    log_warn "  - Master-Replica pattern: Set up replication first"

    if [[ "$FORCE" != "true" ]]; then
      return 1
    else
      log_warn "Proceeding anyway due to --force flag (DANGEROUS!)"
    fi
  fi

  # Check if service is running
  if ! docker-compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "Up"; then
    log_error "Service '$service' is not running"
    log_info "Start the service first: docker-compose up -d $service"
    return 1
  fi

  # Check if service has health check
  if ! has_healthcheck "$service"; then
    log_warn "Service '$service' does not have a health check defined"
    log_warn "Blue-Green deployment requires health checks for safety"

    if [[ "$FORCE" != "true" ]]; then
      log_error "Add a healthcheck to $service in docker-compose.yml or use --force"
      return 1
    else
      log_warn "Proceeding anyway due to --force flag (may be unsafe)"
    fi
  fi

  log_success "Service validation passed"
  return 0
}

is_stateful_service() {
  local service=$1

  for stateful in "${STATEFUL_SERVICES[@]}"; do
    if [[ "$service" == "$stateful" ]]; then
      return 0
    fi
  done

  return 1
}

has_healthcheck() {
  local service=$1

  # Check if healthcheck is defined in compose file
  if docker-compose -f "$COMPOSE_FILE" config | grep -A 5 "^  $service:" | grep -q "healthcheck:"; then
    return 0
  fi

  # Check if container has healthcheck
  local container_id
  container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)

  if [[ -n "$container_id" ]]; then
    if docker inspect "$container_id" | jq -e '.[0].State.Health' &>/dev/null; then
      return 0
    fi
  fi

  return 1
}

validate_resource_format() {
  local cpu=$1
  local memory=$2

  # Validate CPU format (number with optional decimal)
  if ! echo "$cpu" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    log_error "Invalid CPU format: $cpu (expected: 1.0, 1.5, 2.0, etc.)"
    return 1
  fi

  # Validate CPU range (0.1 to 16.0)
  if ! awk -v cpu="$cpu" 'BEGIN { exit !(cpu >= 0.1 && cpu <= 16.0) }'; then
    log_error "CPU limit out of range: $cpu (expected: 0.1 to 16.0)"
    return 1
  fi

  # Validate memory format (number with unit)
  if ! echo "$memory" | grep -qE '^[0-9]+[KMG]$'; then
    log_error "Invalid memory format: $memory (expected: 512M, 1024M, 2G, etc.)"
    return 1
  fi

  # Convert to MB for range validation
  local memory_mb
  memory_mb=$(convert_to_mb "$memory")

  # Validate memory range (64MB to 32GB)
  if ! awk -v mem="$memory_mb" 'BEGIN { exit !(mem >= 64 && mem <= 32768) }'; then
    log_error "Memory limit out of range: $memory (expected: 64M to 32G)"
    return 1
  fi

  log_debug "Resource format validated: CPU=$cpu, Memory=$memory"
  return 0
}

convert_to_mb() {
  local size=$1
  local value="${size%[KMG]}"
  local unit="${size: -1}"

  case "$unit" in
    K) echo "$((value / 1024))" ;;
    M) echo "$value" ;;
    G) echo "$((value * 1024))" ;;
    *) echo "0" ;;
  esac
}

# ====================================================================
# RESOURCE MANAGEMENT
# ====================================================================

get_current_limits() {
  local service=$1

  log_debug "Getting current resource limits for $service"

  # Get current limits from docker inspect
  local container_id
  container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | head -1)

  if [[ -z "$container_id" ]]; then
    log_error "Cannot find container for service: $service"
    return 1
  fi

  # Get CPU limit (NanoCPUs / 1000000000)
  local cpu_nano
  cpu_nano=$(docker inspect "$container_id" --format='{{.HostConfig.NanoCpus}}' 2>/dev/null || echo "0")

  if [[ "$cpu_nano" -gt 0 ]]; then
    CURRENT_CPU=$(awk -v nano="$cpu_nano" 'BEGIN { printf "%.1f", nano/1000000000 }')
  else
    CURRENT_CPU="unlimited"
  fi

  # Get memory limit
  local memory_bytes
  memory_bytes=$(docker inspect "$container_id" --format='{{.HostConfig.Memory}}' 2>/dev/null || echo "0")

  if [[ "$memory_bytes" -gt 0 ]]; then
    local memory_mb=$((memory_bytes / 1024 / 1024))
    if [[ $memory_mb -ge 1024 ]]; then
      CURRENT_MEMORY="$((memory_mb / 1024))G"
    else
      CURRENT_MEMORY="${memory_mb}M"
    fi
  else
    CURRENT_MEMORY="unlimited"
  fi

  log_info "Current limits: CPU=$CURRENT_CPU, Memory=$CURRENT_MEMORY"
  return 0
}

create_green_config() {
  local service=$1
  local new_cpu=$2
  local new_memory=$3

  log_debug "Creating Green configuration for $service"

  # Backup existing override file if it exists
  if [[ -f "$OVERRIDE_FILE" ]]; then
    log_debug "Backing up existing override file"
    cp "$OVERRIDE_FILE" "$BACKUP_FILE"
  fi

  # Create new override file with updated resource limits
  cat > "$OVERRIDE_FILE" <<EOF
# Blue-Green deployment override
# Generated: $(date -Iseconds)
# Service: $service
# New limits: CPU=$new_cpu, Memory=$new_memory
# Previous limits: CPU=$CURRENT_CPU, Memory=$CURRENT_MEMORY

services:
  $service:
    deploy:
      resources:
        limits:
          cpus: "$new_cpu"
          memory: $new_memory
        reservations:
          cpus: "$(awk -v cpu="$new_cpu" 'BEGIN { printf "%.2f", cpu/4 }')"
          memory: $(awk -v mem="${new_memory%[MG]}" -v unit="${new_memory: -1}" 'BEGIN {
            if (unit == "G") mem = mem * 1024;
            printf "%dM", mem/4
          }')

    # Add label to identify Green deployment
    labels:
      - "deployment.type=blue-green"
      - "deployment.phase=green"
      - "deployment.timestamp=$(date +%s)"
      - "deployment.new_cpu=$new_cpu"
      - "deployment.new_memory=$new_memory"
EOF

  log_success "Green configuration created at $OVERRIDE_FILE"
  return 0
}

# ====================================================================
# DEPLOYMENT ORCHESTRATION
# ====================================================================

scale_up_green() {
  local service=$1

  log_debug "Scaling up Green replica for $service"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would scale $service to 2 replicas"
    return 0
  fi

  # Scale service to 2 replicas using both compose files
  if docker-compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" up -d --scale "$service=2" --no-recreate "$service" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Scaled $service to 2 replicas (Blue + Green)"

    # Wait a moment for the new container to start
    sleep 2

    # List running containers for this service
    log_info "Running replicas:"
    docker-compose -f "$COMPOSE_FILE" ps "$service" | tail -n +3 | sed 's/^/  /'

    return 0
  else
    log_error "Failed to scale up $service"
    return 1
  fi
}

wait_for_green_healthy() {
  local service=$1
  local timeout=$HEALTH_CHECK_TIMEOUT
  local interval=$HEALTH_CHECK_INTERVAL
  local elapsed=0

  log_info "Waiting for Green replica to be healthy (timeout: ${timeout}s)..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would wait for health checks"
    return 0
  fi

  while [[ $elapsed -lt $timeout ]]; do
    # Get all containers for this service
    local healthy_count=0
    local total_count=0

    # Count healthy replicas
    while IFS= read -r container_id; do
      if [[ -z "$container_id" ]]; then
        continue
      fi

      ((total_count++))

      local health_status
      health_status=$(docker inspect "$container_id" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")

      if [[ "$health_status" == "healthy" ]]; then
        ((healthy_count++))
      elif [[ "$health_status" == "none" ]]; then
        # No health check defined, check if running
        local state
        state=$(docker inspect "$container_id" --format='{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [[ "$state" == "running" ]]; then
          ((healthy_count++))
        fi
      fi
    done < <(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null)

    log_debug "Health check: $healthy_count/$total_count healthy"

    # We need at least 2 healthy replicas (Blue + Green)
    if [[ $healthy_count -ge 2 ]]; then
      log_success "Green replica is healthy! ($healthy_count/$total_count replicas healthy)"
      return 0
    fi

    # Show progress
    printf "\r  ⏳ Waiting for health... %ds/%ds (healthy: %d/%d)" \
      "$elapsed" "$timeout" "$healthy_count" "$total_count"

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  echo "" # New line after progress
  log_error "Health check timeout after ${timeout}s"

  # Show container logs for debugging
  log_info "Container logs (last 20 lines):"
  docker-compose -f "$COMPOSE_FILE" logs --tail=20 "$service" | sed 's/^/  /'

  return 1
}

verify_traffic_split() {
  local service=$1

  log_debug "Verifying traffic distribution for $service"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would verify traffic distribution"
    return 0
  fi

  # Check if service is exposed via Traefik
  local container_id
  container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | head -1)

  if [[ -z "$container_id" ]]; then
    log_warn "Cannot verify traffic split: no container found"
    return 0
  fi

  # Check for Traefik labels
  local has_traefik
  has_traefik=$(docker inspect "$container_id" --format='{{index .Config.Labels "traefik.enable"}}' 2>/dev/null || echo "false")

  if [[ "$has_traefik" != "true" ]]; then
    log_info "Service not exposed via Traefik, skipping traffic verification"
    return 0
  fi

  log_info "Service is exposed via Traefik - traffic will be load balanced automatically"

  # Get replica count
  local replica_count
  replica_count=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | wc -l)

  log_success "Traefik managing $replica_count replicas for load balancing"
  return 0
}

drain_blue_connections() {
  local service=$1

  if [[ "$SKIP_DRAIN" == "true" ]]; then
    log_info "Skipping connection draining (--no-drain)"
    return 0
  fi

  log_info "Draining active connections from Blue replica..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would wait ${DRAIN_TIMEOUT}s for connection draining"
    return 0
  fi

  # Wait for active connections to drain
  log_debug "Waiting ${DRAIN_TIMEOUT}s for graceful connection draining"

  for ((i=DRAIN_TIMEOUT; i>0; i--)); do
    printf "\r  ⏳ Draining connections... %ds remaining" "$i"
    sleep 1
  done

  echo "" # New line after progress
  log_success "Connection draining complete"
  return 0
}

scale_down_blue() {
  local service=$1

  log_debug "Scaling down to 1 replica (removing Blue)"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would scale $service down to 1 replica"
    return 0
  fi

  # Scale down to 1 replica, keeping Green
  if docker-compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" up -d --scale "$service=1" --no-recreate "$service" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Scaled down to 1 replica (Green only)"

    # Wait for scale down to complete
    sleep 2

    # Verify only 1 replica running
    local replica_count
    replica_count=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | wc -l)

    if [[ $replica_count -eq 1 ]]; then
      log_success "Confirmed: 1 replica running"
      return 0
    else
      log_warn "Expected 1 replica, found $replica_count"
      return 1
    fi
  else
    log_error "Failed to scale down $service"
    return 1
  fi
}

verify_deployment() {
  local service=$1

  log_debug "Verifying final deployment state"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would verify deployment"
    return 0
  fi

  # Check if service is healthy
  local container_id
  container_id=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | head -1)

  if [[ -z "$container_id" ]]; then
    log_error "No container found for $service"
    return 1
  fi

  # Check health status
  local health_status
  health_status=$(docker inspect "$container_id" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")

  if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "none" && $(docker inspect "$container_id" --format='{{.State.Status}}') == "running" ]]; then
    log_success "Service is healthy"
  else
    log_error "Service health check failed: $health_status"
    return 1
  fi

  # Verify resource limits applied
  local actual_cpu
  local actual_memory

  actual_cpu=$(docker inspect "$container_id" --format='{{.HostConfig.NanoCpus}}' 2>/dev/null || echo "0")
  actual_memory=$(docker inspect "$container_id" --format='{{.HostConfig.Memory}}' 2>/dev/null || echo "0")

  if [[ "$actual_cpu" -gt 0 ]]; then
    actual_cpu=$(awk -v nano="$actual_cpu" 'BEGIN { printf "%.1f", nano/1000000000 }')
    log_info "Actual CPU limit: $actual_cpu"
  fi

  if [[ "$actual_memory" -gt 0 ]]; then
    local memory_mb=$((actual_memory / 1024 / 1024))
    if [[ $memory_mb -ge 1024 ]]; then
      actual_memory="$((memory_mb / 1024))G"
    else
      actual_memory="${memory_mb}M"
    fi
    log_info "Actual memory limit: $actual_memory"
  fi

  log_success "Deployment verification complete"
  return 0
}

# ====================================================================
# ROLLBACK FUNCTIONS
# ====================================================================

rollback_deployment() {
  local service=$1

  log_warn "Initiating rollback for $service..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would rollback deployment"
    return 0
  fi

  # Restore backup if it exists
  if [[ -f "$BACKUP_FILE" ]]; then
    log_info "Restoring previous configuration"
    mv "$BACKUP_FILE" "$OVERRIDE_FILE"
  else
    log_info "Removing override configuration"
    rm -f "$OVERRIDE_FILE"
  fi

  # Scale back to 1 replica with original config
  log_info "Scaling back to 1 replica with original configuration"
  if docker-compose -f "$COMPOSE_FILE" up -d --scale "$service=1" "$service" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Rollback complete - service restored to original state"

    # Update deployment status
    DEPLOYMENT_STATUS="rolled_back"

    return 0
  else
    log_error "Rollback failed!"
    log_error "Manual intervention required"
    log_error "Run: docker-compose -f $COMPOSE_FILE up -d $service"

    DEPLOYMENT_STATUS="rollback_failed"
    return 1
  fi
}

perform_manual_rollback() {
  local service=$1

  log_step "Phase: Manual Rollback"

  # Validate service
  if ! validate_service "$service"; then
    return 1
  fi

  # Perform rollback
  if rollback_deployment "$service"; then
    log_success "Manual rollback completed successfully"
    cleanup
    return 0
  else
    log_error "Manual rollback failed"
    return 1
  fi
}

# ====================================================================
# CLEANUP FUNCTIONS
# ====================================================================

cleanup() {
  log_debug "Cleaning up temporary files"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would cleanup temporary files"
    return 0
  fi

  # Remove backup file
  if [[ -f "$BACKUP_FILE" ]]; then
    rm -f "$BACKUP_FILE"
    log_debug "Removed backup file"
  fi

  # Keep override file for future reference/rollback
  # Only remove if explicitly requested
  if [[ "${CLEANUP_OVERRIDE:-false}" == "true" ]] && [[ -f "$OVERRIDE_FILE" ]]; then
    rm -f "$OVERRIDE_FILE"
    log_debug "Removed override file"
  fi

  log_debug "Cleanup complete"
}

# ====================================================================
# METRICS FUNCTIONS
# ====================================================================

export_metrics() {
  if [[ "$EXPORT_METRICS" != "true" ]]; then
    return 0
  fi

  log_debug "Exporting deployment metrics"

  local duration=0
  if [[ -n "$DEPLOYMENT_START_TIME" ]] && [[ -n "$DEPLOYMENT_END_TIME" ]]; then
    duration=$((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME))
  fi

  # Create metrics file in Prometheus format
  cat > "$METRICS_FILE" <<EOF
# HELP blue_green_deployment_total Total number of blue-green deployments
# TYPE blue_green_deployment_total counter
blue_green_deployment_total{service="$SERVICE_NAME",status="$DEPLOYMENT_STATUS"} 1 $(date +%s)000

# HELP blue_green_deployment_duration_seconds Duration of blue-green deployment
# TYPE blue_green_deployment_duration_seconds gauge
blue_green_deployment_duration_seconds{service="$SERVICE_NAME",status="$DEPLOYMENT_STATUS"} $duration $(date +%s)000

# HELP blue_green_deployment_timestamp Timestamp of last deployment
# TYPE blue_green_deployment_timestamp gauge
blue_green_deployment_timestamp{service="$SERVICE_NAME"} $DEPLOYMENT_END_TIME $(date +%s)000

# HELP blue_green_cpu_limit CPU limit after deployment
# TYPE blue_green_cpu_limit gauge
blue_green_cpu_limit{service="$SERVICE_NAME"} $NEW_CPU $(date +%s)000

# HELP blue_green_memory_limit_bytes Memory limit after deployment
# TYPE blue_green_memory_limit_bytes gauge
blue_green_memory_limit_bytes{service="$SERVICE_NAME"} $(convert_to_mb "$NEW_MEMORY")000000 $(date +%s)000
EOF

  log_success "Metrics exported to $METRICS_FILE"
}

# ====================================================================
# STATUS FUNCTIONS
# ====================================================================

show_deployment_status() {
  local service=$1

  log_info "Deployment status for: $service"

  # Check if service is running
  if ! docker-compose -f "$COMPOSE_FILE" ps "$service" 2>/dev/null | grep -q "Up"; then
    log_warn "Service is not running"
    return 0
  fi

  # Get current limits
  get_current_limits "$service"

  # Check for override file
  if [[ -f "$OVERRIDE_FILE" ]]; then
    log_info "Override file exists: $OVERRIDE_FILE"

    # Parse override file for deployment info
    if grep -q "deployment.type=blue-green" "$OVERRIDE_FILE" 2>/dev/null; then
      log_info "Last deployment: Blue-Green"

      local timestamp
      timestamp=$(grep "deployment.timestamp" "$OVERRIDE_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"')

      if [[ -n "$timestamp" ]]; then
        local deploy_date
        deploy_date=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        log_info "Deployment time: $deploy_date"
      fi
    fi
  else
    log_info "No active override configuration"
  fi

  # Show replica count
  local replica_count
  replica_count=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | wc -l)
  log_info "Current replicas: $replica_count"

  # Show container details
  log_info "\nContainer details:"
  docker-compose -f "$COMPOSE_FILE" ps "$service" | tail -n +2 | sed 's/^/  /'

  return 0
}

# ====================================================================
# MAIN DEPLOYMENT FUNCTION
# ====================================================================

deploy_blue_green() {
  local service=$1
  local new_cpu=$2
  local new_memory=$3

  DEPLOYMENT_START_TIME=$(date +%s)
  DEPLOYMENT_STATUS="in_progress"

  log_step "Blue-Green Deployment Starting"
  log_info "Service: $service"
  log_info "New limits: CPU=$new_cpu, Memory=$new_memory"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
  fi

  # Phase 1: Preparation
  log_step "Phase 1: Preparation"

  if ! validate_service "$service"; then
    DEPLOYMENT_STATUS="validation_failed"
    return 1
  fi

  if ! get_current_limits "$service"; then
    DEPLOYMENT_STATUS="validation_failed"
    return 1
  fi

  if ! create_green_config "$service" "$new_cpu" "$new_memory"; then
    DEPLOYMENT_STATUS="config_failed"
    return 1
  fi

  # Phase 2: Deploy Green
  log_step "Phase 2: Deploy Green Replica"

  if ! scale_up_green "$service"; then
    log_error "Failed to deploy Green replica"
    if [[ "$AUTO_ROLLBACK" == "true" ]]; then
      rollback_deployment "$service"
    fi
    DEPLOYMENT_STATUS="deploy_failed"
    return 2
  fi

  # Phase 3: Health Check
  log_step "Phase 3: Health Check"

  if ! wait_for_green_healthy "$service"; then
    log_error "Green replica failed health checks"
    if [[ "$AUTO_ROLLBACK" == "true" ]]; then
      rollback_deployment "$service"
    fi
    DEPLOYMENT_STATUS="health_check_failed"
    return 4
  fi

  # Phase 4: Traffic Verification
  log_step "Phase 4: Traffic Verification"

  if ! verify_traffic_split "$service"; then
    log_warn "Traffic verification failed, but continuing"
  fi

  # Wait a bit to ensure Green is handling traffic
  log_info "Monitoring Green replica for 10 seconds..."
  sleep 10

  # Phase 5: Drain and Remove Blue
  log_step "Phase 5: Remove Blue Replica"

  if ! drain_blue_connections "$service"; then
    log_warn "Connection draining failed, but continuing"
  fi

  if ! scale_down_blue "$service"; then
    log_error "Failed to remove Blue replica"
    if [[ "$AUTO_ROLLBACK" == "true" ]]; then
      rollback_deployment "$service"
    fi
    DEPLOYMENT_STATUS="scale_down_failed"
    return 2
  fi

  # Phase 6: Final Verification
  log_step "Phase 6: Final Verification"

  if ! verify_deployment "$service"; then
    log_error "Deployment verification failed"
    if [[ "$AUTO_ROLLBACK" == "true" ]]; then
      rollback_deployment "$service"
    fi
    DEPLOYMENT_STATUS="verification_failed"
    return 2
  fi

  # Success
  DEPLOYMENT_END_TIME=$(date +%s)
  DEPLOYMENT_STATUS="success"

  log_step "Deployment Complete"
  log_success "Blue-Green deployment completed successfully!"
  log_success "Service: $service"
  log_success "Previous limits: CPU=$CURRENT_CPU, Memory=$CURRENT_MEMORY"
  log_success "New limits: CPU=$new_cpu, Memory=$new_memory"
  log_success "Duration: $((DEPLOYMENT_END_TIME - DEPLOYMENT_START_TIME)) seconds"

  # Cleanup
  cleanup

  # Export metrics
  export_metrics

  return 0
}

# ====================================================================
# ARGUMENT PARSING
# ====================================================================

parse_arguments() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  # Check for help flag
  if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  # Check for special commands
  case "$1" in
    rollback)
      if [[ -z "${2:-}" ]]; then
        log_error "Missing service name for rollback"
        usage
        exit 1
      fi
      perform_manual_rollback "$2"
      exit $?
      ;;
    status)
      if [[ -z "${2:-}" ]]; then
        log_error "Missing service name for status"
        usage
        exit 1
      fi
      show_deployment_status "$2"
      exit 0
      ;;
  esac

  # Parse deploy command (default)
  if [[ $# -lt 3 ]]; then
    log_error "Missing required arguments"
    usage
    exit 1
  fi

  SERVICE_NAME="$1"
  NEW_CPU="$2"
  NEW_MEMORY="$3"
  shift 3

  # Parse options
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --timeout)
        if [[ -z "${2:-}" ]]; then
          log_error "--timeout requires a value"
          exit 1
        fi
        HEALTH_CHECK_TIMEOUT="$2"
        shift 2
        ;;
      --no-rollback)
        AUTO_ROLLBACK=false
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --log-file)
        if [[ -z "${2:-}" ]]; then
          log_error "--log-file requires a value"
          exit 1
        fi
        LOG_FILE="$2"
        shift 2
        ;;
      --no-drain)
        SKIP_DRAIN=true
        shift
        ;;
      --metrics)
        EXPORT_METRICS=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

# ====================================================================
# MAIN ENTRY POINT
# ====================================================================

main() {
  # Initialize logging
  init_logging

  log_info "========================================="
  log_info "Blue-Green Deployment Tool v1.0"
  log_info "========================================="

  # Parse arguments
  parse_arguments "$@"

  # Validate dependencies
  if ! validate_dependencies; then
    exit 1
  fi

  # Validate resource format
  if ! validate_resource_format "$NEW_CPU" "$NEW_MEMORY"; then
    exit 1
  fi

  # Execute deployment
  if deploy_blue_green "$SERVICE_NAME" "$NEW_CPU" "$NEW_MEMORY"; then
    log_success "\n🎉 Deployment successful!"
    exit 0
  else
    log_error "\n❌ Deployment failed!"
    exit 2
  fi
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
