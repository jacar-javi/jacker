#!/bin/bash
set -e

echo "=== Creating Limited PostgreSQL Users ==="

# Grafana user (read/write to grafana_db only)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER grafana_user WITH PASSWORD '${GF_DATABASE_PASSWORD:-changeme}';
    GRANT CONNECT ON DATABASE grafana_db TO grafana_user;
    \c grafana_db
    GRANT USAGE ON SCHEMA public TO grafana_user;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO grafana_user;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO grafana_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO grafana_user;
EOSQL

# CrowdSec user (read/write to crowdsec_db only)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER crowdsec_user WITH PASSWORD '${CROWDSEC_DB_PASSWORD:-changeme}';
    GRANT CONNECT ON DATABASE crowdsec_db TO crowdsec_user;
    \c crowdsec_db
    GRANT USAGE ON SCHEMA public TO crowdsec_user;
    GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO crowdsec_user;
    GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO crowdsec_user;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO crowdsec_user;
EOSQL

# Read-only monitoring user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE USER postgres_exporter_user WITH PASSWORD '${POSTGRES_EXPORTER_PASSWORD:-changeme}';
    GRANT CONNECT ON DATABASE postgres TO postgres_exporter_user;
    GRANT pg_monitor TO postgres_exporter_user;
EOSQL

echo "✓ Limited PostgreSQL users created"
