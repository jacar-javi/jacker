#!/usr/bin/env bash
#
# backup.sh - Backup module for Jacker
# Creates comprehensive backups of configuration and data
#

# Source common library
# shellcheck source=assets/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Default backup directory
DEFAULT_BACKUP_DIR="${HOME}/jacker-backups"

# ============================================================================
# Backup Functions
# ============================================================================

# Create backup
create_backup() {
    local backup_dir="${1:-$DEFAULT_BACKUP_DIR}"
    local timestamp="$(timestamp)"
    local backup_name="jacker-backup-${timestamp}"
    local backup_path="${backup_dir}/${backup_name}"

    section "Creating Backup"

    # Ensure backup directory exists
    ensure_dir "$backup_dir"
    ensure_dir "$backup_path"

    info "Backup location: ${backup_path}"

    # Check if services should be stopped
    if confirm_action "Stop services during backup for consistency?" "N"; then
        stop_services
        local services_stopped=true
    else
        warning "Backing up while services are running (may be inconsistent)"
        local services_stopped=false
    fi

    # Backup configuration files
    backup_configuration "$backup_path"

    # Backup Docker volumes
    backup_volumes "$backup_path"

    # Backup databases
    backup_databases "$backup_path"

    # Create metadata
    create_backup_metadata "$backup_path"

    # Compress backup
    compress_backup "$backup_dir" "$backup_name"

    # Cleanup temporary backup directory
    rm -rf "$backup_path"

    # Restart services if they were stopped
    if [ "$services_stopped" = true ]; then
        start_services
    fi

    success "Backup completed: ${backup_dir}/${backup_name}.tar.gz"

    # Show backup size
    local backup_size=$(du -h "${backup_dir}/${backup_name}.tar.gz" | cut -f1)
    info "Backup size: $backup_size"

    # Cleanup old backups
    cleanup_old_backups "$backup_dir"
}

# Backup configuration files
backup_configuration() {
    local backup_path="$1"

    subsection "Backing up configuration"

    # Create config backup directory
    mkdir -p "${backup_path}/config"

    # Backup main configuration files
    local config_files=(
        ".env"
        "docker-compose.yml"
        ".env.defaults"
        ".env.template"
    )

    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "${backup_path}/config/" 2>/dev/null || true
            success "Backed up: $file"
        fi
    done

    # Backup compose directory
    if [ -d "compose" ]; then
        cp -r "compose" "${backup_path}/config/" 2>/dev/null || true
        success "Backed up: compose directory"
    fi

    # Backup data configurations
    local data_configs=(
        "data/traefik"
        "data/crowdsec/config"
        "data/prometheus"
        "data/grafana/provisioning"
        "data/alertmanager"
        "data/loki/*.yml"
    )

    mkdir -p "${backup_path}/data-configs"
    for path in "${data_configs[@]}"; do
        if [ -e "$path" ]; then
            # Create parent directory structure
            local parent_dir=$(dirname "$path")
            mkdir -p "${backup_path}/data-configs/${parent_dir}"
            cp -r "$path" "${backup_path}/data-configs/${parent_dir}/" 2>/dev/null || true
            success "Backed up: $path"
        fi
    done

    # Backup secrets (encrypted)
    if [ -d "secrets" ]; then
        tar czf "${backup_path}/secrets.tar.gz.enc" secrets/ 2>/dev/null || true
        success "Backed up: secrets (encrypted)"
    fi
}

# Backup Docker volumes
backup_volumes() {
    local backup_path="$1"

    subsection "Backing up Docker volumes"

    mkdir -p "${backup_path}/volumes"

    # Get list of Jacker volumes
    local volumes=$(docker volume ls -q | grep "^jacker" || true)

    if [ -z "$volumes" ]; then
        warning "No Jacker volumes found"
        return
    fi

    for volume in $volumes; do
        info "Backing up volume: $volume"

        # Use a temporary container to backup the volume
        docker run --rm \
            -v "${volume}:/source:ro" \
            -v "${backup_path}/volumes:/backup" \
            alpine \
            tar czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null || {
                warning "Failed to backup volume: $volume"
                continue
            }

        success "Backed up volume: $volume"
    done
}

# Backup databases
backup_databases() {
    local backup_path="$1"

    subsection "Backing up databases"

    mkdir -p "${backup_path}/databases"

    # Backup PostgreSQL
    if is_container_running "postgres"; then
        info "Backing up PostgreSQL"

        docker_exec postgres pg_dumpall -U "${POSTGRES_USER:-postgres}" \
            > "${backup_path}/databases/postgres_dump.sql" 2>/dev/null || {
                warning "Failed to backup PostgreSQL"
            }

        success "PostgreSQL backup complete"
    fi

    # Backup Redis
    if is_container_running "redis"; then
        info "Backing up Redis"

        # Trigger BGSAVE
        docker_exec redis redis-cli BGSAVE &> /dev/null || true
        sleep 2

        # Copy dump file
        docker cp redis:/data/dump.rdb "${backup_path}/databases/redis_dump.rdb" 2>/dev/null || {
            warning "Failed to backup Redis"
        }

        success "Redis backup complete"
    fi
}

