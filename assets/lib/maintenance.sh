#!/usr/bin/env bash
# Jacker Maintenance Library
# Backup, restore, updates, and maintenance operations

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${SCRIPT_DIR}/common.sh"

#########################################
# Backup Functions
#########################################

backup_jacker() {
    local backup_type="${1:-full}"
    local custom_path="${2:-}"

    log_section "Jacker Backup"

    # Determine backup path
    local backup_base="${custom_path:-${JACKER_DIR}/backups}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${backup_base}/backup_${timestamp}"

    mkdir -p "$backup_dir"

    case "$backup_type" in
        full)
            backup_full "$backup_dir"
            ;;
        config)
            backup_config "$backup_dir"
            ;;
        data)
            backup_data "$backup_dir"
            ;;
        volumes)
            backup_volumes "$backup_dir"
            ;;
        selective)
            backup_selective "$backup_dir"
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac

    # Create backup manifest
    create_backup_manifest "$backup_dir"

    # Compress if requested
    read -p "Compress backup? (Y/n): " compress
    if [[ "${compress,,}" != "n" ]]; then
        compress_backup "$backup_dir"
    fi

    log_success "Backup completed: $backup_dir"
    show_backup_size "$backup_dir"
}

backup_full() {
    local backup_dir="$1"

    log_info "Performing full backup..."

    # Stop services if requested
    read -p "Stop services during backup? (recommended) (Y/n): " stop_services
    if [[ "${stop_services,,}" != "n" ]]; then
        docker compose stop
        local services_stopped=true
    fi

    # Backup configuration
    backup_config "$backup_dir"

    # Backup data
    backup_data "$backup_dir"

    # Backup volumes
    backup_volumes "$backup_dir"

    # Backup compose files
    log_info "Backing up compose files..."
    tar -czf "$backup_dir/compose.tar.gz" -C "${JACKER_DIR}" compose docker-compose.yml

    # Restart services if they were stopped
    if [[ "${services_stopped:-false}" == "true" ]]; then
        docker compose start
    fi
}

backup_config() {
    local backup_dir="$1"

    log_info "Backing up configuration..."

    # Backup .env file
    if [[ -f "${JACKER_DIR}/.env" ]]; then
        cp "${JACKER_DIR}/.env" "$backup_dir/.env"
        chmod 600 "$backup_dir/.env"
    fi

    # Backup config directories
    local config_dirs=(
        "config"
        "data/traefik/rules"
        "data/traefik/traefik.yml"
        "data/loki/loki-config.yml"
        "data/loki/promtail-config.yml"
        "data/crowdsec/config"
        "data/homepage/config"
    )

    for dir_path in "${config_dirs[@]}"; do
        if [[ -e "${JACKER_DIR}/$dir_path" ]]; then
            local parent_dir=$(dirname "$dir_path")
            mkdir -p "$backup_dir/$parent_dir"
            cp -r "${JACKER_DIR}/$dir_path" "$backup_dir/$parent_dir/"
        fi
    done

    # Backup secrets
    if [[ -d "${JACKER_DIR}/secrets" ]]; then
        log_info "Backing up secrets (encrypted)..."
        tar -czf "$backup_dir/secrets.tar.gz.enc" -C "${JACKER_DIR}" secrets
        # Encrypt the secrets backup
        if command -v openssl &>/dev/null; then
            read -sp "Enter encryption password for secrets: " enc_password
            echo
            openssl enc -aes-256-cbc -salt -in "$backup_dir/secrets.tar.gz.enc" \
                    -out "$backup_dir/secrets.tar.gz.enc.aes" -pass pass:"$enc_password"
            rm "$backup_dir/secrets.tar.gz.enc"
        fi
    fi
}

