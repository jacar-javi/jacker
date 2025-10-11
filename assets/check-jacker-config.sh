#!/bin/bash
# Jacker Configuration Diagnostic Script
# Checks for common configuration issues causing 404 errors

echo "=== Jacker Configuration Check ==="
echo ""

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine Jacker root directory
# If script is in assets/ subdirectory, go up one level
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi

ENV_FILE="$JACKER_DIR/.env"
SECRETS_FILE="$JACKER_DIR/secrets/traefik_forward_oauth"

# Verify we found the correct directory
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Cannot find Jacker installation (.env not found)"
    echo "   Script location: $SCRIPT_DIR"
    echo "   Expected Jacker directory: $JACKER_DIR"
    exit 1
fi

echo "Using Jacker directory: $JACKER_DIR"
echo ""

# Check .env OAuth config
echo "1. Checking OAuth Configuration..."
if grep -q "^OAUTH_CLIENT_ID=$" "$ENV_FILE" 2>/dev/null || ! grep -q "^OAUTH_CLIENT_ID=" "$ENV_FILE" 2>/dev/null; then
    echo "   ❌ OAUTH_CLIENT_ID is empty or not set"
    OAUTH_MISSING=true
else
    echo "   ✓ OAUTH_CLIENT_ID is set"
fi

if grep -q "^OAUTH_CLIENT_SECRET=$" "$ENV_FILE" 2>/dev/null || ! grep -q "^OAUTH_CLIENT_SECRET=" "$ENV_FILE" 2>/dev/null; then
    echo "   ❌ OAUTH_CLIENT_SECRET is empty or not set"
    OAUTH_MISSING=true
else
    echo "   ✓ OAUTH_CLIENT_SECRET is set"
fi

if grep -q "^OAUTH_SECRET=$" "$ENV_FILE" 2>/dev/null || ! grep -q "^OAUTH_SECRET=" "$ENV_FILE" 2>/dev/null; then
    echo "   ❌ OAUTH_SECRET is empty or not set"
    OAUTH_MISSING=true
else
    echo "   ✓ OAUTH_SECRET is set"
fi

if grep -q "^OAUTH_WHITELIST=$" "$ENV_FILE" 2>/dev/null || ! grep -q "^OAUTH_WHITELIST=" "$ENV_FILE" 2>/dev/null; then
    echo "   ⚠️  OAUTH_WHITELIST is empty or not set"
    OAUTH_MISSING=true
