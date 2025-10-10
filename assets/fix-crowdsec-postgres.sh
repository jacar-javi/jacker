#!/usr/bin/env bash
#
# Fix CrowdSec to use PostgreSQL instead of MySQL
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  CrowdSec PostgreSQL Migration"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

source .env

echo "Step 1: Stopping CrowdSec container..."
docker stop crowdsec 2>/dev/null || true
docker rm crowdsec 2>/dev/null || true
echo "✓ Container stopped and removed"
echo ""

echo "Step 2: Cleaning old CrowdSec data..."
# Keep config, remove data to force re-initialization
rm -rf data/crowdsec/data
mkdir -p data/crowdsec/data
echo "✓ Old data cleared"
echo ""

echo "Step 3: Ensuring PostgreSQL config is correct..."
mkdir -p data/crowdsec/config
envsubst < assets/templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
echo "✓ PostgreSQL config generated"
echo ""
cat data/crowdsec/config/config.yaml.local
echo ""

echo "Step 4: Ensuring CrowdSec database exists in PostgreSQL..."
# Connect to the default 'postgres' database to create crowdsec_db if needed
docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres <<EOF 2>/dev/null || true
-- Create crowdsec_db if it doesn't exist
SELECT 'CREATE DATABASE crowdsec_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'crowdsec_db')\gexec
EOF

# Now connect to crowdsec_db to set permissions
docker exec -i postgres psql -U "$POSTGRES_USER" -d crowdsec_db <<EOF 2>/dev/null || true
-- Grant all privileges on schema
GRANT ALL ON SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $POSTGRES_USER;
EOF

echo "✓ Database created/verified with proper permissions"
echo ""

echo "Step 5: Starting CrowdSec with clean state..."
docker compose up -d crowdsec
echo "✓ CrowdSec started"
echo ""

echo "Step 6: Waiting for CrowdSec to initialize (30 seconds)..."
sleep 30
echo ""

echo "Step 7: Checking CrowdSec status..."
docker logs crowdsec --tail 20
echo ""

echo "=========================================="
echo "  CrowdSec Migration Complete!"
echo "=========================================="
echo ""
echo "Check status with:"
echo "  docker logs crowdsec"
echo "  docker exec crowdsec cscli metrics"
echo ""
