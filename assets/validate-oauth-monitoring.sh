#!/bin/bash
# validate-oauth-monitoring.sh - Validates OAuth2-Proxy monitoring integration
# This script checks that all monitoring components for OAuth2-Proxy are properly configured

set -euo pipefail

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi
cd "$JACKER_DIR" || exit 1

# Source .env file if it exists
if [[ -f .env ]]; then
    source .env
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Results tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

    case $status in
        "PASS")
            echo -e "${GREEN}✓${NC} $message"
            ((PASSED_CHECKS++))
            ;;
        "FAIL")
            echo -e "${RED}✗${NC} $message"
            ((FAILED_CHECKS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠${NC} $message"
            ((WARNINGS++))
            ;;
        "INFO")
            echo -e "  $message"
            ;;
    esac
    ((TOTAL_CHECKS++))
}

# Function to check if a service is running
check_service_running() {
    local service=$1
    if docker ps --format "table {{.Names}}" | grep -q "^${service}$"; then
        return 0
    else
        return 1
    fi
}

# Function to check if a port is accessible
check_port() {
    local host=$1
    local port=$2
    nc -z -w1 "$host" "$port" 2>/dev/null
}

echo "======================================"
echo "OAuth2-Proxy Monitoring Validation"
echo "======================================"
echo

# 1. Check OAuth2-Proxy container is running
echo "1. Service Status Checks:"
echo "------------------------"

if check_service_running "oauth"; then
    print_status "PASS" "OAuth2-Proxy container is running"
else
    print_status "FAIL" "OAuth2-Proxy container is not running"
fi

if check_service_running "prometheus"; then
    print_status "PASS" "Prometheus container is running"
else
    print_status "FAIL" "Prometheus container is not running"
fi

if check_service_running "grafana"; then
    print_status "PASS" "Grafana container is running"
else
    print_status "FAIL" "Grafana container is not running"
fi

if check_service_running "loki"; then
    print_status "PASS" "Loki container is running"
else
    print_status "FAIL" "Loki container is not running"
fi

if check_service_running "promtail"; then
    print_status "PASS" "Promtail container is running"
else
    print_status "FAIL" "Promtail container is not running"
fi

echo

# 2. Check OAuth2-Proxy metrics endpoint
echo "2. Metrics Endpoint Checks:"
echo "--------------------------"