else
    WHITELIST=$(grep "^OAUTH_WHITELIST=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    echo "   ✓ OAUTH_WHITELIST: $WHITELIST"
fi

# Check domain config
echo ""
echo "2. Checking Domain Configuration..."
DOMAIN=$(grep "^DOMAINNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
PUBLIC_FQDN=$(grep "^PUBLIC_FQDN=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)

if [ "$DOMAIN" = "example.com" ]; then
    echo "   ⚠️  Using placeholder domain: $DOMAIN"
    echo "      This will not work in production!"
    DOMAIN_ISSUE=true
else
    echo "   ✓ Domain: $DOMAIN"
fi

if [ -n "$PUBLIC_FQDN" ]; then
    echo "   ✓ PUBLIC_FQDN: $PUBLIC_FQDN"
else
    echo "   ❌ PUBLIC_FQDN not set"
    DOMAIN_ISSUE=true
fi

# Check Let's Encrypt email
echo ""
echo "3. Checking Let's Encrypt Email..."
if grep -q "^LETSENCRYPT_EMAIL=$" "$ENV_FILE" 2>/dev/null || ! grep -q "^LETSENCRYPT_EMAIL=" "$ENV_FILE" 2>/dev/null; then
    echo "   ❌ LETSENCRYPT_EMAIL is empty or not set"
    LETSENCRYPT_ISSUE=true
else
    EMAIL=$(grep "^LETSENCRYPT_EMAIL=" "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    echo "   ✓ Email: $EMAIL"
fi

# Check secrets file
echo ""
echo "4. Checking OAuth Secrets File..."
if [ -f "$SECRETS_FILE" ]; then
    echo "   ✓ Secrets file exists: $SECRETS_FILE"

    # Check if secrets file has empty values
    if grep -q "client-id=$" "$SECRETS_FILE" 2>/dev/null; then
        echo "   ⚠️  Secrets file has empty client-id"
        SECRETS_ISSUE=true
    fi

    if grep -q "client-secret=$" "$SECRETS_FILE" 2>/dev/null; then
        echo "   ⚠️  Secrets file has empty client-secret"
        SECRETS_ISSUE=true
    fi

    if grep -q "^secret=$" "$SECRETS_FILE" 2>/dev/null; then
        echo "   ⚠️  Secrets file has empty secret"
        SECRETS_ISSUE=true
    fi

    if [ -z "$SECRETS_ISSUE" ]; then
        echo "   ✓ Secrets file appears properly configured"
    fi
else
    echo "   ❌ Secrets file missing: $SECRETS_FILE"
    SECRETS_MISSING=true
fi

# Check Docker services (if docker is available)
echo ""
echo "5. Checking Docker Services..."
if command -v docker &> /dev/null; then
    cd "$JACKER_DIR" 2>/dev/null || exit 1

    if [ -f "Makefile" ]; then
        TRAEFIK_STATUS=$(make ps 2>/dev/null | grep traefik | awk '{print $7}' || echo "unknown")
        OAUTH_STATUS=$(make ps 2>/dev/null | grep oauth | awk '{print $7}' || echo "unknown")

        if [ "$TRAEFIK_STATUS" != "unknown" ]; then
            if echo "$TRAEFIK_STATUS" | grep -q "healthy\|running"; then
                echo "   ✓ Traefik: $TRAEFIK_STATUS"
            else
                echo "   ⚠️  Traefik: $TRAEFIK_STATUS"
            fi
        fi

        if [ "$OAUTH_STATUS" != "unknown" ]; then
            if echo "$OAUTH_STATUS" | grep -q "healthy\|running"; then
                echo "   ✓ OAuth: $OAUTH_STATUS"
            else
                echo "   ⚠️  OAuth: $OAUTH_STATUS"
            fi
        fi
    else
        echo "   ⚠️  Cannot check services (Makefile not found)"
    fi
else
    echo "   ⚠️  Docker not available in this environment"
fi

# Summary
echo ""
echo "=== SUMMARY ==="
echo ""

ISSUES_FOUND=false

if [ "$OAUTH_MISSING" = true ]; then
    echo "❌ CRITICAL: OAuth credentials not configured"
    echo "   → This is the PRIMARY cause of 404 errors"
    echo "   → See TROUBLESHOOTING_404_ERRORS.md - Section: Google OAuth Setup"
    echo ""
    ISSUES_FOUND=true
fi

if [ "$SECRETS_MISSING" = true ] || [ "$SECRETS_ISSUE" = true ]; then
    echo "❌ CRITICAL: OAuth secrets file issue"
    echo "   → Recreate with: cd $JACKER_DIR && envsubst < assets/templates/traefik_forward_oauth.template > secrets/traefik_forward_oauth"
    echo "   → Then restart: make down && make install"
    echo ""
    ISSUES_FOUND=true
fi

if [ "$DOMAIN_ISSUE" = true ]; then
    echo "⚠️  WARNING: Domain configuration uses placeholder"
    echo "   → For production: Configure real domain in .env"
    echo "   → For testing: Use bypass method (see TROUBLESHOOTING_404_ERRORS.md - Option B)"
    echo ""
    ISSUES_FOUND=true
fi

if [ "$LETSENCRYPT_ISSUE" = true ]; then
    echo "⚠️  WARNING: Let's Encrypt email not configured"
    echo "   → Set LETSENCRYPT_EMAIL in .env"
    echo "   → Required for SSL certificates"
    echo ""
    ISSUES_FOUND=true
fi

if [ "$ISSUES_FOUND" = false ]; then
    echo "✓ No critical issues detected!"
    echo ""
    echo "If you're still experiencing 404 errors:"
    echo "  1. Restart services: make down && make install"
    echo "  2. Check Traefik logs: make logs service=traefik"
    echo "  3. Verify DNS resolution: nslookup grafana.$DOMAIN"
    echo "  4. See TROUBLESHOOTING_404_ERRORS.md for detailed steps"
else
    echo "Review the issues above and consult:"
    echo "  → TROUBLESHOOTING_404_ERRORS.md (comprehensive guide)"
fi

echo ""
