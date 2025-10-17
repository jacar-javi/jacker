#!/bin/sh
# Redis ACL initialization script to inject passwords from Docker secrets
# This script reads passwords from Docker secrets and generates the ACL file

set -e

echo "=== Redis ACL Initialization ==="

# Read passwords from secrets
DEFAULT_PASSWORD=$(cat /run/secrets/redis_password 2>/dev/null || echo "")
RATELIMIT_PASSWORD=$(cat /run/secrets/redis_ratelimit_password 2>/dev/null || echo "")

if [ -z "$DEFAULT_PASSWORD" ] || [ -z "$RATELIMIT_PASSWORD" ]; then
    echo "ERROR: Required secrets not found!"
    exit 1
fi

echo "✓ Passwords loaded from secrets"

# Generate ACL file from template
cat > /usr/local/etc/redis/users.acl << EOF
# ====================================================================
# Redis ACL Configuration (Auto-generated from Docker secrets)
# ====================================================================
# This file is generated at container startup from Docker secrets
# DO NOT EDIT - Changes will be overwritten on container restart
# ====================================================================

# ====================================================================
# Default User - Administrative Access
# ====================================================================
user default on >${DEFAULT_PASSWORD} +@all ~* &*

# ====================================================================
# OAuth2-Proxy User - Session Storage
# ====================================================================
user oauth_user on >\$(cat /run/secrets/redis_oauth_password) ~* +get +set +del +exists +expire +ttl +ping +scan +keys +info resetchannels -@all

# ====================================================================
# Rate Limiting User - Traefik Rate Limiter
# ====================================================================
user ratelimit_user on >${RATELIMIT_PASSWORD} ~* +@all -@dangerous +select resetchannels

# ====================================================================
# Monitoring User - Read-Only Access for Metrics
# ====================================================================
user exporter_user on >\$(cat /run/secrets/redis_exporter_password 2>/dev/null || echo "changeme") +@read +@keyspace +@connection +info +config|get ~* resetchannels -@all
EOF

chmod 644 /usr/local/etc/redis/users.acl
echo "✓ Generated /usr/local/etc/redis/users.acl"

echo "=== ACL Initialization Complete ==="
echo ""

# Execute redis-server with the provided arguments
exec redis-server "$@"