backup_data() {
    local backup_dir="$1"

    log_info "Backing up data directories..."

    # Critical data directories to backup
    local data_dirs=(
        "data/traefik/acme"
        "data/grafana"
        "data/prometheus"
        "data/loki/data"
        "data/postgres"
        "data/redis"
        "data/crowdsec/data"
        "data/portainer"
        "data/homepage"
    )

    mkdir -p "$backup_dir/data"

    for dir_path in "${data_dirs[@]}"; do
        if [[ -d "${JACKER_DIR}/$dir_path" ]]; then
            local dir_name=$(basename "$dir_path")
            log_info "Backing up $dir_path..."

            # Handle special cases
            case "$dir_path" in
                "data/postgres")
                    # Backup PostgreSQL properly
                    backup_postgres "$backup_dir/data"
                    ;;
                "data/redis")
                    # Backup Redis properly
                    backup_redis "$backup_dir/data"
                    ;;
                *)
                    # Regular file backup
                    tar -czf "$backup_dir/data/${dir_name}.tar.gz" \
                        -C "${JACKER_DIR}" "$dir_path" 2>/dev/null || \
                        log_warn "Failed to backup $dir_path"
                    ;;
            esac
        fi
    done
}

backup_postgres() {
    local backup_dir="$1"

    if ! docker ps --format '{{.Names}}' | grep -q 'jacker-postgres'; then
        log_warn "PostgreSQL container not running, skipping database backup"
        return
    fi

    log_info "Backing up PostgreSQL databases..."

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    # Dump all databases
    docker compose exec -T postgres pg_dumpall -U "${POSTGRES_USER}" \
        > "$backup_dir/postgres_dump.sql" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        gzip "$backup_dir/postgres_dump.sql"
        log_success "PostgreSQL backup completed"
    else
        log_error "PostgreSQL backup failed"
    fi
}

backup_redis() {
    local backup_dir="$1"

    if ! docker ps --format '{{.Names}}' | grep -q 'jacker-redis'; then
        log_warn "Redis container not running, skipping backup"
        return
    fi

    log_info "Backing up Redis..."

    # Trigger Redis save
    docker compose exec -T redis redis-cli BGSAVE 2>/dev/null

    # Wait for save to complete
    sleep 2

    # Copy dump file
    docker compose cp redis:/data/dump.rdb "$backup_dir/redis_dump.rdb" 2>/dev/null || \
        log_warn "Failed to backup Redis"
}

backup_volumes() {
    local backup_dir="$1"

    log_info "Backing up Docker volumes..."

    mkdir -p "$backup_dir/volumes"

    # Get all Jacker volumes
    local volumes=$(docker volume ls --format '{{.Name}}' | grep '^jacker_')

    for volume in $volumes; do
        log_info "Backing up volume: $volume"

        # Create temporary container to access volume
        docker run --rm -v "${volume}:/source:ro" \
               -v "${backup_dir}/volumes:/backup" \
               alpine tar -czf "/backup/${volume}.tar.gz" -C /source . 2>/dev/null || \
               log_warn "Failed to backup volume $volume"
    done
}

backup_selective() {
    local backup_dir="$1"

    log_section "Selective Backup"

    echo "Select items to backup:"
    echo "1. Configuration files (.env, configs)"
    echo "2. Traefik data (certificates, rules)"
    echo "3. Monitoring data (Grafana, Prometheus)"
    echo "4. Database data (PostgreSQL, Redis)"
    echo "5. Application data (Portainer, Homepage)"
    echo "6. Security data (CrowdSec)"
    echo "7. Docker volumes"

    read -p "Enter selections (comma-separated, e.g., 1,3,4): " selections

    IFS=',' read -ra SELECTIONS <<< "$selections"

    for selection in "${SELECTIONS[@]}"; do
        case "$selection" in
            1)
                backup_config "$backup_dir"
                ;;
            2)
                tar -czf "$backup_dir/traefik.tar.gz" -C "${JACKER_DIR}" data/traefik
                ;;
            3)
                tar -czf "$backup_dir/monitoring.tar.gz" -C "${JACKER_DIR}" \
                    data/grafana data/prometheus data/loki 2>/dev/null
                ;;
            4)
                backup_postgres "$backup_dir"
                backup_redis "$backup_dir"
                ;;
            5)
                tar -czf "$backup_dir/apps.tar.gz" -C "${JACKER_DIR}" \
                    data/portainer data/homepage 2>/dev/null
                ;;
            6)
                tar -czf "$backup_dir/security.tar.gz" -C "${JACKER_DIR}" \
                    data/crowdsec 2>/dev/null
                ;;
            7)
                backup_volumes "$backup_dir"
                ;;
        esac
    done
}

