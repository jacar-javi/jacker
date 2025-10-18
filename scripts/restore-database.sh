#!/bin/bash
# PostgreSQL Database Restore Script

set -euo pipefail

# Load environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_ROOT/.env"

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup-file.sql.gz>"
    echo "Available backups:"
    ls -lh "${DATADIR}/backups/postgres/" 2>/dev/null || echo "No backups found"
    exit 1
fi

BACKUP_FILE="$1"

# Verify backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  WARNING: This will restore database from backup!"
echo "Backup file: $BACKUP_FILE"
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo "=== Stopping services..."
docker compose stop grafana crowdsec

echo "=== Restoring database..."
gunzip -c "$BACKUP_FILE" | docker exec -i postgres psql -U postgres

echo "=== Starting services..."
docker compose start grafana crowdsec

echo "✓ Database restored successfully"
