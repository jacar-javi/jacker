#!/bin/sh
# Redis ACL initialization script to inject passwords from Docker secrets
# This script reads passwords from Docker secrets and generates the ACL file

set -e

echo "=== Redis ACL Initialization ==="

# Ensure the directory exists
mkdir -p /usr/local/etc/redis

# Read passwords from secrets
DEFAULT_PASSWORD=$(cat /run/secrets/redis_password 2>/dev/null || echo "")
RATELIMIT_PASSWORD=$(cat /run/secrets/redis_ratelimit_password 2>/dev/null || echo "")
OAUTH_PASSWORD=$(cat /run/secrets/redis_oauth_password 2>/dev/null || echo "changeme")
EXPORTER_PASSWORD=$(cat /run/secrets/redis_exporter_password 2>/dev/null || echo "changeme")

if [ -z "$DEFAULT_PASSWORD" ] || [ -z "$RATELIMIT_PASSWORD" ]; then
    echo "ERROR: Required secrets not found!"
    exit 1
fi

echo "✓ Passwords loaded from secrets"

# Generate ACL file from template
# Note: OAuth user needs renamed commands for session management
cat > /usr/local/etc/redis/users.acl << EOF
user default on >${DEFAULT_PASSWORD} +@all ~* &*
user oauth_user on >${OAUTH_PASSWORD} -@all +@read +@write +@string +@hash +@keyspace +@connection +eval +evalsha +script +DEL_b6c7d8e9f1a2 +EXPIRE_a2b3c4d5e6f7 +PEXPIRE_f7e6d5c4b3a2 +TTL_d9e8f7a6b5c4 +PTTL_c4b5a6f7e8d9 ~* resetchannels
user ratelimit_user on >${RATELIMIT_PASSWORD} -@all +@read +@write +@string +@keyspace +@connection +select +eval +evalsha +script +DEL_b6c7d8e9f1a2 +EXPIRE_a2b3c4d5e6f7 +TTL_d9e8f7a6b5c4 ~* resetchannels
user exporter_user on >${EXPORTER_PASSWORD} -@all +@read +@keyspace +@connection +info +config|get ~* resetchannels
EOF

chmod 644 /usr/local/etc/redis/users.acl
echo "✓ Generated /usr/local/etc/redis/users.acl"

# Verify the ACL file was created successfully
if [ ! -f /usr/local/etc/redis/users.acl ]; then
    echo "ERROR: ACL file was not created!"
    exit 1
fi

echo "=== ACL Initialization Complete ==="
echo ""

# Execute redis-server with the provided arguments and ACL file
exec redis-server "$@" --aclfile /usr/local/etc/redis/users.acl
