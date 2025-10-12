#!/bin/bash
BACKUP_DIR="backup"
BACKUP_NAME="test-backup"

mkdir -p "${BACKUP_DIR}/${BACKUP_NAME}/config"
cp .env "${BACKUP_DIR}/${BACKUP_NAME}/config/"
cp -r data "${BACKUP_DIR}/${BACKUP_NAME}/"

cd "${BACKUP_DIR}" || exit 1
tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"
rm -rf "${BACKUP_NAME}"

echo "Backup created: ${BACKUP_NAME}.tar.gz"
