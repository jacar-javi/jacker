#!/usr/bin/env bash
#
# Setup CrowdSec database in PostgreSQL
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Setting up CrowdSec Database in PostgreSQL ==="
echo ""

# Source environment variables
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

# Export all variables from .env for envsubst
set -a
source .env
set +a

# Create database for CrowdSec
echo "Creating CrowdSec database..."

# Connect to the default 'postgres' database to create crowdsec_db
docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres <<EOF
-- Create crowdsec_db if it doesn't exist
SELECT 'CREATE DATABASE crowdsec_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'crowdsec_db')\gexec
EOF

# Now connect to crowdsec_db to set permissions
docker exec -i postgres psql -U "$POSTGRES_USER" -d crowdsec_db <<EOF
-- Ensure proper permissions
GRANT ALL ON SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL TABLES IN SCHEMA public TO $POSTGRES_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $POSTGRES_USER;
EOF

if [ $? -eq 0 ]; then
    echo "✓ CrowdSec database created successfully"
else
    echo "✗ Failed to create CrowdSec database"
    exit 1
fi

echo ""
echo "=== Restarting CrowdSec ==="
docker restart crowdsec

echo ""
echo "✓ CrowdSec setup complete!"
echo "Check status with: docker logs crowdsec"
