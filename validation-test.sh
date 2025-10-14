#!/usr/bin/env bash
#
# Jacker Fresh Install Validation Script
# Tests the current deployment with recent SSL fixes
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track test results
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

section() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

check_prerequisites() {
    section "1. Prerequisite Checks"

    # Check .env file exists
    if [[ -f ".env" ]]; then
        pass ".env file exists"
        source .env
    else
        fail ".env file not found"
        return 1
    fi

    # Check domain configuration
    if [[ -n "${DOMAINNAME:-}" ]] && [[ -n "${PUBLIC_FQDN:-}" ]]; then
        pass "Domain configured: ${PUBLIC_FQDN}"
    else
        fail "Domain not configured in .env"
    fi

    # Check Let's Encrypt email
    if [[ -n "${LETSENCRYPT_EMAIL:-}" ]]; then
        pass "Let's Encrypt email: ${LETSENCRYPT_EMAIL}"
    else
        fail "LETSENCRYPT_EMAIL not set"
    fi
}

# ============================================================================
# DNS VALIDATION
# ============================================================================

check_dns() {
    section "2. DNS Resolution"

    if [[ -z "${PUBLIC_FQDN:-}" ]]; then
        fail "PUBLIC_FQDN not set, skipping DNS checks"
        return 1
    fi

    # Check main domain
    info "Checking DNS for ${PUBLIC_FQDN}..."
    if host "${PUBLIC_FQDN}" >/dev/null 2>&1; then
        local ip=$(host "${PUBLIC_FQDN}" | grep "has address" | awk '{print $4}' | head -1)
        pass "${PUBLIC_FQDN} resolves to ${ip}"
    else
        fail "${PUBLIC_FQDN} does not resolve"
    fi

    # Check key subdomains
    local subdomains=("traefik" "grafana" "prometheus" "homepage")
    for sub in "${subdomains[@]}"; do
        local fqdn="${sub}.${DOMAINNAME}"
        if host "${fqdn}" >/dev/null 2>&1; then
            local ip=$(host "${fqdn}" | grep "has address" | awk '{print $4}' | head -1)
            pass "${fqdn} resolves to ${ip}"
        else
            warn "${fqdn} does not resolve (may use wildcard)"
        fi
    done
}

# ============================================================================
# PORT CHECKS
# ============================================================================

check_ports() {
    section "3. Port Availability"

    # Check if ports 80 and 443 are listening
    if netstat -tuln 2>/dev/null | grep -q ":80 "; then
        pass "Port 80 is listening"
    else
        fail "Port 80 is not listening"
    fi

    if netstat -tuln 2>/dev/null | grep -q ":443 "; then
        pass "Port 443 is listening"
    else
        fail "Port 443 is not listening"
    fi

    # Check if ports are accessible externally (if we can determine public IP)
    if command -v curl >/dev/null 2>&1 && [[ -n "${PUBLIC_FQDN:-}" ]]; then
        info "Testing external HTTP accessibility..."
        if timeout 5 curl -s -o /dev/null -w "%{http_code}" "http://${PUBLIC_FQDN}" | grep -q "301\|302\|200"; then
            pass "Port 80 accessible externally (HTTP redirect working)"
        else
            warn "Port 80 may not be accessible externally"
        fi
    fi
}

# ============================================================================
# ACME.JSON VALIDATION
# ============================================================================

check_acme_json() {
    section "4. SSL Certificate Storage (acme.json)"

    local acme_file="data/traefik/acme/acme.json"

    # Check if acme.json exists
    if [[ -f "$acme_file" ]]; then
        pass "acme.json exists"
    else
        fail "acme.json does not exist at $acme_file"
        return 1
    fi

    # Check permissions (must be 600)
    local perms=$(stat -c "%a" "$acme_file" 2>/dev/null || stat -f "%OLp" "$acme_file" 2>/dev/null)
    if [[ "$perms" == "600" ]]; then
        pass "acme.json has correct permissions (600)"
    else
        fail "acme.json has incorrect permissions ($perms), should be 600"
    fi

    # Check if file is empty
    local size=$(stat -c "%s" "$acme_file" 2>/dev/null || stat -f "%z" "$acme_file" 2>/dev/null)
    if [[ "$size" -gt 10 ]]; then
        pass "acme.json contains data (${size} bytes)"
    else
        warn "acme.json is empty or nearly empty (${size} bytes) - no certificates issued yet"
    fi

    # Check ownership
    local owner=$(stat -c "%U:%G" "$acme_file" 2>/dev/null || stat -f "%Su:%Sg" "$acme_file" 2>/dev/null)
    info "acme.json owned by: $owner"
}

# ============================================================================
# TRAEFIK CONFIGURATION
# ============================================================================

check_traefik_config() {
    section "5. Traefik Configuration"

    # Check traefik.yml exists
    if [[ -f "config/traefik/traefik.yml" ]]; then
        pass "traefik.yml exists"
    else
        fail "traefik.yml not found"
        return 1
    fi

    # Check for Let's Encrypt email in config
    if grep -q "email: ${LETSENCRYPT_EMAIL}" config/traefik/traefik.yml; then
        pass "Let's Encrypt email configured in traefik.yml"
    else
        fail "Let's Encrypt email not found in traefik.yml"
    fi

    # Check for acme storage path
    if grep -q "storage: /acme/acme.json" config/traefik/traefik.yml; then
        pass "ACME storage path configured"
    else
        fail "ACME storage path not configured"
    fi

    # Check for HTTP challenge
    if grep -q "httpChallenge:" config/traefik/traefik.yml; then
        pass "HTTP challenge configured"
    else
        warn "HTTP challenge not found (may be using DNS challenge)"
    fi
}

