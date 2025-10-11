#!/bin/bash
source "${LIB_DIR}/common.sh"

# Backup database
BACKUP_FILE="backup/postgres_$(date +%Y%m%d_%H%M%S).sql"
ensure_dir "backup"

docker exec postgres pg_dump -U postgres postgres > "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    echo "Backup created successfully"

    # Test restore
    docker exec -i postgres pg_restore -U postgres -d postgres_restore < "$BACKUP_FILE"
    echo "Restore completed"
else
    echo "Backup failed"
    exit 1
fi
