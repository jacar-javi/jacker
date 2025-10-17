#!/usr/bin/env bash
# ====================================================================
# Trivy Container Scanning Script
# ====================================================================
# Scans all running Docker containers for vulnerabilities, secrets,
# and misconfigurations, then sends alerts to Alertmanager
# ====================================================================

set -euo pipefail

# ====================================================================
# Configuration
# ====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables if .env exists
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env"
fi

# Trivy configuration
TRIVY_CONTAINER="${TRIVY_CONTAINER:-trivy}"
TRIVY_SEVERITY="${TRIVY_SEVERITY:-CRITICAL,HIGH,MEDIUM}"
TRIVY_FORMAT="${TRIVY_FORMAT:-json}"
TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-10m}"
TRIVY_REPORTS_DIR="${DATADIR:-$PROJECT_ROOT/data}/trivy/reports"
TRIVY_CONFIG="${CONFIGDIR:-$PROJECT_ROOT/config}/trivy/trivy.yaml"

# Alertmanager configuration
ALERTMANAGER_URL="${ALERTMANAGER_URL:-http://localhost:9093}"
ALERTMANAGER_ENDPOINT="${ALERTMANAGER_URL}/api/v2/alerts"

# Alert thresholds
CRITICAL_THRESHOLD="${TRIVY_CRITICAL_THRESHOLD:-1}"
HIGH_THRESHOLD="${TRIVY_HIGH_THRESHOLD:-5}"
SECRETS_THRESHOLD="${TRIVY_SECRETS_THRESHOLD:-1}"

# Excluded containers (regex pattern)
EXCLUDE_PATTERN="${TRIVY_EXCLUDE_PATTERN:-^(trivy|socket-proxy)$}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ====================================================================
# Functions
# ====================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Create reports directory if it doesn't exist
ensure_reports_dir() {
    mkdir -p "$TRIVY_REPORTS_DIR"
    log_info "Reports directory: $TRIVY_REPORTS_DIR"
}

# Get list of running containers
get_running_containers() {
    docker ps --format '{{.Names}}' | grep -vE "$EXCLUDE_PATTERN" || true
}

# Scan a single container
scan_container() {
    local container_name="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local report_file="$TRIVY_REPORTS_DIR/${container_name}_${timestamp}.json"
    local summary_file="$TRIVY_REPORTS_DIR/${container_name}_${timestamp}_summary.txt"

    log_info "Scanning container: $container_name"

    # Run Trivy scan inside the Trivy container
    if docker exec "$TRIVY_CONTAINER" trivy image \
        --format "$TRIVY_FORMAT" \
        --severity "$TRIVY_SEVERITY" \
        --timeout "$TRIVY_TIMEOUT" \
        --scanners vuln,secret,config \
        --output "/reports/$(basename "$report_file")" \
        "docker://socket-proxy:2375/$container_name" 2>&1; then

        log_success "Scan completed for $container_name"

        # Generate human-readable summary
        docker exec "$TRIVY_CONTAINER" trivy image \
            --format table \
            --severity "$TRIVY_SEVERITY" \
            --timeout "$TRIVY_TIMEOUT" \
            --scanners vuln,secret,config \
            "docker://socket-proxy:2375/$container_name" > "$summary_file" 2>&1 || true

        return 0
    else
        log_error "Scan failed for $container_name"
        return 1
    fi
}

# Parse scan results and count vulnerabilities
parse_scan_results() {
    local report_file="$1"

    if [[ ! -f "$report_file" ]]; then
        log_warning "Report file not found: $report_file"
        return 1
    fi

    # Count vulnerabilities by severity
    local critical_count
    local high_count
    local medium_count
    local secrets_count

    critical_count=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' "$report_file" 2>/dev/null || echo "0")
    high_count=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length' "$report_file" 2>/dev/null || echo "0")
    medium_count=$(jq -r '[.Results[]?.Vulnerabilities[]? | select(.Severity=="MEDIUM")] | length' "$report_file" 2>/dev/null || echo "0")
    secrets_count=$(jq -r '[.Results[]?.Secrets[]?] | length' "$report_file" 2>/dev/null || echo "0")

    echo "$critical_count $high_count $medium_count $secrets_count"
}

# Send alert to Alertmanager
send_alert() {
    local container_name="$1"
    local severity="$2"
    local critical_count="$3"
    local high_count="$4"
    local medium_count="$5"
    local secrets_count="$6"
    local report_file="$7"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Generate alert annotations
    local summary="Container $container_name has security issues: $critical_count CRITICAL, $high_count HIGH, $medium_count MEDIUM vulnerabilities"
    if [[ "$secrets_count" -gt 0 ]]; then
        summary="$summary and $secrets_count exposed secrets"
    fi

    # Create Alertmanager payload
    local alert_payload
    alert_payload=$(cat <<EOF
[
  {
    "labels": {
      "alertname": "TrivyVulnerabilitiesDetected",
      "severity": "$severity",
      "service": "trivy",
      "container": "$container_name",
      "component": "security-scanner"
    },
    "annotations": {
      "summary": "$summary",
      "description": "Trivy scan detected security issues in container $container_name. See report: $report_file",
      "critical_count": "$critical_count",
      "high_count": "$high_count",
      "medium_count": "$medium_count",
      "secrets_count": "$secrets_count",
      "report_path": "$report_file"
    },
    "startsAt": "$timestamp",
    "generatorURL": "https://trivy.${PUBLIC_FQDN:-localhost}"
  }
]
EOF
)

    # Send to Alertmanager
    if curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$alert_payload" \
        "$ALERTMANAGER_ENDPOINT" >/dev/null 2>&1; then
        log_success "Alert sent to Alertmanager for $container_name"
    else
        log_warning "Failed to send alert to Alertmanager (endpoint: $ALERTMANAGER_ENDPOINT)"
    fi
}

