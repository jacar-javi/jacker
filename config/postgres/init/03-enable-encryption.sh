#!/bin/bash
set -e

echo "=== Enabling PostgreSQL Encryption Extensions ==="

# Enable pgcrypto for column-level encryption
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL

echo "✓ Encryption extensions enabled"
