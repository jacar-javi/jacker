#!/usr/bin/env bash
#
# Script: restore.sh
# Description: Restore Jacker configuration from backup
# Usage: ./restore.sh <backup_path>
# Example: ./restore.sh ./backups/jacker-backup-20240101-120000
#          ./restore.sh ./backups/jacker-backup-20240101-120000.tar.gz
#

set -euo pipefail

cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if backup path provided
if [ $# -eq 0 ]; then
    echo -e "${RED}ERROR: No backup path specified${NC}"
    echo ""
    echo "Usage: $0 <backup_path>"
    echo ""
    echo "Examples:"
    echo "  $0 ./backups/jacker-backup-20240101-120000"
    echo "  $0 ./backups/jacker-backup-20240101-120000.tar.gz"
    echo ""
    exit 1
fi

BACKUP_SOURCE="$1"

echo -e "${BLUE}=== Jacker Restore Utility ===${NC}"
echo ""

# Check if backup exists
if [ ! -e "$BACKUP_SOURCE" ]; then
    echo -e "${RED}ERROR: Backup not found: $BACKUP_SOURCE${NC}"
    exit 1
fi

# Determine backup type (archive or directory)
BACKUP_DIR=""
CLEANUP_TEMP=false

if [ -f "$BACKUP_SOURCE" ]; then
    # It's a compressed archive
    echo "Detected compressed backup archive"

    # Verify it's a valid tar.gz
    if ! tar -tzf "$BACKUP_SOURCE" &> /dev/null; then
        echo -e "${RED}ERROR: Invalid or corrupted backup archive${NC}"
        exit 1
    fi

    # Extract to temporary directory
    TEMP_DIR=$(mktemp -d)
    CLEANUP_TEMP=true

    echo "Extracting backup to temporary directory..."
    tar -xzf "$BACKUP_SOURCE" -C "$TEMP_DIR"

    # Find the backup directory inside
    BACKUP_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "jacker-backup-*" | head -1)

    if [ -z "$BACKUP_DIR" ]; then
        echo -e "${RED}ERROR: No backup directory found in archive${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
elif [ -d "$BACKUP_SOURCE" ]; then
    # It's already a directory
    BACKUP_DIR="$BACKUP_SOURCE"
    echo "Using backup directory: $BACKUP_DIR"
else
    echo -e "${RED}ERROR: Invalid backup source${NC}"
    exit 1
fi

# Verify backup structure
echo "Verifying backup structure..."

if [ ! -f "$BACKUP_DIR/MANIFEST.txt" ]; then
    echo -e "${YELLOW}WARNING: MANIFEST.txt not found${NC}"
else
    echo ""
    echo -e "${BLUE}Backup Manifest:${NC}"
    head -10 "$BACKUP_DIR/MANIFEST.txt"
    echo ""
fi

# Verify checksums if available
if [ -f "$BACKUP_DIR/checksums.sha256" ]; then
    echo "Verifying backup integrity..."
    cd "$BACKUP_DIR"
    if sha256sum -c checksums.sha256 &> /dev/null; then
        echo -e "${GREEN}✓ Backup integrity verified${NC}"
    else
        echo -e "${YELLOW}⚠ Checksum verification failed (some files may have changed)${NC}"
        read -r -p "Continue anyway? [y/N] " response
        case $response in
            [yY][eE][sS]|[yY])
                echo "Continuing..."
            ;;
            *)
                [ "$CLEANUP_TEMP" = true ] && rm -rf "$TEMP_DIR"
                exit 1
            ;;
        esac
    fi
    cd - > /dev/null
fi

echo ""
echo -e "${YELLOW}WARNING: This will restore configuration from backup!${NC}"
echo -e "${YELLOW}Current configuration will be backed up to .env.pre-restore${NC}"
echo ""
read -r -p "Do you want to continue? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        echo "Proceeding with restore..."
    ;;
    *)
        echo "Restore cancelled."
        [ "$CLEANUP_TEMP" = true ] && rm -rf "$TEMP_DIR"
        exit 0
    ;;
esac

echo ""
echo -e "${BLUE}=== Starting Restore Process ===${NC}"
echo ""

# Stop services if running
echo "Stopping services..."
if [ -f .env ]; then
    docker compose down &> /dev/null || true