# Determine alert severity based on findings
determine_severity() {
    local critical_count="$1"
    local high_count="$2"
    local secrets_count="$3"

    if [[ "$critical_count" -ge "$CRITICAL_THRESHOLD" ]] || [[ "$secrets_count" -ge "$SECRETS_THRESHOLD" ]]; then
        echo "critical"
    elif [[ "$high_count" -ge "$HIGH_THRESHOLD" ]]; then
        echo "warning"
    else
        echo "info"
    fi
}

# Clean up old reports
cleanup_old_reports() {
    local retention_days="${TRIVY_RETENTION_DAYS:-30}"

    log_info "Cleaning up reports older than $retention_days days"

    find "$TRIVY_REPORTS_DIR" -type f -name "*.json" -mtime +"$retention_days" -delete 2>/dev/null || true
    find "$TRIVY_REPORTS_DIR" -type f -name "*.txt" -mtime +"$retention_days" -delete 2>/dev/null || true

    log_success "Old reports cleaned up"
}

# Main scanning function
main() {
    log_info "Starting Trivy container vulnerability scan"
    log_info "Severity levels: $TRIVY_SEVERITY"
    log_info "Alertmanager URL: $ALERTMANAGER_URL"

    # Ensure reports directory exists
    ensure_reports_dir

    # Check if Trivy container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${TRIVY_CONTAINER}$"; then
        log_error "Trivy container is not running"
        exit 1
    fi

    # Update vulnerability database
    log_info "Updating vulnerability database"
    if docker exec "$TRIVY_CONTAINER" trivy image --download-db-only; then
        log_success "Vulnerability database updated"
    else
        log_warning "Failed to update vulnerability database"
    fi

    # Get running containers
    local containers
    containers=$(get_running_containers)

    if [[ -z "$containers" ]]; then
        log_warning "No containers found to scan"
        exit 0
    fi

    log_info "Found $(echo "$containers" | wc -l) containers to scan"

    # Scan each container
    local total_scanned=0
    local total_alerts=0

    while IFS= read -r container_name; do
        [[ -z "$container_name" ]] && continue

        # Scan container
        if scan_container "$container_name"; then
            ((total_scanned++))

            # Find the latest report for this container
            local latest_report
            latest_report=$(find "$TRIVY_REPORTS_DIR" -type f -name "${container_name}_*.json" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

            if [[ -n "$latest_report" ]] && [[ -f "$latest_report" ]]; then
                # Parse results
                read -r critical_count high_count medium_count secrets_count <<< "$(parse_scan_results "$latest_report")"

                log_info "Results for $container_name: CRITICAL=$critical_count, HIGH=$high_count, MEDIUM=$medium_count, SECRETS=$secrets_count"

                # Determine if alert should be sent
                local severity
                severity=$(determine_severity "$critical_count" "$high_count" "$secrets_count")

                if [[ "$critical_count" -ge "$CRITICAL_THRESHOLD" ]] || \
                   [[ "$high_count" -ge "$HIGH_THRESHOLD" ]] || \
                   [[ "$secrets_count" -ge "$SECRETS_THRESHOLD" ]]; then

                    log_warning "Sending $severity alert for $container_name"
                    send_alert "$container_name" "$severity" "$critical_count" "$high_count" "$medium_count" "$secrets_count" "$latest_report"
                    ((total_alerts++))
                else
                    log_success "No significant issues found in $container_name"
                fi
            fi
        fi
    done <<< "$containers"

    # Clean up old reports
    cleanup_old_reports

    # Summary
    log_success "Scan complete: $total_scanned containers scanned, $total_alerts alerts sent"

    # Exit with appropriate code
    if [[ "$total_alerts" -gt 0 ]]; then
        log_warning "Security issues detected in $total_alerts containers"
        exit 0  # Don't fail in continuous scanning mode
    else
        log_success "All scanned containers are secure"
        exit 0
    fi
}

# ====================================================================
# Script Execution
# ====================================================================

# Parse command-line arguments
case "${1:-}" in
    --help|-h)
        cat <<EOF
Usage: $0 [OPTIONS]

Scan all running Docker containers for vulnerabilities using Trivy.

Options:
  --help, -h          Show this help message
  --cleanup-only      Only clean up old reports, don't scan
  --container NAME    Scan a specific container only

Environment Variables:
  TRIVY_SEVERITY              Severity levels (default: CRITICAL,HIGH,MEDIUM)
  TRIVY_CRITICAL_THRESHOLD    Alert threshold for CRITICAL (default: 1)
  TRIVY_HIGH_THRESHOLD        Alert threshold for HIGH (default: 5)
  TRIVY_SECRETS_THRESHOLD     Alert threshold for secrets (default: 1)
  TRIVY_RETENTION_DAYS        Report retention days (default: 30)
  ALERTMANAGER_URL            Alertmanager URL (default: http://localhost:9093)

Examples:
  $0                           # Scan all containers
  $0 --container traefik       # Scan specific container
  $0 --cleanup-only            # Clean up old reports

EOF
        exit 0
        ;;
    --cleanup-only)
        ensure_reports_dir
        cleanup_old_reports
        exit 0
        ;;
    --container)
        if [[ -z "${2:-}" ]]; then
            log_error "Container name required"
            exit 1
        fi
        ensure_reports_dir
        scan_container "$2"
        exit $?
        ;;
    *)
        main "$@"
        ;;
esac
