#!/bin/bash
# Fix Jaeger volume permissions
# This script ensures the Jaeger data directories have correct ownership

set -euo pipefail

# Load environment variables
if [ -f "$(dirname "$0")/../.env" ]; then
    source "$(dirname "$0")/../.env"
fi

DATADIR="${DATADIR:-/home/testuser/docker/data}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo "Fixing Jaeger permissions..."
echo "DATADIR: $DATADIR"
echo "PUID: $PUID"
echo "PGID: $PGID"

# Create directories if they don't exist
mkdir -p "$DATADIR/jaeger/badger/data"
mkdir -p "$DATADIR/jaeger/badger/key"
mkdir -p "$DATADIR/jaeger/tmp"

# Set ownership
chown -R "$PUID:$PGID" "$DATADIR/jaeger"

# Set permissions (rwx for user, rx for group and others)
chmod -R 755 "$DATADIR/jaeger"

# Verify
echo ""
echo "Verification:"
ls -la "$DATADIR/jaeger/"
echo ""
ls -la "$DATADIR/jaeger/badger/" 2>/dev/null || echo "Badger subdirectories will be created by Jaeger"

echo ""
echo "✓ Jaeger permissions fixed!"
echo ""
echo "ALTERNATIVE: For better performance, use ephemeral tmpfs storage (recommended):"
echo "1. Edit compose/jaeger.yml"
echo "2. Comment out the volume line: - \$DATADIR/jaeger/badger:/badger"
echo "3. Uncomment the tmpfs section"
echo ""
echo "tmpfs provides:"
echo "  - Faster I/O (in-memory)"
echo "  - No permission issues"
echo "  - Automatic cleanup on restart"
echo "  - Suitable for traces (typically don't need long-term persistence)"