fi

# Backup current configuration
if [ -f .env ]; then
    echo "Backing up current .env to .env.pre-restore..."
    cp .env .env.pre-restore
fi

# Restore configuration files
echo "Restoring configuration files..."

if [ -f "$BACKUP_DIR/.env" ]; then
    cp "$BACKUP_DIR/.env" .env
    chmod 600 .env
    echo "  ✓ Restored .env"
else
    echo -e "  ${YELLOW}⚠ .env not found in backup${NC}"
fi

if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
    echo "  ✓ Restored docker-compose.yml"
fi

# Restore compose directory
if [ -d "$BACKUP_DIR/compose" ]; then
    echo "Restoring compose configurations..."
    cp -r "$BACKUP_DIR/compose/"* compose/ 2>/dev/null || true
    echo "  ✓ Restored compose directory"
fi

# Restore Traefik configuration
if [ -d "$BACKUP_DIR/data/traefik" ]; then
    echo "Restoring Traefik configuration..."
    mkdir -p data/traefik

    if [ -d "$BACKUP_DIR/data/traefik/rules" ]; then
        cp -r "$BACKUP_DIR/data/traefik/rules" data/traefik/ 2>/dev/null || true
        echo "  ✓ Restored Traefik rules"
    fi

    if [ -f "$BACKUP_DIR/data/traefik/traefik.yml" ]; then
        cp "$BACKUP_DIR/data/traefik/traefik.yml" data/traefik/
        echo "  ✓ Restored traefik.yml"
    fi

    if [ -f "$BACKUP_DIR/data/traefik/acme.json" ]; then
        cp "$BACKUP_DIR/data/traefik/acme.json" data/traefik/
        chmod 600 data/traefik/acme.json
        echo "  ✓ Restored SSL certificates"
    fi
fi

# Restore CrowdSec configuration
if [ -d "$BACKUP_DIR/data/crowdsec/config" ]; then
    echo "Restoring CrowdSec configuration..."
    mkdir -p data/crowdsec
    sudo cp -r "$BACKUP_DIR/data/crowdsec/config" data/crowdsec/ 2>/dev/null || true
    echo "  ✓ Restored CrowdSec config"
fi

# Restore secrets
if [ -d "$BACKUP_DIR/secrets" ]; then
    echo "Restoring secrets..."
    mkdir -p secrets
    cp -r "$BACKUP_DIR/secrets/"* secrets/ 2>/dev/null || true
    chmod -R 600 secrets/* 2>/dev/null || true
    echo "  ✓ Restored secrets"
fi

# Restore Grafana provisioning
if [ -d "$BACKUP_DIR/data/grafana/provisioning" ]; then
    echo "Restoring Grafana provisioning..."
    mkdir -p data/grafana
    cp -r "$BACKUP_DIR/data/grafana/provisioning" data/grafana/ 2>/dev/null || true
    echo "  ✓ Restored Grafana provisioning"
fi

# Restore Prometheus configuration
if [ -d "$BACKUP_DIR/data/prometheus/config" ]; then
    echo "Restoring Prometheus configuration..."
    mkdir -p data/prometheus
    cp -r "$BACKUP_DIR/data/prometheus/config" data/prometheus/ 2>/dev/null || true
    echo "  ✓ Restored Prometheus config"
fi

# Restore Homepage configuration
if [ -d "$BACKUP_DIR/data/homepage" ]; then
    echo "Restoring Homepage configuration..."
    mkdir -p data/homepage
    cp "$BACKUP_DIR/data/homepage/"*.yaml data/homepage/ 2>/dev/null || true
    echo "  ✓ Restored Homepage config"
fi

# Cleanup
if [ "$CLEANUP_TEMP" = true ]; then
    echo "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
fi

echo ""
echo -e "${GREEN}=== Restore Complete ===${NC}"
echo ""
echo "Configuration has been restored from backup."
echo ""
echo "Next steps:"
echo "1. Review the restored .env file: vim .env"
echo "2. Validate the configuration: ./validate.sh"
echo "3. Start the services: docker compose up -d"
echo "4. Check service health: ./health-check.sh"
echo ""
echo "If you need to revert to your previous configuration:"
echo "  cp .env.pre-restore .env"
echo ""
