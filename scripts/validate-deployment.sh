#!/bin/bash
# Deployment Readiness Validation Script
# Based on lessons learned from OAuth debugging session
# Created by Puto Amo Enhancement Project

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "=========================================="
echo "  Deployment Readiness Validation"
echo "=========================================="
echo ""

# Function to print errors
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

# Function to print warnings
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((WARNINGS++))
}

# Function to print success
success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

# Function to check section
section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

#
# SECTION 1: Environment File Validation
#
section "1. Environment Configuration (.env)"

if [[ ! -f .env ]]; then
    error ".env file not found"
else
    success ".env file exists"

    # Check for required variables
    REQUIRED_VARS=(
        "DOMAINNAME"
        "PUBLIC_FQDN"
        "OAUTH_CLIENT_ID"
        "OAUTH_CLIENT_SECRET"
        "OAUTH_COOKIE_SECRET"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${var}=" .env; then
            # Check if value is not empty or placeholder
            value=$(grep "^${var}=" .env | cut -d'=' -f2-)
            if [[ -z "$value" ]] || [[ "$value" =~ (changeme|example|test-|generated-) ]]; then
                warning "${var} appears to have placeholder/test value"
            else
                success "${var} is set"
            fi
        else
            error "${var} is not set in .env"
        fi
    done
fi

#
# SECTION 2: OAuth Configuration (Lessons Learned)
#
section "2. OAuth2-Proxy Configuration (Critical)"

# Check for COOKIE_DOMAINS (plural, not singular)
if grep -q "OAUTH2_PROXY_COOKIE_DOMAINS" compose/oauth.yml; then
    success "Using OAUTH2_PROXY_COOKIE_DOMAINS (plural - correct)"
else
    error "Missing OAUTH2_PROXY_COOKIE_DOMAINS - should be plural!"
fi

# Check if accidentally using singular form
if grep -q "OAUTH2_PROXY_COOKIE_DOMAIN[^S]" compose/oauth.yml; then
    error "Found OAUTH2_PROXY_COOKIE_DOMAIN (singular) - should be COOKIE_DOMAINS (plural)"
fi

# Check for SameSite=none (required for OAuth)
if grep -q "COOKIE_SAMESITE=none" compose/oauth.yml; then
    success "SameSite=none configured (required for OAuth)"
elif grep -q "COOKIE_SAMESITE=lax" compose/oauth.yml; then
    error "SameSite=lax will block OAuth CSRF cookies! Change to 'none'"
else
    warning "SameSite attribute not found in OAuth config"
fi

# Check for Secure=true (required when SameSite=none)
if grep -q "COOKIE_SECURE=true" compose/oauth.yml; then
    success "COOKIE_SECURE=true (required with SameSite=none)"
else
    warning "COOKIE_SECURE should be true when using SameSite=none"
fi

# Check for cookie domain leading dot
if grep -q "COOKIE_DOMAINS=\.\${" compose/oauth.yml; then
    success "Cookie domain has leading dot for subdomain sharing"
elif grep -q "COOKIE_DOMAINS=\${" compose/oauth.yml; then
    warning "Cookie domain missing leading dot - may not work for subdomains"
fi

#
# SECTION 3: Docker Secrets vs Environment Variables
#
section "3. Configuration Method (Secrets vs Env Vars)"

# Check if using Docker secrets for dynamic values (anti-pattern from lessons learned)
if grep -q "_FILE" compose/oauth.yml && grep -q "COOKIE" compose/oauth.yml; then
    warning "Using Docker secrets for OAuth cookie config - secrets are immutable!"
    echo "        Recommendation: Use environment variables for dynamic OAuth settings"
fi

#
# SECTION 4: Compose File Syntax
#
section "4. Docker Compose Syntax Validation"

COMPOSE_FILES=(compose/*.yml)
for file in "${COMPOSE_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        if docker compose -f "$file" config > /dev/null 2>&1; then
            success "$(basename "$file") syntax valid"
        else
            error "$(basename "$file") has syntax errors"
        fi
    fi
done

#
# SECTION 5: Traefik Configuration
#
section "5. Traefik Routing & Middleware"

# Check for OAuth middleware in services
if grep -rq "chain-oauth@file" compose/*.yml; then
    success "OAuth middleware chain found in services"
else
    warning "No services using OAuth middleware - is this intentional?"
fi

# Check for proper HTTPS redirect
if grep -q "redirect-to-https@file" compose/traefik.yml; then
    success "HTTPS redirect middleware configured"
else
    warning "HTTPS redirect middleware not found"
fi

#
# SECTION 6: Redis Session Store
#
section "6. Redis Session Store Configuration"

if [[ -f compose/redis.yml ]]; then
    success "Redis compose file exists"

    # Check for ACL configuration
    if grep -q "redis.conf" compose/redis.yml || grep -q "REDIS.*PASSWORD" .env; then
        success "Redis authentication configured"
    else
        warning "Redis may not have authentication configured"
    fi
fi

#
# SECTION 7: Network Configuration
#
section "7. Docker Network Configuration"

# Check for required networks in .env
if grep -q "DOCKER_DEFAULT_SUBNET" .env && grep -q "SOCKET_PROXY_SUBNET" .env; then
    success "Custom network subnets defined"
else
    warning "Custom network subnets not configured"
fi

#
# SECTION 8: SSL/TLS Configuration
#
section "8. SSL/TLS & Let's Encrypt"

if grep -q "LETSENCRYPT_EMAIL" .env; then
    success "Let's Encrypt email configured"
else
    error "LETSENCRYPT_EMAIL not set"
fi

# Check for staging flag
if grep -q "LETSENCRYPT_STAGING=true" .env; then
    warning "Let's Encrypt STAGING mode enabled - no production certificates!"
elif grep -q "LETSENCRYPT_STAGING=false" .env; then
    success "Let's Encrypt production mode enabled"
fi

#
# SECTION 9: Monitoring Configuration
#
section "9. Monitoring Stack Validation"

MONITORING_SERVICES=("prometheus" "grafana" "loki" "promtail")
for service in "${MONITORING_SERVICES[@]}"; do
    if [[ -f "compose/${service}.yml" ]]; then
        success "${service} configuration found"
    else
        warning "${service} not configured"
    fi
done

#
# SECTION 10: Security Headers & Best Practices
#
section "10. Security Configuration"

# Check for CrowdSec
if [[ -f compose/crowdsec.yml ]]; then
    success "CrowdSec security configured"
else
    warning "CrowdSec not configured - consider adding for security"
fi

# Check for socket proxy
if [[ -f compose/socket-proxy.yml ]]; then
    success "Docker socket proxy configured (security best practice)"
else
    warning "Docker socket not proxied - direct access increases attack surface"
fi

#
# FINAL REPORT
#
section "Validation Summary"

echo ""
if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED${NC}"
    echo "System is ready for deployment!"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ PASSED WITH WARNINGS${NC}"
    echo "Errors: 0 | Warnings: $WARNINGS"
    echo "Review warnings before deploying to production"
    exit 0
else
    echo -e "${RED}✗ VALIDATION FAILED${NC}"
    echo "Errors: $ERRORS | Warnings: $WARNINGS"
    echo "Fix errors before deployment!"
    exit 1
fi
