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

source .env

# Create database and user for CrowdSec
echo "Creating CrowdSec database and user..."

docker exec -i postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<EOF
-- Create crowdsec database if it doesn't exist
SELECT 'CREATE DATABASE crowdsec_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'crowdsec_db')\gexec

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE crowdsec_db TO $POSTGRES_USER;

\c crowdsec_db

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
