#!/usr/bin/env bash
#
# Fix PostgreSQL password mismatch by recreating with correct credentials
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  PostgreSQL Password Mismatch Fix"
echo "=========================================="
echo ""

# Export all variables from .env
set -a
source .env
set +a

echo "Current .env credentials:"
echo "  POSTGRES_DB=$POSTGRES_DB"
echo "  POSTGRES_USER=$POSTGRES_USER"
echo "  POSTGRES_PASSWORD=$POSTGRES_PASSWORD"
echo ""

echo "This will recreate PostgreSQL with the correct credentials."
echo "⚠️  WARNING: This will delete all PostgreSQL data!"
echo ""
read -p "Continue? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi
echo ""

echo "Step 1: Stopping all services that depend on PostgreSQL..."
docker stop crowdsec 2>/dev/null || true
docker stop postgres 2>/dev/null || true
echo "  ✓ Services stopped"
echo ""

echo "Step 2: Removing PostgreSQL data..."
sudo rm -rf data/postgres/data
echo "  ✓ Data removed"
echo ""

echo "Step 3: Recreating PostgreSQL data directory..."
mkdir -p data/postgres/data
echo "  ✓ Directory created"
echo ""

echo "Step 4: Starting PostgreSQL with correct credentials..."
docker compose up -d postgres
echo "  Waiting for PostgreSQL to initialize (30 seconds)..."
sleep 30
echo ""

echo "Step 5: Verifying PostgreSQL is ready..."
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
    echo "  ✗ PostgreSQL failed to start"
    exit 1
fi
echo ""

echo "Step 6: Creating crowdsec_db database..."
docker exec -i postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<EOF
-- Create crowdsec_db if it doesn't exist
SELECT 'CREATE DATABASE crowdsec_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'crowdsec_db')\gexec
EOF

docker exec -i postgres psql -U "$POSTGRES_USER" -d crowdsec_db <<EOF
-- Grant all privileges
GRANT ALL ON SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $POSTGRES_USER;
EOF
echo "  ✓ Database created"
echo ""

echo "Step 7: Regenerating CrowdSec configuration..."
mkdir -p data/crowdsec/config
envsubst < assets/templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
echo "  ✓ Configuration generated"
echo ""

echo "Generated config:"
cat data/crowdsec/config/config.yaml.local
echo ""

echo "Step 8: Cleaning CrowdSec data..."
sudo rm -rf data/crowdsec/data
mkdir -p data/crowdsec/data
echo "  ✓ CrowdSec data cleaned"
echo ""

echo "Step 9: Starting CrowdSec..."
docker compose up -d crowdsec
echo "  Waiting for CrowdSec to initialize (45 seconds)..."
sleep 45
echo ""

echo "Step 10: Checking CrowdSec status..."
docker logs crowdsec --tail 30
echo ""

echo "=========================================="
echo "  Fix Complete!"
echo "=========================================="
echo ""
echo "Verify with:"
echo "  docker logs crowdsec | grep -i database"
echo "  docker exec crowdsec cscli metrics"
echo ""
