#!/bin/sh
# Traefik initialization script to inject secrets into dynamic configuration
# This script reads passwords from Docker secrets and generates configuration files

set -e

echo "=== Traefik Secrets Initialization ==="

# Check if redis_ratelimit_password secret exists
if [ -f "/run/secrets/redis_ratelimit_password" ]; then
    REDIS_RATELIMIT_PASSWORD=$(cat /run/secrets/redis_ratelimit_password)
    echo "✓ Redis rate limit password loaded from secret"

    # Generate middlewares-rate-limit.yml from template
    if [ -f "/rules/middlewares-rate-limit.yml.template" ]; then
        sed "s|REDIS_RATELIMIT_PASSWORD_PLACEHOLDER|${REDIS_RATELIMIT_PASSWORD}|g" \
            /rules/middlewares-rate-limit.yml.template > /rules/middlewares-rate-limit.yml
        echo "✓ Generated /rules/middlewares-rate-limit.yml from template"
    else
        echo "⚠ Template file not found: /rules/middlewares-rate-limit.yml.template"
    fi
else
    echo "⚠ Redis rate limit password secret not found, skipping middleware generation"
fi

# Set proper permissions
chmod 644 /rules/*.yml 2>/dev/null || true

echo "=== Initialization Complete ==="
echo ""

# Execute the main Traefik command
exec "$@"
