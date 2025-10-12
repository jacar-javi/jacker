#!/bin/bash
BACKUP_FILE="backup/test-backup.tar.gz"
RESTORE_DIR="restored"

mkdir -p "${RESTORE_DIR}"
cd "${RESTORE_DIR}" || exit 1
tar xzf "../${BACKUP_FILE}"

if [ -f "test-backup/config/.env" ]; then
    cp test-backup/config/.env ../.env.restored
    echo "Restore complete"
else
    echo "Restore failed"
    exit 1
fi
