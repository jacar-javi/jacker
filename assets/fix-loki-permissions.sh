#!/bin/bash
# Fix Loki permission errors by creating missing directories
# Solves: "mkdir /loki/chunks: permission denied" error

set -e

# Get the script's directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine Jacker root directory
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi

cd "$JACKER_DIR"

echo "=== Fixing Loki Permissions ==="
echo ""

# Check if Loki data directory exists
if [ ! -d "data/loki" ]; then
    echo "❌ Loki data directory not found: $JACKER_DIR/data/loki"
    echo "   Is this a Jacker installation?"
    exit 1
fi

echo "Creating missing Loki directories..."

# Create all required Loki directories
mkdir -p data/loki/data/rules
mkdir -p data/loki/data/chunks
mkdir -p data/loki/data/compactor

# Set proper permissions (Loki runs as UID 10001)
chmod -R 777 data/loki/data

echo "✓ Created directories:"
echo "  - data/loki/data/rules"
echo "  - data/loki/data/chunks"
echo "  - data/loki/data/compactor"
echo ""
echo "✓ Set permissions to 777 (required for Loki UID 10001)"
echo ""

# Show current structure
echo "Current Loki directory structure:"
ls -la data/loki/data/
echo ""

# Restart Loki if Docker is available
if command -v docker &> /dev/null && [ -f "Makefile" ]; then
    echo "Restarting Loki service..."
    make restart service=loki 2>&1 || true

    echo ""
    echo "Waiting for Loki to start..."
    sleep 3

    echo ""
    echo "Checking Loki status..."
    make ps 2>&1 | grep loki || true
    echo ""
else
    echo "⚠️  Docker not available - please restart Loki manually:"
    echo "   make restart service=loki"
    echo "   or"
    echo "   docker compose restart loki"
    echo ""
fi

echo "=== Fix Complete ==="
echo ""
echo "Loki should now start without permission errors."
echo ""
echo "To verify:"
echo "  make logs service=loki"
echo ""
