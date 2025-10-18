#!/bin/bash
# Quick health check for OAuth on VPS1

VPS_HOST="ubuntu@vps1.jacarsystems.net"

echo "OAuth Health Check - VPS1"
echo "=========================="
echo ""

# Check container status
echo "Container Status:"
ssh $VPS_HOST "docker ps --filter name=oauth --filter name=traefik --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo ""

# Check OAuth logs for errors
echo "Recent OAuth Errors (if any):"
ssh $VPS_HOST "docker logs oauth --tail 50 2>&1 | grep -i 'error\|fail\|fatal' || echo 'No errors found'"
echo ""

# Check Traefik logs for OAuth middleware errors
echo "Recent Traefik Errors (if any):"
ssh $VPS_HOST "docker logs traefik --tail 50 2>&1 | grep -i 'oauth.*error\|middleware.*error' || echo 'No OAuth middleware errors found'"
echo ""

echo "Health Check Complete"