if check_port "127.0.0.1" "9090"; then
    print_status "PASS" "OAuth2-Proxy metrics port is accessible"

    # Try to fetch metrics
    if curl -s http://127.0.0.1:9090/metrics | grep -q "oauth2_proxy"; then
        print_status "PASS" "OAuth2-Proxy metrics are being exposed"

        # Count metrics
        metric_count=$(curl -s http://127.0.0.1:9090/metrics | grep -c "^oauth2_proxy" || true)
        print_status "INFO" "Found $metric_count OAuth2-Proxy metrics"
    else
        print_status "FAIL" "OAuth2-Proxy metrics not found at endpoint"
    fi
else
    print_status "FAIL" "OAuth2-Proxy metrics port not accessible"
fi

echo

# 3. Check Prometheus scraping
echo "3. Prometheus Scraping Checks:"
echo "-----------------------------"

# Check if Prometheus can reach OAuth2-Proxy
if docker exec prometheus wget -q -O- http://oauth:9090/metrics 2>/dev/null | grep -q "oauth2_proxy"; then
    print_status "PASS" "Prometheus can reach OAuth2-Proxy metrics endpoint"
else
    print_status "WARN" "Could not verify Prometheus connection to OAuth2-Proxy"
fi

# Check Prometheus targets
if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -q '"job":"oauth2-proxy"'; then
    print_status "PASS" "OAuth2-Proxy target configured in Prometheus"

    # Check target health
    if curl -s http://localhost:9090/api/v1/targets 2>/dev/null | grep -A5 '"job":"oauth2-proxy"' | grep -q '"health":"up"'; then
        print_status "PASS" "OAuth2-Proxy target is UP in Prometheus"
    else
        print_status "FAIL" "OAuth2-Proxy target is DOWN in Prometheus"
    fi
else
    print_status "FAIL" "OAuth2-Proxy target not found in Prometheus configuration"
fi

echo

# 4. Check alert rules
echo "4. Alert Rules Checks:"
echo "--------------------"

if [[ -f data/prometheus/rules/oauth.yml ]]; then
    print_status "PASS" "OAuth alert rules file exists"

    # Count alerts
    alert_count=$(grep -c "alert:" data/prometheus/rules/oauth.yml || true)
    print_status "INFO" "Found $alert_count alert rules for OAuth2-Proxy"

    # Check if alerts are loaded in Prometheus
    if curl -s http://localhost:9090/api/v1/rules 2>/dev/null | grep -q "OAuth2Proxy"; then
        print_status "PASS" "OAuth alert rules loaded in Prometheus"
    else
        print_status "WARN" "Could not verify alert rules in Prometheus"
    fi
else
    print_status "FAIL" "OAuth alert rules file not found"
fi

echo

# 5. Check Grafana dashboard
echo "5. Grafana Dashboard Checks:"
echo "--------------------------"

if [[ -f data/grafana/provisioning/dashboards/oauth2-proxy.json ]]; then
    print_status "PASS" "OAuth2-Proxy dashboard file exists"

    # Check dashboard structure
    if grep -q '"uid": "oauth2-proxy"' data/grafana/provisioning/dashboards/oauth2-proxy.json; then
        print_status "PASS" "Dashboard has correct UID"
    else
        print_status "FAIL" "Dashboard UID not found or incorrect"
    fi

    # Count panels
    panel_count=$(grep -c '"type":' data/grafana/provisioning/dashboards/oauth2-proxy.json || true)
    print_status "INFO" "Dashboard contains $panel_count panels"
else
    print_status "FAIL" "OAuth2-Proxy dashboard file not found"
fi

echo

# 6. Check Promtail configuration
echo "6. Log Collection Checks:"
echo "-----------------------"

if [[ -f data/loki/promtail-config.yml ]]; then
    print_status "PASS" "Promtail configuration file exists"

    # Check for OAuth job
    if grep -q "job_name: oauth2_proxy" data/loki/promtail-config.yml; then
        print_status "PASS" "OAuth2-Proxy log collection job configured"
    else
        print_status "FAIL" "OAuth2-Proxy log collection job not found"
    fi

    # Check if Promtail is collecting OAuth logs
    if docker logs promtail 2>&1 | tail -50 | grep -q "oauth"; then
        print_status "PASS" "Promtail is processing OAuth2-Proxy logs"
    else
        print_status "WARN" "Could not verify OAuth2-Proxy log processing"
    fi
else
    print_status "FAIL" "Promtail configuration file not found"
fi

echo

# 7. Check Loki for OAuth logs
echo "7. Loki Log Storage Checks:"
echo "-------------------------"

# Query Loki for OAuth logs (last 5 minutes)
LOKI_QUERY='http://localhost:3100/loki/api/v1/query_range?query={container="oauth"}&limit=10&start='$(($(date +%s) - 300))'000000000'

if curl -s "$LOKI_QUERY" 2>/dev/null | grep -q '"status":"success"'; then
    print_status "PASS" "Loki API is accessible"

    log_count=$(curl -s "$LOKI_QUERY" 2>/dev/null | grep -o '"stream"' | wc -l || echo "0")
    if [[ $log_count -gt 0 ]]; then
        print_status "PASS" "Found OAuth2-Proxy logs in Loki (${log_count} streams)"
    else
        print_status "WARN" "No OAuth2-Proxy logs found in Loki (container may be quiet)"
    fi
else
    print_status "WARN" "Could not query Loki API"
fi

echo

# 8. Configuration consistency checks
echo "8. Configuration Consistency:"
echo "---------------------------"

# Check if OAuth environment variables are set
if [[ -n "${OAUTH_CLIENT_ID:-}" ]]; then
    print_status "PASS" "OAuth client ID is configured"
else
    print_status "WARN" "OAuth client ID not set in .env"
fi

# Check if metrics port matches in compose and prometheus
compose_port=$(grep -A1 "ports:" compose/oauth.yml | grep "9090:9090" | cut -d: -f2 | head -1)
prometheus_port=$(grep -A1 "oauth2-proxy" data/prometheus/prometheus.yml | grep "targets:" | grep -o "9090" || echo "")

if [[ "$compose_port" == "$prometheus_port" ]]; then
    print_status "PASS" "Metrics port configuration is consistent"
else
    print_status "WARN" "Metrics port mismatch between compose and Prometheus config"
fi

echo
echo "======================================"
echo "Validation Summary"
echo "======================================"
echo "Total checks: $TOTAL_CHECKS"
echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
if [[ $WARNINGS -gt 0 ]]; then
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
fi
if [[ $FAILED_CHECKS -gt 0 ]]; then
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
fi

echo

# Overall status
if [[ $FAILED_CHECKS -eq 0 ]]; then
    if [[ $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ OAuth2-Proxy monitoring integration is fully operational!${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠ OAuth2-Proxy monitoring is operational with warnings.${NC}"
        echo "Please review the warnings above for potential improvements."
        exit 0
    fi
else
    echo -e "${RED}✗ OAuth2-Proxy monitoring has configuration issues.${NC}"
    echo "Please address the failed checks above."
    exit 1
fi