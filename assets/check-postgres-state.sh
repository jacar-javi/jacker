#!/usr/bin/env bash
#
# Check PostgreSQL current state
#

set -euo pipefail

cd "$(dirname "$0")/.."

echo "=========================================="
echo "  PostgreSQL Current State Check"
echo "=========================================="
echo ""

# Load current .env
source .env

echo "Current .env settings:"
echo "  POSTGRES_DB=$POSTGRES_DB"
echo "  POSTGRES_USER=$POSTGRES_USER"
echo ""

echo "Databases in PostgreSQL:"
docker exec postgres psql -U postgres -c "\l" | grep -E "Name|------|crowdsec|jacker" || echo "No matching databases"
echo ""

echo "Users in PostgreSQL:"
docker exec postgres psql -U postgres -c "\du" | grep -E "Role name|---------|crowdsec|jacker" || echo "No matching users"
echo ""

echo "Trying to connect with crowdsec user:"
if docker exec postgres psql -U crowdsec -d crowdsec_db -c "SELECT version();" 2>&1 | grep -q "PostgreSQL"; then
    echo "  ✓ User 'crowdsec' can connect to crowdsec_db"
else
    echo "  ✗ User 'crowdsec' cannot connect"
fi
echo ""

echo "Trying to connect with jacker user:"
if docker exec postgres psql -U jacker -d crowdsec_db -c "SELECT version();" 2>&1 | grep -q "PostgreSQL"; then
    echo "  ✓ User 'jacker' can connect to crowdsec_db"
else
    echo "  ✗ User 'jacker' cannot connect"
fi
echo ""
