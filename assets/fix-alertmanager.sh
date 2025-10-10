#!/usr/bin/env bash
#
# Fix Alertmanager configuration and permissions
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  Alertmanager Configuration Fix"
echo "=========================================="
echo ""

# Export all variables from .env
set -a
source .env
set +a

echo "Step 1: Generating alertmanager.yml from template..."
mkdir -p data/alertmanager
envsubst < assets/templates/alertmanager.yml.template > data/alertmanager/alertmanager.yml
echo "  ✓ Configuration generated"
echo ""

echo "Generated config snippet (line 86):"
sed -n '84,88p' data/alertmanager/alertmanager.yml
echo ""

echo "Step 2: Fixing data directory permissions..."
sudo chown -R 65534:65534 data/alertmanager 2>/dev/null || chown -R 65534:65534 data/alertmanager
echo "  ✓ Permissions fixed (owner: nobody:nogroup / 65534:65534)"
echo ""

echo "Step 3: Restarting alertmanager..."
docker restart alertmanager
echo "  Waiting for alertmanager to start (10 seconds)..."
sleep 10
echo ""

echo "Step 4: Checking alertmanager status..."
docker logs alertmanager --tail 20
echo ""

echo "=========================================="
echo "  Fix Complete!"
echo "=========================================="
echo ""
echo "Check status with:"
echo "  docker logs alertmanager"
echo "  curl -s http://localhost:9093/-/healthy"
echo ""
