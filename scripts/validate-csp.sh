#!/usr/bin/env bash
###############################################################################
# CSP Configuration Validator
# Validates Content Security Policy middleware configurations
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

###############################################################################
# Helper Functions
###############################################################################

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

###############################################################################
# Validation Functions
###############################################################################

validate_file_exists() {
    local file="$1"
    local description="$2"

    if [[ -f "$file" ]]; then
        print_success "$description exists: $file"
        return 0
    else
        print_error "$description not found: $file"
        return 1
    fi
}

validate_csp_directive() {
    local file="$1"
    local middleware="$2"
    local directive="$3"
    local should_contain="$4"
    local should_not_contain="$5"

    if ! [[ -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi

    local csp_block
    csp_block=$(awk "/^    ${middleware}:/,/^    [a-z]/" "$file" | grep -A 50 "contentSecurityPolicy:" || true)

    if [[ -z "$csp_block" ]]; then
        print_error "$middleware: CSP directive not found"
        return 1
    fi

    # Check for required content
    if [[ -n "$should_contain" ]]; then
        if echo "$csp_block" | grep -q "$should_contain"; then
            print_success "$middleware: Contains required directive '$should_contain'"
        else
            print_error "$middleware: Missing required directive '$should_contain'"
            return 1
        fi
    fi

    # Check for prohibited content
    if [[ -n "$should_not_contain" ]]; then
        if echo "$csp_block" | grep -q "$should_not_contain"; then
            print_error "$middleware: Contains prohibited directive '$should_not_contain'"
            return 1
        else
            print_success "$middleware: Does not contain '$should_not_contain'"
        fi
    fi

    return 0
}

validate_chain_exists() {
    local file="$1"
    local chain_name="$2"

    if ! [[ -f "$file" ]]; then
        print_error "Chain file not found: $file"
        return 1
    fi

    if grep -q "^    ${chain_name}:" "$file"; then
        print_success "Chain '$chain_name' exists in $file"
        return 0
    else
        print_error "Chain '$chain_name' not found in $file"
        return 1
    fi
}

###############################################################################
# Main Validation
###############################################################################

main() {
    print_header "CSP Configuration Validator"
    echo ""

    # Change to project root
    cd "$(dirname "$0")/.." || exit 1

    # Validate middleware files exist
    print_header "1. Validating Middleware Files"
    validate_file_exists "config/traefik/rules/middlewares-secure-headers.yml" "Secure headers middleware"
    validate_file_exists "config/traefik/rules/chain-oauth-relaxed.yml" "OAuth relaxed chain"
    validate_file_exists "config/traefik/rules/chain-public-relaxed.yml" "Public relaxed chain"
    validate_file_exists "config/traefik/rules/chain-strict-csp.yml" "Strict CSP chains"
    echo ""

    # Validate documentation exists
    print_header "2. Validating Documentation"
    validate_file_exists "docs/guides/CSP_IMPLEMENTATION_GUIDE.md" "CSP Implementation Guide"
    validate_file_exists "docs/guides/CSP_QUICK_REFERENCE.md" "CSP Quick Reference"
    validate_file_exists "docs/CSP_HARDENING_SUMMARY.md" "CSP Hardening Summary"
    echo ""

    # Validate strict CSP middleware
    print_header "3. Validating Strict CSP Middleware"
    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers-strict" \
        "script-src" \
        "script-src 'self'" \
        "'unsafe-inline'"

    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers-strict" \
        "script-src" \
        "" \
        "'unsafe-eval'"
    echo ""

    # Validate default CSP middleware (hardened)
    print_header "4. Validating Default CSP Middleware (Hardened)"
    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers" \
        "script-src" \
        "script-src 'self'" \
        "'unsafe-inline'"

    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers" \
        "script-src" \
        "" \
        "'unsafe-eval'"

    # Verify style-src still has unsafe-inline (intentional)
    if grep -A 50 "^    secure-headers:" "config/traefik/rules/middlewares-secure-headers.yml" | \
       grep "contentSecurityPolicy:" -A 20 | \
       grep "style-src" | \
       grep -q "'unsafe-inline'"; then
        print_info "Default CSP: style-src correctly includes 'unsafe-inline' (intended)"
    else
        print_warning "Default CSP: style-src does not include 'unsafe-inline'"
    fi
    echo ""

    # Validate relaxed CSP middleware
    print_header "5. Validating Relaxed CSP Middleware"
    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers-relaxed" \
        "script-src" \
        "'unsafe-inline'" \
        ""

    validate_csp_directive \
        "config/traefik/rules/middlewares-secure-headers.yml" \
        "secure-headers-relaxed" \
        "script-src" \
        "'unsafe-eval'" \
        ""

    print_info "Relaxed CSP includes unsafe directives (intended for legacy support)"
    echo ""

    # Validate chain configurations
    print_header "6. Validating Middleware Chains"
    validate_chain_exists "config/traefik/rules/chain-oauth-relaxed.yml" "chain-oauth-relaxed"
    validate_chain_exists "config/traefik/rules/chain-public-relaxed.yml" "chain-public-relaxed"
    validate_chain_exists "config/traefik/rules/chain-strict-csp.yml" "chain-oauth-strict"
    validate_chain_exists "config/traefik/rules/chain-strict-csp.yml" "chain-public-strict"
    validate_chain_exists "config/traefik/rules/chain-strict-csp.yml" "chain-api-strict"
    echo ""

    # Validate chain references correct middleware
    print_header "7. Validating Chain Middleware References"

    if grep -q "secure-headers-relaxed" "config/traefik/rules/chain-oauth-relaxed.yml"; then
        print_success "chain-oauth-relaxed references secure-headers-relaxed"
    else
        print_error "chain-oauth-relaxed does not reference secure-headers-relaxed"
    fi

    if grep -q "secure-headers-strict" "config/traefik/rules/chain-strict-csp.yml"; then
        print_success "Strict chains reference secure-headers-strict"
    else
        print_error "Strict chains do not reference secure-headers-strict"
    fi
    echo ""

    # Check for backward compatibility
    print_header "8. Validating Backward Compatibility"
    if grep -q "^    middlewares-secure-headers:" "config/traefik/rules/middlewares-secure-headers.yml"; then
        print_success "Backward compatibility alias 'middlewares-secure-headers' exists"
    else
        print_error "Backward compatibility alias 'middlewares-secure-headers' not found"
    fi
    echo ""

    # Summary
    print_header "Validation Summary"
    echo -e "${GREEN}Passed:${NC}  $CHECKS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNING"
    echo -e "${RED}Failed:${NC}  $CHECKS_FAILED"
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All CSP validations passed!${NC}"
        echo ""
        echo "CSP Configuration Summary:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "• secure-headers-strict:  Maximum security (no unsafe directives)"
        echo "• secure-headers:         Hardened default (no unsafe-inline/eval in scripts)"
        echo "• secure-headers-relaxed: Legacy support (includes unsafe directives)"
        echo ""
        echo "Available Chains:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "• chain-oauth-strict, chain-public-strict, chain-api-strict"
        echo "• chain-oauth, chain-public, chain-api (now hardened)"
        echo "• chain-oauth-relaxed, chain-public-relaxed (legacy)"
        echo ""
        echo "Documentation:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "• Implementation Guide: docs/guides/CSP_IMPLEMENTATION_GUIDE.md"
        echo "• Quick Reference:      docs/guides/CSP_QUICK_REFERENCE.md"
        echo "• Hardening Summary:    docs/CSP_HARDENING_SUMMARY.md"
        echo ""
        return 0
    else
        echo -e "${RED}✗ CSP validation failed with $CHECKS_FAILED error(s)${NC}"
        echo ""
        echo "Please review the errors above and ensure all CSP configurations are correct."
        return 1
    fi
}

###############################################################################
# Script Entry Point
###############################################################################

main "$@"