# ============================================================================
# DOCKER CONTAINER STATUS
# ============================================================================

check_containers() {
    section "6. Docker Container Status"

    # Check if docker-compose.yml exists
    if [[ ! -f "docker-compose.yml" ]]; then
        fail "docker-compose.yml not found"
        return 1
    fi

    # Get container status
    local running=$(docker compose ps --filter "status=running" --services 2>/dev/null | wc -l)
    local total=$(docker compose ps --services 2>/dev/null | wc -l)

    if [[ $running -gt 0 ]]; then
        pass "$running of $total services running"
    else
        fail "No services running"
    fi

    # Check critical services
    local critical=("traefik" "socket-proxy" "postgres" "redis")
    for service in "${critical[@]}"; do
        if docker compose ps "$service" 2>/dev/null | grep -q "Up"; then
            pass "$service is running"
        else
            fail "$service is not running"
        fi
    done
}

# ============================================================================
# TRAEFIK LOGS ANALYSIS
# ============================================================================

check_traefik_logs() {
    section "7. Traefik Logs Analysis"

    if ! docker compose ps traefik 2>/dev/null | grep -q "Up"; then
        fail "Traefik is not running, skipping log analysis"
        return 1
    fi

    info "Analyzing last 100 lines of Traefik logs..."

    # Check for ACME errors
    if docker compose logs --tail=100 traefik 2>/dev/null | grep -i "acme" | grep -i "error"; then
        fail "ACME errors found in Traefik logs (see above)"
    else
        pass "No ACME errors in recent logs"
    fi

    # Check for certificate acquisition
    if docker compose logs --tail=100 traefik 2>/dev/null | grep -i "certificate.*obtained\|certificate.*generated"; then
        pass "Certificate acquisition logged"
    else
        warn "No certificate acquisition found in recent logs"
    fi

    # Check for Let's Encrypt communication
    if docker compose logs --tail=100 traefik 2>/dev/null | grep -i "letsencrypt\|acme-v02"; then
        info "Let's Encrypt communication detected"
    else
        warn "No Let's Encrypt communication in recent logs"
    fi

    # Check for default certificate warnings
    if docker compose logs --tail=100 traefik 2>/dev/null | grep -i "TRAEFIK DEFAULT CERT"; then
        fail "Using TRAEFIK DEFAULT CERT - SSL not working properly"
    else
        pass "Not using default certificate"
    fi
}

# ============================================================================
# SSL CERTIFICATE VALIDATION
# ============================================================================

check_ssl_certificates() {
    section "8. SSL Certificate Validation"

    if [[ -z "${PUBLIC_FQDN:-}" ]]; then
        warn "PUBLIC_FQDN not set, skipping SSL checks"
        return 0
    fi

    # Check if we can reach the service
    if ! timeout 5 curl -s -o /dev/null "https://${PUBLIC_FQDN}" 2>/dev/null; then
        warn "Cannot reach https://${PUBLIC_FQDN} (may be expected during initial setup)"
        return 0
    fi

    info "Checking SSL certificate for ${PUBLIC_FQDN}..."

    # Get certificate info
    local cert_info=$(echo | timeout 5 openssl s_client -servername "${PUBLIC_FQDN}" -connect "${PUBLIC_FQDN}:443" 2>/dev/null | openssl x509 -noout -issuer -subject -dates 2>/dev/null)

    if [[ -n "$cert_info" ]]; then
        # Check if it's a Let's Encrypt certificate
        if echo "$cert_info" | grep -q "Let's Encrypt"; then
            pass "Valid Let's Encrypt certificate detected"
            echo "$cert_info" | while read -r line; do
                info "  $line"
            done
        elif echo "$cert_info" | grep -q "TRAEFIK DEFAULT CERT\|Traefik"; then
            fail "Using Traefik default certificate (SSL NOT working)"
        else
            warn "Certificate found but issuer unclear"
            echo "$cert_info" | while read -r line; do
                info "  $line"
            done
        fi
    else
        warn "Could not retrieve certificate information"
    fi
}

# ============================================================================
# SERVICE ACCESSIBILITY
# ============================================================================

check_service_accessibility() {
    section "9. Service Accessibility"

    if [[ -z "${DOMAINNAME:-}" ]]; then
        warn "DOMAINNAME not set, skipping accessibility checks"
        return 0
    fi

    local services=("homepage" "traefik" "grafana" "prometheus")

    for service in "${services[@]}"; do
        local url="https://${service}.${DOMAINNAME}"
        info "Checking $url..."

        local http_code=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" -k "$url" 2>/dev/null || echo "000")

        case "$http_code" in
            200|301|302|401|403)
                pass "$service accessible (HTTP $http_code)"
                ;;
            000)
                warn "$service not accessible (connection failed)"
                ;;
            *)
                warn "$service returned HTTP $http_code"
                ;;
        esac
    done
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================

show_summary() {
    section "Validation Summary"

    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All critical checks passed!${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}⚠ There are $WARNINGS warnings that should be reviewed${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ $FAILED checks failed${NC}"
        echo -e "${YELLOW}Please review the failures above before proceeding${NC}"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}║        Jacker Fresh Install Validation Script            ║${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"

    check_prerequisites
    check_dns
    check_ports
    check_acme_json
    check_traefik_config
    check_containers
    check_traefik_logs
    check_ssl_certificates
    check_service_accessibility
    show_summary
}

# Change to script directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run main function
main "$@"
