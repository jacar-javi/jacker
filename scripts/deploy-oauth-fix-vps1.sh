#!/bin/bash
# Quick OAuth fix deployment to VPS1
# Deploys critical OAuth fixes for CSRF cookie issues

set -e  # Exit on error

VPS_HOST="ubuntu@vps1.jacarsystems.net"
REMOTE_DIR="/opt/jacker"

echo "=========================================="
echo "Deploying OAuth fixes to VPS1"
echo "=========================================="
echo ""

echo "[1/4] Transferring oauth.yml to VPS1..."
scp -o StrictHostKeyChecking=no compose/oauth.yml $VPS_HOST:$REMOTE_DIR/compose/
echo "✓ oauth.yml transferred"
echo ""

echo "[2/4] Transferring middlewares-oauth.yml to VPS1..."
scp -o StrictHostKeyChecking=no config/traefik/rules/middlewares-oauth.yml $VPS_HOST:$REMOTE_DIR/config/traefik/rules/
echo "✓ middlewares-oauth.yml transferred"
echo ""

echo "[3/4] Recreating OAuth and Traefik containers..."
ssh $VPS_HOST "cd $REMOTE_DIR && docker compose up -d --force-recreate oauth traefik"
echo "✓ Containers recreated"
echo ""

echo "[4/4] Waiting 5 seconds for containers to stabilize..."
sleep 5
echo ""

echo "=========================================="
echo "Deployment Complete - Showing OAuth Logs"
echo "=========================================="
ssh $VPS_HOST "cd $REMOTE_DIR && docker compose logs --tail 30 oauth"
echo ""

echo "=========================================="
echo "Verification Commands"
echo "=========================================="
echo "Run these commands to verify the deployment:"
echo ""
echo "# Verify COOKIE_DOMAINS (plural) and COOKIE_SAMESITE=none:"
echo "ssh $VPS_HOST 'cd $REMOTE_DIR && grep \"COOKIE_DOMAINS\\|COOKIE_SAMESITE\" compose/oauth.yml'"
echo ""
echo "# Verify Set-Cookie header in middleware:"
echo "ssh $VPS_HOST 'cd $REMOTE_DIR && grep Set-Cookie config/traefik/rules/middlewares-oauth.yml'"
echo ""
echo "# Test OAuth flow:"
echo "echo 'Visit https://n8n.jacarsystems.net and test authentication'"
echo ""