create_backup_manifest() {
    local backup_dir="$1"

    log_info "Creating backup manifest..."

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    cat > "$backup_dir/manifest.txt" <<EOF
Jacker Backup Manifest
======================
Timestamp: $(date)
Hostname: $(hostname -f)
Domain: ${DOMAINNAME:-unknown}
Public FQDN: ${PUBLIC_FQDN:-unknown}
Jacker Version: $(cat "${JACKER_DIR}/VERSION" 2>/dev/null || echo "unknown")
Docker Version: $(docker --version)
Compose Version: $(docker compose version)

Backup Contents:
$(ls -la "$backup_dir")

Disk Usage:
$(du -sh "$backup_dir")

Container Status at Backup:
$(docker compose ps)
EOF
}

compress_backup() {
    local backup_dir="$1"

    log_info "Compressing backup..."

    local archive_name="$(basename "$backup_dir").tar.gz"
    local archive_path="$(dirname "$backup_dir")/$archive_name"

    tar -czf "$archive_path" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"

    if [[ $? -eq 0 ]]; then
        # Remove uncompressed backup
        rm -rf "$backup_dir"
        log_success "Backup compressed: $archive_path"
    else
        log_error "Failed to compress backup"
    fi
}

show_backup_size() {
    local backup_path="$1"

    if [[ -d "$backup_path" ]]; then
        local size=$(du -sh "$backup_path" | awk '{print $1}')
    else
        local size=$(du -sh "$backup_path"* 2>/dev/null | awk '{print $1}')
    fi

    echo "Backup size: ${size:-unknown}"
}

#########################################
# Restore Functions
#########################################

restore_jacker() {
    log_section "Jacker Restore"

    # List available backups
    list_backups

    read -p "Enter backup to restore (path or name): " backup_source

    # Find backup
    local backup_path
    if [[ -f "$backup_source" ]] || [[ -d "$backup_source" ]]; then
        backup_path="$backup_source"
    else
        backup_path="${JACKER_DIR}/backups/$backup_source"
    fi

    if [[ ! -e "$backup_path" ]]; then
        log_error "Backup not found: $backup_path"
        return 1
    fi

    # Extract if compressed
    if [[ -f "$backup_path" ]] && [[ "$backup_path" == *.tar.gz ]]; then
        log_info "Extracting backup..."
        local extract_dir="/tmp/jacker_restore_$$"
        mkdir -p "$extract_dir"
        tar -xzf "$backup_path" -C "$extract_dir"
        backup_path="$extract_dir/$(ls "$extract_dir")"
    fi

    # Confirm restore
    log_warn "This will overwrite current configuration and data!"
    read -p "Continue with restore? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        log_info "Restore cancelled"
        return
    fi

    # Stop services
    log_info "Stopping services..."
    docker compose down

    # Perform restore
    restore_config "$backup_path"
    restore_data "$backup_path"
    restore_volumes "$backup_path"

    # Start services
    log_info "Starting services..."
    docker compose up -d

    log_success "Restore completed"
}

restore_config() {
    local backup_path="$1"

    log_info "Restoring configuration..."

    # Restore .env
    if [[ -f "$backup_path/.env" ]]; then
        cp "$backup_path/.env" "${JACKER_DIR}/.env"
        chmod 600 "${JACKER_DIR}/.env"
    fi

    # Restore config directories
    if [[ -d "$backup_path/config" ]]; then
        cp -r "$backup_path/config" "${JACKER_DIR}/"
    fi

    # Restore Traefik rules
    if [[ -d "$backup_path/data/traefik/rules" ]]; then
        mkdir -p "${JACKER_DIR}/data/traefik"
        cp -r "$backup_path/data/traefik/rules" "${JACKER_DIR}/data/traefik/"
    fi

    # Restore secrets (if encrypted)
    if [[ -f "$backup_path/secrets.tar.gz.enc.aes" ]]; then
        log_info "Restoring encrypted secrets..."
        read -sp "Enter decryption password: " dec_password
        echo

        openssl enc -d -aes-256-cbc -in "$backup_path/secrets.tar.gz.enc.aes" \
                -out "$backup_path/secrets.tar.gz" -pass pass:"$dec_password"

        tar -xzf "$backup_path/secrets.tar.gz" -C "${JACKER_DIR}"
        rm "$backup_path/secrets.tar.gz"
    elif [[ -d "$backup_path/secrets" ]]; then
        cp -r "$backup_path/secrets" "${JACKER_DIR}/"
    fi
}

