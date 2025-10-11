#!/usr/bin/env bash
#
# Script: backup.sh
# Description: Backup Jacker configuration and critical data
# Usage: ./backup.sh [backup_directory]
# Requirements: .env file must exist
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Default backup directory
BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="jacker-backup-${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"

echo "=== Jacker Backup Utility ==="
echo ""
echo "Backup will be created at: ${BACKUP_PATH}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

# shellcheck source=/dev/null
source .env

# Create backup directory
mkdir -p "${BACKUP_PATH}"

echo "Creating backup: ${BACKUP_NAME}"
echo ""

# Backup .env file
echo "Backing up configuration files..."
cp .env "${BACKUP_PATH}/.env" 2>/dev/null || echo "WARNING: Could not backup .env"
cp .env.defaults "${BACKUP_PATH}/.env.defaults" 2>/dev/null || echo "WARNING: Could not backup .env.defaults"

# Backup docker-compose.yml
cp docker-compose.yml "${BACKUP_PATH}/docker-compose.yml" 2>/dev/null || echo "WARNING: Could not backup docker-compose.yml"

# Backup compose directory
echo "Backing up compose configurations..."
mkdir -p "${BACKUP_PATH}/compose"
cp -r compose/* "${BACKUP_PATH}/compose/" 2>/dev/null || echo "WARNING: Could not backup compose directory"

# Backup Traefik configuration
echo "Backing up Traefik configuration..."
mkdir -p "${BACKUP_PATH}/data/traefik"
if [ -d data/traefik ]; then
    cp -r data/traefik/rules "${BACKUP_PATH}/data/traefik/" 2>/dev/null || true
    cp data/traefik/traefik.yml "${BACKUP_PATH}/data/traefik/" 2>/dev/null || true
    cp data/traefik/acme.json "${BACKUP_PATH}/data/traefik/" 2>/dev/null || true
fi

# Backup CrowdSec configuration
echo "Backing up CrowdSec configuration..."
mkdir -p "${BACKUP_PATH}/data/crowdsec"
if [ -d data/crowdsec/config ]; then
    sudo cp -r data/crowdsec/config "${BACKUP_PATH}/data/crowdsec/" 2>/dev/null || echo "WARNING: Could not backup CrowdSec config"
fi

# Backup secrets
echo "Backing up secrets..."
mkdir -p "${BACKUP_PATH}/secrets"
if [ -d secrets ]; then
    cp -r secrets/* "${BACKUP_PATH}/secrets/" 2>/dev/null || echo "WARNING: Could not backup secrets"
fi

# Backup Grafana dashboards and datasources
echo "Backing up Grafana configuration..."
mkdir -p "${BACKUP_PATH}/data/grafana"
if [ -d data/grafana/provisioning ]; then
    cp -r data/grafana/provisioning "${BACKUP_PATH}/data/grafana/" 2>/dev/null || true
fi

# Backup Prometheus configuration
echo "Backing up Prometheus configuration..."
mkdir -p "${BACKUP_PATH}/data/prometheus"
if [ -d data/prometheus/config ]; then
    cp -r data/prometheus/config "${BACKUP_PATH}/data/prometheus/" 2>/dev/null || true
fi

# Backup Homepage configuration
echo "Backing up Homepage configuration..."
mkdir -p "${BACKUP_PATH}/data/homepage"
if [ -d data/homepage ]; then
    cp data/homepage/*.yaml "${BACKUP_PATH}/data/homepage/" 2>/dev/null || true
fi

# Export Docker volumes list
echo "Exporting Docker volumes list..."
docker volume ls > "${BACKUP_PATH}/docker-volumes.txt" 2>/dev/null || true

# Export running containers
echo "Exporting running containers list..."
docker ps -a > "${BACKUP_PATH}/docker-containers.txt" 2>/dev/null || true

# Export CrowdSec decisions (if running)
echo "Exporting CrowdSec decisions..."
if command -v cscli &> /dev/null && docker ps | grep -q crowdsec; then
    cscli decisions list -o json > "${BACKUP_PATH}/crowdsec-decisions.json" 2>/dev/null || true
    cscli bouncers list -o json > "${BACKUP_PATH}/crowdsec-bouncers.json" 2>/dev/null || true
fi

# Create backup manifest
echo "Creating backup manifest..."
cat > "${BACKUP_PATH}/MANIFEST.txt" << EOF
Jacker Backup Manifest
========================
Backup Date: $(date)
Hostname: ${HOSTNAME:-unknown}
Domain: ${DOMAINNAME:-unknown}
Public FQDN: ${PUBLIC_FQDN:-unknown}

Backed up components:
- Configuration files (.env, docker-compose.yml)
- Compose service definitions
- Traefik configuration and SSL certificates
- CrowdSec configuration
- Grafana provisioning
- Prometheus configuration
- Homepage configuration
- Docker secrets
- CrowdSec decisions and bouncers

Backup location: ${BACKUP_PATH}
EOF

# Create checksum file
echo "Creating checksums..."
find "${BACKUP_PATH}" -type f -exec sha256sum {} \; > "${BACKUP_PATH}/checksums.sha256" 2>/dev/null || true

# Fix permissions
echo "Setting permissions..."
chmod -R 600 "${BACKUP_PATH}/secrets" 2>/dev/null || true
chmod 600 "${BACKUP_PATH}/.env" 2>/dev/null || true

# Create compressed archive
echo "Compressing backup..."
tar -czf "${BACKUP_PATH}.tar.gz" -C "${BACKUP_DIR}" "${BACKUP_NAME}" 2>/dev/null || {
    echo "WARNING: Could not create compressed archive"
}

# Calculate backup size
if [ -f "${BACKUP_PATH}.tar.gz" ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_PATH}.tar.gz" | cut -f1)
    echo ""
    echo "=== Backup Complete ==="
    echo "Backup archive: ${BACKUP_PATH}.tar.gz"
    echo "Archive size: ${BACKUP_SIZE}"
    echo "Uncompressed backup: ${BACKUP_PATH}"
    echo ""
    echo "To restore this backup, extract the archive and review the MANIFEST.txt file"
else
    echo ""
    echo "=== Backup Complete ==="
    echo "Backup location: ${BACKUP_PATH}"
    echo ""
fi

echo "Backup completed successfully!"
