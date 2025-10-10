#!/usr/bin/env bash
#
# Fix Loki configuration
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  Loki Configuration Fix"
echo "=========================================="
echo ""

echo "Step 1: Copying fixed Loki configuration..."
mkdir -p data/loki
cp assets/templates/loki-config.yml.template data/loki/loki-config.yml
echo "  ✓ Configuration updated"
echo ""

echo "Step 2: Fixing data directory permissions..."
sudo chown -R 10001:10001 data/loki 2>/dev/null || chown -R 10001:10001 data/loki
echo "  ✓ Permissions fixed (owner: loki:loki / 10001:10001)"
echo ""

echo "Step 3: Restarting loki..."
docker restart loki
echo "  Waiting for loki to start (10 seconds)..."
sleep 10
echo ""

echo "Step 4: Checking loki status..."
docker logs loki --tail 20
echo ""

echo "=========================================="
echo "  Fix Complete!"
echo "=========================================="
echo ""
echo "Check status with:"
echo "  docker logs loki"
echo "  docker ps | grep loki"
echo ""
