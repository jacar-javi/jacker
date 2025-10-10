#!/usr/bin/env bash
#
# Fix PostgreSQL and CrowdSec connection issues
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  PostgreSQL & CrowdSec Connection Fix"
echo "=========================================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

source .env

echo "Step 1: Ensuring PostgreSQL is configured to listen on all interfaces..."
if ! grep -q "^listen_addresses = '\*'" data/postgres/postgresql.conf 2>/dev/null; then
    echo "  Adding listen_addresses configuration..."
    sed -i "/^# CONNECTIONS AND AUTHENTICATION/a listen_addresses = '*'                   # Listen on all interfaces (required for Docker networking)" data/postgres/postgresql.conf
    echo "  ✓ Configuration added"
else
    echo "  ✓ Already configured"
fi
echo ""

echo "Step 2: Restarting PostgreSQL to apply changes..."
docker restart postgres
echo "  Waiting for PostgreSQL to be ready..."
sleep 10

# Wait for PostgreSQL to be healthy
timeout=60
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if docker exec postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
        echo "  ✓ PostgreSQL is ready"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $timeout ]; then
    echo "  ✗ PostgreSQL failed to become ready"
    exit 1
fi
echo ""

echo "Step 3: Ensuring crowdsec_db database exists..."
# Connect to postgres database to create crowdsec_db
docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres <<EOF 2>/dev/null || true
SELECT 'CREATE DATABASE crowdsec_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'crowdsec_db')\gexec
EOF

# Grant permissions
docker exec -i postgres psql -U "$POSTGRES_USER" -d crowdsec_db <<EOF 2>/dev/null || true
GRANT ALL ON SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $POSTGRES_USER;
EOF

echo "  ✓ Database verified"
echo ""

echo "Step 4: Regenerating CrowdSec configuration..."
mkdir -p data/crowdsec/config
envsubst < assets/templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
echo "  ✓ Configuration regenerated"
echo ""
cat data/crowdsec/config/config.yaml.local
echo ""

echo "Step 5: Stopping CrowdSec..."
docker stop crowdsec 2>/dev/null || true
docker rm crowdsec 2>/dev/null || true
echo "  ✓ Stopped"
echo ""

echo "Step 6: Cleaning CrowdSec data (keeping config)..."
sudo rm -rf data/crowdsec/data
mkdir -p data/crowdsec/data
echo "  ✓ Data cleared"
echo ""

echo "Step 7: Starting CrowdSec with fresh state..."
docker compose up -d crowdsec
echo "  ✓ Started"
echo ""

echo "Step 8: Waiting for CrowdSec to initialize (45 seconds)..."
sleep 45
echo ""

echo "Step 9: Checking CrowdSec status..."
docker logs crowdsec --tail 30
echo ""

echo "=========================================="
echo "  Fix Complete!"
echo "=========================================="
echo ""
echo "Check CrowdSec status with:"
echo "  docker logs crowdsec"
echo "  docker exec crowdsec cscli metrics"
echo ""