restore_data() {
    local backup_path="$1"

    log_info "Restoring data..."

    # Restore data archives
    if [[ -d "$backup_path/data" ]]; then
        for archive in "$backup_path/data"/*.tar.gz; do
            if [[ -f "$archive" ]]; then
                log_info "Restoring $(basename "$archive")..."
                tar -xzf "$archive" -C "${JACKER_DIR}" 2>/dev/null || \
                    log_warn "Failed to restore $(basename "$archive")"
            fi
        done
    fi

    # Restore PostgreSQL
    if [[ -f "$backup_path/data/postgres_dump.sql.gz" ]]; then
        restore_postgres "$backup_path/data/postgres_dump.sql.gz"
    fi

    # Restore Redis
    if [[ -f "$backup_path/data/redis_dump.rdb" ]]; then
        restore_redis "$backup_path/data/redis_dump.rdb"
    fi
}

restore_postgres() {
    local dump_file="$1"

    log_info "Restoring PostgreSQL databases..."

    # Start PostgreSQL if not running
    docker compose up -d postgres
    sleep 5

    # Wait for PostgreSQL to be ready
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
            break
        fi
        ((attempt++))
        sleep 2
    done

    # Restore dump
    gunzip -c "$dump_file" | docker compose exec -T postgres psql -U "${POSTGRES_USER}"

    if [[ $? -eq 0 ]]; then
        log_success "PostgreSQL restored"
    else
        log_error "PostgreSQL restore failed"
    fi
}

restore_redis() {
    local dump_file="$1"

    log_info "Restoring Redis..."

    # Copy dump file to Redis container
    docker compose cp "$dump_file" redis:/data/dump.rdb

    # Restart Redis to load dump
    docker compose restart redis

    log_success "Redis restored"
}

restore_volumes() {
    local backup_path="$1"

    if [[ ! -d "$backup_path/volumes" ]]; then
        log_info "No volume backups found"
        return
    fi

    log_info "Restoring Docker volumes..."

    for archive in "$backup_path/volumes"/*.tar.gz; do
        if [[ -f "$archive" ]]; then
            local volume_name=$(basename "$archive" .tar.gz)
            log_info "Restoring volume: $volume_name"

            # Create volume if it doesn't exist
            docker volume create "$volume_name" 2>/dev/null

            # Restore volume data
            docker run --rm -v "${volume_name}:/target" \
                   -v "$(dirname "$archive"):/backup:ro" \
                   alpine sh -c "cd /target && tar -xzf /backup/$(basename "$archive")" || \
                   log_warn "Failed to restore volume $volume_name"
        fi
    done
}

list_backups() {
    local backup_dir="${JACKER_DIR}/backups"

    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found"
        return
    fi

    log_subsection "Available Backups"

    # List backups with details
    for backup in "$backup_dir"/*; do
        if [[ -e "$backup" ]]; then
            local name=$(basename "$backup")
            local size=$(du -sh "$backup" | awk '{print $1}')
            local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)

            echo "  $name - $size - $date"

            # Show manifest if available
            if [[ -f "$backup/manifest.txt" ]]; then
                grep "Domain:" "$backup/manifest.txt" | sed 's/^/    /'
            fi
        fi
    done
}

#########################################
# Update Functions
#########################################

update_jacker() {
    log_section "Jacker Update"

    # Check for updates
    check_updates

    echo "Update Options:"
    echo "1. Update Jacker system"
    echo "2. Update Docker images"
    echo "3. Update configurations"
    echo "4. Update all"
    read -p "Choose option [4]: " update_choice
    update_choice="${update_choice:-4}"

    case "$update_choice" in
        1)
            update_jacker_system
            ;;
        2)
            update_docker_images
            ;;
        3)
            update_configurations
            ;;
        4)
            update_all
            ;;
    esac
}

check_updates() {
    log_info "Checking for updates..."

    # Check Jacker repository for updates
    if [[ -d "${JACKER_DIR}/.git" ]]; then
        local current_commit=$(git -C "${JACKER_DIR}" rev-parse HEAD)
        local remote_commit=$(git -C "${JACKER_DIR}" ls-remote origin main | awk '{print $1}')

        if [[ "$current_commit" != "$remote_commit" ]]; then
            log_info "Jacker updates available"
            git -C "${JACKER_DIR}" log --oneline HEAD..origin/main 2>/dev/null | head -5
        else
            log_success "Jacker is up to date"
        fi
    fi

    # Check Docker images for updates
    log_info "Checking Docker images..."
    local outdated_images=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.CreatedSince}}" | \
                           grep -E "weeks ago|months ago" | wc -l)

    if [[ $outdated_images -gt 0 ]]; then
        log_info "$outdated_images Docker images may have updates available"
    fi
}

update_jacker_system() {
    log_info "Updating Jacker system..."

    if [[ ! -d "${JACKER_DIR}/.git" ]]; then
        log_error "Not a git repository. Cannot update automatically."
        return 1
    fi

    # Create backup before update
    log_info "Creating backup before update..."
    backup_jacker config

    # Pull latest changes
    git -C "${JACKER_DIR}" fetch origin
    git -C "${JACKER_DIR}" pull origin main

    # Update dependencies if needed
    if [[ -f "${JACKER_DIR}/requirements.txt" ]]; then
        pip install -r "${JACKER_DIR}/requirements.txt"
    fi

    log_success "Jacker system updated"
}

update_docker_images() {
    log_info "Updating Docker images..."

    # Pull latest images
    docker compose pull

    # Show which images were updated
    docker compose images

    read -p "Recreate containers with new images? (Y/n): " recreate
    if [[ "${recreate,,}" != "n" ]]; then
        docker compose up -d --force-recreate
    fi

    # Clean up old images
    read -p "Remove old unused images? (Y/n): " cleanup
    if [[ "${cleanup,,}" != "n" ]]; then
        docker image prune -af
    fi

    log_success "Docker images updated"
}

update_configurations() {
    log_info "Updating configurations..."

    # Update template configurations
    local templates_dir="${JACKER_DIR}/assets/templates"

    if [[ -d "$templates_dir" ]]; then
        log_info "Regenerating configurations from templates..."

        # Load environment
        set -a
        source "${JACKER_DIR}/.env"
        set +a

        # Process templates
        for template in "$templates_dir"/*.template; do
            if [[ -f "$template" ]]; then
                local output_file="${template%.template}"
                local output_name=$(basename "$output_file")

                case "$output_name" in
                    "traefik.yml")
                        envsubst < "$template" > "${JACKER_DIR}/data/traefik/traefik.yml"
                        ;;
                    "loki-config.yml")
                        envsubst < "$template" > "${JACKER_DIR}/data/loki/loki-config.yml"
                        ;;
                    "promtail-config.yml")
                        envsubst < "$template" > "${JACKER_DIR}/data/loki/promtail-config.yml"
                        ;;
                esac
            fi
        done
    fi

    log_success "Configurations updated"
}

update_all() {
    log_info "Performing full update..."

    update_jacker_system
    update_docker_images
    update_configurations

    log_success "Full update completed"
    log_info "Restart services with './jacker restart' to apply all changes"
}

#########################################
# Cleanup Functions
#########################################

cleanup_jacker() {
    log_section "Jacker Cleanup"

    echo "Cleanup Options:"
    echo "1. Clean Docker resources"
    echo "2. Clean logs"
    echo "3. Clean old backups"
    echo "4. Clean temporary files"
    echo "5. Deep clean (all)"
    read -p "Choose option: " clean_choice

    case "$clean_choice" in
        1)
            clean_docker_resources
            ;;
        2)
            clean_logs
            ;;
        3)
            clean_old_backups
            ;;
        4)
            clean_temp_files
            ;;
        5)
            deep_clean
            ;;
    esac
}

clean_docker_resources() {
    log_info "Cleaning Docker resources..."

    # Remove stopped containers
    local stopped=$(docker ps -aq -f status=exited | wc -l)
    if [[ $stopped -gt 0 ]]; then
        log_info "Removing $stopped stopped containers..."
        docker container prune -f
    fi

    # Remove unused images
    log_info "Removing unused images..."
    docker image prune -af

    # Remove unused volumes
    read -p "Remove unused volumes? (y/N): " remove_volumes
    if [[ "${remove_volumes,,}" == "y" ]]; then
        docker volume prune -f
    fi

    # Remove unused networks
    docker network prune -f

    # Show disk usage
    log_info "Docker disk usage:"
    docker system df
}

clean_logs() {
    log_info "Cleaning logs..."

    # Clean container logs
    local containers=$(docker ps -q)
    for container in $containers; do
        local log_file=$(docker inspect --format='{{.LogPath}}' "$container")
        if [[ -f "$log_file" ]]; then
            local log_size=$(du -h "$log_file" | awk '{print $1}')
            if [[ "$log_size" != "0" ]]; then
                log_info "Truncating log for $container ($log_size)..."
                echo "" | sudo tee "$log_file" > /dev/null
            fi
        fi
    done

    # Clean Loki logs if over threshold
    local loki_dir="${JACKER_DIR}/data/loki/data"
    if [[ -d "$loki_dir" ]]; then
        local loki_size=$(du -sh "$loki_dir" | awk '{print $1}')
        log_info "Loki data size: $loki_size"

        read -p "Clean old Loki chunks? (y/N): " clean_loki
        if [[ "${clean_loki,,}" == "y" ]]; then
            find "$loki_dir/chunks" -type f -mtime +7 -delete 2>/dev/null
            log_success "Old Loki chunks cleaned"
        fi
    fi
}

clean_old_backups() {
    log_info "Cleaning old backups..."

    local backup_dir="${JACKER_DIR}/backups"

    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups directory found"
        return
    fi

    # Show current backups
    log_info "Current backups:"
    ls -lah "$backup_dir"

    read -p "Keep how many recent backups? [5]: " keep_count
    keep_count="${keep_count:-5}"

    # Remove old backups
    mapfile -t backups < <(ls -t "$backup_dir")
    local count=0

    for backup in "${backups[@]}"; do
        ((count++))
        if [[ $count -gt $keep_count ]]; then
            log_info "Removing old backup: $backup"
            rm -rf "${backup_dir:?}/${backup}"
        fi
    done

    log_success "Old backups cleaned"
}

clean_temp_files() {
    log_info "Cleaning temporary files..."

    # Clean /tmp
    find /tmp -name "jacker_*" -mtime +1 -delete 2>/dev/null

    # Clean Docker build cache
    docker builder prune -af

    log_success "Temporary files cleaned"
}

deep_clean() {
    log_warn "Deep clean will remove all unnecessary data!"
    read -p "Continue? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    clean_docker_resources
    clean_logs
    clean_old_backups
    clean_temp_files

    # Additional deep cleaning
    log_info "Performing deep clean..."

    # Clean package manager cache
    if command -v apt-get &>/dev/null; then
        sudo apt-get clean
        sudo apt-get autoremove -y
    fi

    # Clean journal logs
    if command -v journalctl &>/dev/null; then
        sudo journalctl --vacuum-time=7d
    fi

    log_success "Deep clean completed"
}

#########################################
# Migration Functions
#########################################

migrate_jacker() {
    log_section "Jacker Migration"

    echo "Migration Options:"
    echo "1. Migrate to new server"
    echo "2. Migrate from Docker Compose v1 to v2"
    echo "3. Migrate database backend"
    echo "4. Migrate from OAuth to Authentik"
    read -p "Choose option: " migrate_choice

    case "$migrate_choice" in
        1)
            migrate_to_server
            ;;
        2)
            migrate_compose_version
            ;;
        3)
            migrate_database
            ;;
        4)
            migrate_to_authentik
            ;;
    esac
}

migrate_to_server() {
    log_info "Server migration wizard..."

    echo "This will create a migration package for transferring Jacker to another server"

    # Create migration package
    local migration_dir="${JACKER_DIR}/migration_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$migration_dir"

    # Create full backup
    backup_jacker full "$migration_dir"

    # Create migration script
    cat > "$migration_dir/migrate.sh" <<'EOF'
#!/bin/bash
# Jacker Migration Script

set -e

echo "Jacker Migration Script"
echo "======================"

# Check requirements
if ! command -v docker &>/dev/null; then
    echo "Docker not found. Please install Docker first."
    exit 1
fi

# Extract backup
echo "Extracting backup..."
tar -xzf backup_*.tar.gz

# Restore Jacker
echo "Restoring Jacker..."
# Migration commands here

echo "Migration completed!"
echo "Run './jacker start' to start services"
EOF

    chmod +x "$migration_dir/migrate.sh"

    log_success "Migration package created: $migration_dir"
    echo "Transfer this directory to the new server and run ./migrate.sh"
}

migrate_compose_version() {
    log_info "Migrating Docker Compose version..."

    # Check current compose version
    if docker-compose version &>/dev/null 2>&1; then
        log_info "Docker Compose v1 detected"

        # Update to v2
        if ! docker compose version &>/dev/null 2>&1; then
            log_info "Installing Docker Compose v2..."

            sudo mkdir -p /usr/local/lib/docker/cli-plugins
            sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose
            sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        fi

        log_success "Docker Compose v2 installed"
    else
        log_info "Already using Docker Compose v2"
    fi
}

migrate_database() {
    log_info "Database migration..."

    echo "Current database: PostgreSQL"
    echo "Migration options:"
    echo "1. PostgreSQL to MySQL/MariaDB"
    echo "2. SQLite to PostgreSQL"
    echo "3. External database"
    read -p "Choose option: " db_choice

    case "$db_choice" in
        1)
            log_warn "PostgreSQL to MySQL migration not yet implemented"
            ;;
        2)
            log_warn "SQLite to PostgreSQL migration not yet implemented"
            ;;
        3)
            configure_external_database
            ;;
    esac
}

configure_external_database() {
    log_info "Configuring external database..."

    read -p "Database host: " db_host
    read -p "Database port [5432]: " db_port
    db_port="${db_port:-5432}"
    read -p "Database name: " db_name
    read -p "Database user: " db_user
    read -sp "Database password: " db_pass
    echo

    # Update .env
    update_env_var "POSTGRES_HOST" "$db_host"
    update_env_var "POSTGRES_PORT" "$db_port"
    update_env_var "POSTGRES_DB" "$db_name"
    update_env_var "POSTGRES_USER" "$db_user"
    update_env_var "POSTGRES_PASSWORD" "$db_pass"

    log_success "External database configured"
}

migrate_to_authentik() {
    log_info "Migrating from OAuth to Authentik..."

    # This would implement the migration from OAuth to Authentik
    # Following the guide in jacker-docs/docs/guides/authentik-migration.md

    log_warn "Please refer to jacker-docs/docs/guides/authentik-migration.md for migration steps"
}

#########################################
# Utility Functions
#########################################

update_env_var() {
    local var_name="$1"
    local var_value="$2"
    local env_file="${JACKER_DIR}/.env"

    if grep -q "^${var_name}=" "$env_file"; then
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file"
    else
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Export functions for use by jacker CLI
export -f backup_jacker
export -f restore_jacker
export -f update_jacker
export -f cleanup_jacker
export -f migrate_jacker
export -f list_backups