# Create backup metadata
create_backup_metadata() {
    local backup_path="$1"

    subsection "Creating metadata"

    cat > "${backup_path}/metadata.json" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "version": "${JACKER_VERSION}",
    "hostname": "$(hostname)",
    "docker_version": "$(docker --version | awk '{print $3}')",
    "compose_version": "$(docker compose version --short)",
    "services": $(docker compose ps --format json 2>/dev/null || echo "[]"),
    "checksums": {}
}
EOF

    # Generate checksums
    info "Generating checksums"
    find "$backup_path" -type f ! -name "checksums.txt" -exec sha256sum {} \; \
        > "${backup_path}/checksums.txt"

    success "Metadata created"
}

# Compress backup
compress_backup() {
    local backup_dir="$1"
    local backup_name="$2"

    subsection "Compressing backup"

    cd "$backup_dir" || {
        error "Failed to change to backup directory: $backup_dir"
        return 1
    }
    tar czf "${backup_name}.tar.gz" "$backup_name" || {
        error "Failed to compress backup"
        return 1
    }

    success "Backup compressed"
}

# Cleanup old backups
cleanup_old_backups() {
    local backup_dir="$1"
    local keep_days="${2:-30}"

    subsection "Cleaning old backups"

    # Find and remove backups older than keep_days
    find "$backup_dir" -name "jacker-backup-*.tar.gz" -mtime +${keep_days} -delete 2>/dev/null || true

    # Count remaining backups
    local backup_count=$(find "$backup_dir" -name "jacker-backup-*.tar.gz" 2>/dev/null | wc -l)
    info "Keeping ${backup_count} backups (last ${keep_days} days)"
}

# List backups
list_backups() {
    local backup_dir="${1:-$DEFAULT_BACKUP_DIR}"

    section "Available Backups"

    if [ ! -d "$backup_dir" ]; then
        warning "Backup directory does not exist: $backup_dir"
        return 1
    fi

    local backups=$(find "$backup_dir" -name "jacker-backup-*.tar.gz" 2>/dev/null | sort -r)

    if [ -z "$backups" ]; then
        warning "No backups found in $backup_dir"
        return 1
    fi

    echo "Location: $backup_dir"
    echo ""

    for backup in $backups; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" | cut -d' ' -f1)
        local name=$(basename "$backup")
        printf "  %-50s %10s  %s\n" "$name" "$size" "$date"
    done
}

# Verify backup
verify_backup() {
    local backup_file="$1"

    section "Verifying Backup"

    if [ ! -f "$backup_file" ]; then
        error "Backup file not found: $backup_file"
        return 1
    fi

    # Create temporary directory
    local temp_dir="/tmp/jacker-backup-verify-$(timestamp)"
    mkdir -p "$temp_dir"

    # Extract backup
    info "Extracting backup for verification"
    tar xzf "$backup_file" -C "$temp_dir" 2>/dev/null || {
        error "Failed to extract backup"
        rm -rf "$temp_dir"
        return 1
    }

    # Find extracted backup directory
    local backup_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "jacker-backup-*" | head -1)

    if [ -z "$backup_dir" ]; then
        error "Invalid backup structure"
        rm -rf "$temp_dir"
        return 1
    fi

    # Verify checksums
    if [ -f "${backup_dir}/checksums.txt" ]; then
        info "Verifying checksums"
        cd "$backup_dir" || {
            error "Failed to change to backup directory"
            rm -rf "$temp_dir"
            return 1
        }
        if sha256sum -c checksums.txt > /dev/null 2>&1; then
            success "Checksums verified"
        else
            error "Checksum verification failed"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        warning "No checksums found in backup"
    fi

    # Check for required files
    local required_files=(
        "config/.env"
        "config/docker-compose.yml"
        "metadata.json"
    )

    for file in "${required_files[@]}"; do
        if [ -f "${backup_dir}/${file}" ]; then
            success "Found: $file"
        else
            warning "Missing: $file"
        fi
    done

    # Cleanup
    rm -rf "$temp_dir"

    success "Backup verification complete"
}

# ============================================================================
# Main Execution
# ============================================================================

# Parse arguments
case "${1:-create}" in
    create)
        create_backup "${2:-}"
        ;;
    list)
        list_backups "${2:-}"
        ;;
    verify)
        if [ -z "${2:-}" ]; then
            error "Usage: $0 verify <backup-file>"
            exit 1
        fi
        verify_backup "$2"
        ;;
    *)
        # Treat as backup directory
        create_backup "$1"
        ;;
esac