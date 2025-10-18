#!/bin/bash
# Validation script for OAuth fix deployment on VPS1

set -e

VPS_HOST="ubuntu@vps1.jacarsystems.net"
REMOTE_DIR="/opt/jacker"

echo "=========================================="
echo "OAuth Fix Deployment Validation - VPS1"
echo "=========================================="
echo ""

echo "[1/5] Verifying oauth.yml configuration..."
echo "---"
ssh $VPS_HOST "grep 'COOKIE_DOMAINS\|COOKIE_SAMESITE' $REMOTE_DIR/compose/oauth.yml"
echo ""

echo "[2/5] Verifying middlewares-oauth.yml configuration..."
echo "---"
ssh $VPS_HOST "grep -A 7 'authResponseHeaders' $REMOTE_DIR/config/traefik/rules/middlewares-oauth.yml"
echo ""

echo "[3/5] Checking OAuth container status..."
echo "---"
ssh $VPS_HOST "docker ps --filter name=oauth --format 'Name: {{.Names}}\nStatus: {{.Status}}\nPorts: {{.Ports}}'"
echo ""

echo "[4/5] Checking Traefik container status..."
echo "---"
ssh $VPS_HOST "docker ps --filter name=traefik --format 'Name: {{.Names}}\nStatus: {{.Status}}'"
echo ""

echo "[5/5] Checking OAuth logs for recent activity..."
echo "---"
ssh $VPS_HOST "docker logs oauth --tail 10 2>&1"
echo ""

echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
echo "Expected Configuration:"
echo "  - OAUTH2_PROXY_COOKIE_DOMAINS=.\${PUBLIC_FQDN} (plural)"
echo "  - OAUTH2_PROXY_COOKIE_SAMESITE=none"
echo "  - Set-Cookie in authResponseHeaders"
echo ""
echo "Next Steps:"
echo "  1. Test OAuth flow at: https://n8n.jacarsystems.net"
echo "  2. Clear browser cookies before testing"
echo "  3. Verify CSRF cookie is set correctly in browser DevTools"
echo ""
