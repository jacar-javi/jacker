#!/usr/bin/env bash
#
# deploy-to-vps.sh - Production deployment script for Jacker
# Transfers and deploys Jacker to remote VPS with zero-downtime capability
#
# Usage:
#   ./deploy-to-vps.sh [OPTIONS]
#   ./deploy-to-vps.sh --host ubuntu@vps1.jacarsystems.net
#   ./deploy-to-vps.sh --dry-run
#   ./deploy-to-vps.sh --rollback
#
# Features:
#   - Pre-deployment validation
#   - Efficient rsync file transfer
#   - Remote deployment automation
#   - Automatic rollback on failure
#   - Detailed logging with timestamps
#   - Idempotent execution
#
# Exit codes:
#   0 - Success
#   1 - Validation error
#   2 - Transfer error
#   3 - Deployment error
#   4 - Rollback error

set -euo pipefail

# ====================================================================
# CONFIGURATION
# ====================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly VERSION="1.0.0"

# Default configuration
DEFAULT_VPS_HOST="ubuntu@vps1.jacarsystems.net"
DEFAULT_REMOTE_DIR="/opt/jacker"
DEFAULT_BACKUP_DIR="/opt/jacker-backups"
DEFAULT_LOG_DIR="/var/log/jacker"
DEPLOYMENT_TIMEOUT=600
RSYNC_RETRIES=3

# Runtime variables
VPS_HOST="${DEFAULT_VPS_HOST}"
REMOTE_DIR="${DEFAULT_REMOTE_DIR}"
BACKUP_DIR="${DEFAULT_BACKUP_DIR}"
DRY_RUN=false
FORCE=false
ROLLBACK_MODE=false
SKIP_VALIDATION=false
VERBOSE=false
DEPLOYMENT_ID=""
BACKUP_NAME=""
LOG_FILE=""

# ====================================================================
# COLOR CODES
# ====================================================================
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ====================================================================
# LOGGING FUNCTIONS
# ====================================================================

log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp="$(log_timestamp)"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" >&2
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS" "$*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
    log "WARN" "$*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR" "$*"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}DEBUG:${NC} $*" >&2
        log "DEBUG" "$*"
    fi
}

log_step() {
    echo ""
    echo -e "${BOLD}${MAGENTA}▶${NC} ${BOLD}$*${NC}"
    log "STEP" "$*"
}

# ====================================================================
# UTILITY FUNCTIONS
# ====================================================================

usage() {
    cat <<EOF
${BOLD}Jacker VPS Deployment Tool v${VERSION}${NC}

${BOLD}USAGE:${NC}
    $SCRIPT_NAME [OPTIONS]

${BOLD}OPTIONS:${NC}
    -h, --host HOST         VPS hostname (default: $DEFAULT_VPS_HOST)
    -d, --remote-dir DIR    Remote directory (default: $DEFAULT_REMOTE_DIR)
    -b, --backup-dir DIR    Backup directory (default: $DEFAULT_BACKUP_DIR)
    --dry-run               Show what would be done without executing
    --force                 Skip safety prompts
    --rollback              Rollback to previous deployment
    --skip-validation       Skip pre-deployment validation
    -v, --verbose           Enable verbose output
    --help                  Show this help message

${BOLD}EXAMPLES:${NC}
    # Deploy to default VPS
    $SCRIPT_NAME

    # Deploy to custom host
    $SCRIPT_NAME --host user@vps2.example.com

    # Dry run to test
    $SCRIPT_NAME --dry-run

    # Rollback failed deployment
    $SCRIPT_NAME --rollback

    # Verbose deployment
    $SCRIPT_NAME --verbose

${BOLD}DEPLOYMENT PROCESS:${NC}
    1. Pre-deployment validation
    2. SSH connectivity test
    3. Backup existing deployment (if exists)
    4. Rsync files to VPS
    5. Set permissions
    6. Execute remote deployment
    7. Post-deployment validation
    8. Cleanup

${BOLD}EXCLUDED FROM TRANSFER:${NC}
    - data/ (service data)
    - .git/ (version control)
    - *.log (log files)
    - .env (created on VPS)
    - secrets/*.txt (regenerated on VPS)
    - backups/
    - node_modules/
    - .cache/

${BOLD}NOTES:${NC}
    - Requires SSH key authentication
    - Remote user must have sudo privileges
    - Logs saved to: ${DEFAULT_LOG_DIR}/deploy-\${timestamp}.log
    - Automatic rollback on failure
    - Idempotent (safe to run multiple times)

EOF
}

init_logging() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    DEPLOYMENT_ID="deploy-${timestamp}"

    # Create log directory if it doesn't exist
    mkdir -p "$PROJECT_DIR/logs" 2>/dev/null || true

    LOG_FILE="$PROJECT_DIR/logs/${DEPLOYMENT_ID}.log"

    log_debug "Logging initialized: $LOG_FILE"
    log_debug "Deployment ID: $DEPLOYMENT_ID"
}

# ====================================================================
# VALIDATION FUNCTIONS
# ====================================================================

validate_dependencies() {
    log_step "Validating Dependencies"

    local -a missing_deps=()

    # Only check for local dependencies (docker is checked on remote)
    for cmd in rsync ssh; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Install with: sudo apt-get install rsync openssh-client"
        return 1
    fi

    log_success "All local dependencies available"
    return 0
}

validate_local_environment() {
    log_step "Validating Local Environment"

    # Check if in Jacker directory
    if [[ ! -f "$PROJECT_DIR/docker-compose.yml" ]]; then
        log_error "Not in Jacker directory (docker-compose.yml not found)"
        return 1
    fi
    log_success "Jacker directory verified"

    # Run validation script if not skipped
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        if [[ -f "$SCRIPT_DIR/validate.sh" ]]; then
            log_info "Running pre-deployment validation..."
            if "$SCRIPT_DIR/validate.sh" >> "$LOG_FILE" 2>&1; then
                log_success "Pre-deployment validation passed"
            else
                log_error "Pre-deployment validation failed"
                log_info "Review validation output in: $LOG_FILE"
                log_info "Use --skip-validation to bypass (not recommended)"
                return 1
            fi
        else
            log_warn "Validation script not found, skipping local validation"
        fi
    else
        log_warn "Skipping pre-deployment validation (--skip-validation)"
    fi

    # Check for critical files
    local -a critical_files=(
        "docker-compose.yml"
        "jacker"
        ".env.sample"
        ".env.defaults"
    )

    for file in "${critical_files[@]}"; do
        if [[ ! -f "$PROJECT_DIR/$file" ]]; then
            log_error "Critical file missing: $file"
            return 1
        fi
    done
    log_success "Critical files present"

    return 0
}

test_ssh_connectivity() {
    log_step "Testing SSH Connectivity"

    log_info "Testing connection to: $VPS_HOST"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test SSH connection to $VPS_HOST"
        return 0
    fi

    # Test SSH connection
    if ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_HOST" "echo 'SSH connection successful'" >> "$LOG_FILE" 2>&1; then
        log_success "SSH connection successful"
    else
        log_error "Cannot connect to $VPS_HOST"
        log_error "Verify:"
        log_error "  - SSH key is added to ssh-agent: ssh-add -l"
        log_error "  - Host is reachable: ping $(echo "$VPS_HOST" | cut -d'@' -f2)"
        log_error "  - SSH key is authorized on remote host"
        return 1
    fi

    # Check sudo access
    log_info "Verifying sudo privileges..."
    if ssh "$VPS_HOST" "sudo -n true" >> "$LOG_FILE" 2>&1; then
        log_success "Sudo access verified"
    else
        log_warn "Passwordless sudo not configured"
        log_warn "You may be prompted for password during deployment"
    fi

    # Check if Docker is available on remote
    log_info "Checking Docker availability on VPS..."
    if ssh "$VPS_HOST" "command -v docker &>/dev/null && docker --version" >> "$LOG_FILE" 2>&1; then
        log_success "Docker is available on VPS"
    else
        log_error "Docker not found on VPS"
        log_error "Install Docker on the VPS before deploying"
        return 1
    fi

    return 0
}

# ====================================================================
# BACKUP FUNCTIONS
# ====================================================================

create_remote_backup() {
    log_step "Creating Remote Backup"

    BACKUP_NAME="jacker-backup-$(date +%Y%m%d_%H%M%S)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup: $BACKUP_DIR/$BACKUP_NAME"
        return 0
    fi

    log_info "Checking if deployment exists on VPS..."

    # Check if remote directory exists
    if ssh "$VPS_HOST" "test -d $REMOTE_DIR" 2>/dev/null; then
        log_info "Existing deployment found, creating backup..."

        # Create backup directory if it doesn't exist
        ssh "$VPS_HOST" "sudo mkdir -p $BACKUP_DIR" >> "$LOG_FILE" 2>&1

        # Create backup
        log_info "Backing up to: $BACKUP_DIR/$BACKUP_NAME"
        if ssh "$VPS_HOST" "sudo cp -a $REMOTE_DIR $BACKUP_DIR/$BACKUP_NAME" >> "$LOG_FILE" 2>&1; then
            log_success "Backup created: $BACKUP_NAME"

            # Store backup info
            ssh "$VPS_HOST" "echo '$(date -Iseconds)' | sudo tee $BACKUP_DIR/$BACKUP_NAME/BACKUP_TIMESTAMP > /dev/null"
            ssh "$VPS_HOST" "echo '$DEPLOYMENT_ID' | sudo tee $BACKUP_DIR/$BACKUP_NAME/DEPLOYMENT_ID > /dev/null"
        else
            log_error "Failed to create backup"
            return 1
        fi

        # Clean old backups (keep last 5)
        log_info "Cleaning old backups (keeping last 5)..."
        ssh "$VPS_HOST" "cd $BACKUP_DIR && sudo ls -t | tail -n +6 | xargs -r sudo rm -rf" >> "$LOG_FILE" 2>&1 || true

    else
        log_info "No existing deployment found (first deployment)"
    fi

    return 0
}

# ====================================================================
# TRANSFER FUNCTIONS
# ====================================================================

transfer_files() {
    log_step "Transferring Files to VPS"

    # Prepare rsync exclude list
    local -a rsync_exclude=(
        --exclude='data/'
        --exclude='.git/'
        --exclude='*.log'
        --exclude='logs/'
        --exclude='.env'
        --exclude='secrets/*.txt'
        --exclude='secrets/*.key'
        --exclude='secrets/*.pem'
        --exclude='backups/'
        --exclude='backup/'
        --exclude='restored/'
        --exclude='node_modules/'
        --exclude='.cache/'
        --exclude='.local/'
        --exclude='.config/'
        --exclude='tmp/'
        --exclude='temp/'
        --exclude='__pycache__/'
        --exclude='*.pyc'
        --exclude='.pytest_cache/'
        --exclude='.vscode/'
        --exclude='.idea/'
        --exclude='.DS_Store'
        --exclude='*.swp'
        --exclude='*.swo'
        --exclude='*.bak'
        --exclude='*.old'
        --exclude='*.tmp'
        --exclude='.trunk/'
        --exclude='.serena/'
        --exclude='.claude/'
        --exclude='*.tar.gz'
        --exclude='*.zip'
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would transfer files with rsync"
        log_debug "Rsync command preview:"
        log_debug "rsync -avz --delete ${rsync_exclude[*]} $PROJECT_DIR/ $VPS_HOST:$REMOTE_DIR/"
        return 0
    fi

    # Ensure remote directory exists
    log_info "Creating remote directory: $REMOTE_DIR"
    ssh "$VPS_HOST" "sudo mkdir -p $REMOTE_DIR" >> "$LOG_FILE" 2>&1

    # Set temporary permissions for rsync
    ssh "$VPS_HOST" "sudo chown -R \$USER:$(ssh "$VPS_HOST" id -gn) $REMOTE_DIR" >> "$LOG_FILE" 2>&1

    # Perform rsync with retries
    local attempt=1
    local max_attempts=$RSYNC_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Transferring files (attempt $attempt/$max_attempts)..."

        if rsync -avz --delete \
            --progress \
            --stats \
            --human-readable \
            "${rsync_exclude[@]}" \
            "$PROJECT_DIR/" \
            "$VPS_HOST:$REMOTE_DIR/" \
            >> "$LOG_FILE" 2>&1; then

            log_success "File transfer completed successfully"
            return 0
        else
            log_warn "Transfer attempt $attempt failed"

            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Retrying in 5 seconds..."
                sleep 5
                ((attempt++))
            else
                log_error "File transfer failed after $max_attempts attempts"
                return 1
            fi
        fi
    done

    return 1
}

# ====================================================================
# REMOTE EXECUTION FUNCTIONS
# ====================================================================

set_remote_permissions() {
    log_step "Setting Remote Permissions"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set permissions on remote files"
        return 0
    fi

    log_info "Setting executable permissions..."

    # Make scripts executable
    ssh "$VPS_HOST" "cd $REMOTE_DIR && chmod +x jacker jacker-dev scripts/*.sh" >> "$LOG_FILE" 2>&1
    log_success "Scripts made executable"

    # Create necessary directories with proper permissions
    ssh "$VPS_HOST" "cd $REMOTE_DIR && mkdir -p data logs secrets backups" >> "$LOG_FILE" 2>&1

    # Set ownership
    log_info "Setting ownership..."
    ssh "$VPS_HOST" "sudo chown -R \$USER:\$(id -gn) $REMOTE_DIR" >> "$LOG_FILE" 2>&1

    # Set secure permissions for sensitive directories
    ssh "$VPS_HOST" "cd $REMOTE_DIR && chmod 700 secrets" >> "$LOG_FILE" 2>&1 || true

    log_success "Permissions configured"
    return 0
}

execute_remote_deployment() {
    log_step "Executing Remote Deployment"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute remote deployment"
        return 0
    fi

    # Check if this is initial deployment or update
    log_info "Detecting deployment type..."

    if ssh "$VPS_HOST" "test -f $REMOTE_DIR/.env" 2>/dev/null; then
        log_info "Existing deployment detected - performing update"
        DEPLOYMENT_TYPE="update"
    else
        log_info "First deployment detected - performing initialization"
        DEPLOYMENT_TYPE="init"
    fi

    # Execute appropriate command
    case "$DEPLOYMENT_TYPE" in
        init)
            log_info "Running: ./jacker init --auto"
            if ssh "$VPS_HOST" "cd $REMOTE_DIR && ./jacker init --auto" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Initialization completed"
            else
                log_error "Initialization failed"
                return 1
            fi
            ;;

        update)
            log_info "Pulling latest Docker images..."
            if ssh "$VPS_HOST" "cd $REMOTE_DIR && docker compose pull" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Docker images pulled"
            else
                log_warn "Some images may have failed to pull"
            fi

            log_info "Recreating containers with new images..."
            if ssh "$VPS_HOST" "cd $REMOTE_DIR && docker compose up -d --force-recreate" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Services updated and restarted"
            else
                log_error "Update failed"
                return 1
            fi
            ;;
    esac

    return 0
}

# ====================================================================
# VALIDATION FUNCTIONS
# ====================================================================

validate_remote_deployment() {
    log_step "Validating Remote Deployment"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi

    # Check if services are running
    log_info "Checking service status..."

    if ssh "$VPS_HOST" "cd $REMOTE_DIR && ./jacker status" >> "$LOG_FILE" 2>&1; then
        log_success "Services are running"
    else
        log_error "Service status check failed"
        return 1
    fi

    # Run health checks
    log_info "Running health checks..."

    if ssh "$VPS_HOST" "cd $REMOTE_DIR && ./jacker health" >> "$LOG_FILE" 2>&1; then
        log_success "Health checks passed"
    else
        log_warn "Health checks reported issues"
        log_info "Review health check output in: $LOG_FILE"
    fi

    # Wait for services to stabilize
    log_info "Waiting 10 seconds for services to stabilize..."
    sleep 10

    # Final status check
    log_info "Final status verification..."
    if ssh "$VPS_HOST" "cd $REMOTE_DIR && docker compose ps | grep -c 'Up' || true" >> "$LOG_FILE" 2>&1; then
        local running_count
        running_count=$(ssh "$VPS_HOST" "cd $REMOTE_DIR && docker compose ps | grep -c 'Up' || true")
        log_success "Deployment validated: $running_count services running"
    fi

    return 0
}

# ====================================================================
# ROLLBACK FUNCTIONS
# ====================================================================

perform_rollback() {
    log_step "Performing Rollback"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback to previous deployment"
        return 0
    fi

    log_warn "Rolling back to previous deployment..."

    # Find most recent backup
    local latest_backup
    latest_backup=$(ssh "$VPS_HOST" "ls -t $BACKUP_DIR | head -1" 2>/dev/null || echo "")

    if [[ -z "$latest_backup" ]]; then
        log_error "No backups found in $BACKUP_DIR"
        log_error "Cannot perform rollback"
        return 1
    fi

    log_info "Restoring from backup: $latest_backup"

    # Stop services
    log_info "Stopping services..."
    ssh "$VPS_HOST" "cd $REMOTE_DIR && ./jacker stop" >> "$LOG_FILE" 2>&1 || true

    # Restore backup
    log_info "Restoring files..."
    if ssh "$VPS_HOST" "sudo rm -rf $REMOTE_DIR && sudo cp -a $BACKUP_DIR/$latest_backup $REMOTE_DIR" >> "$LOG_FILE" 2>&1; then
        log_success "Files restored from backup"
    else
        log_error "Failed to restore from backup"
        return 1
    fi

    # Fix ownership
    ssh "$VPS_HOST" "sudo chown -R \$USER:\$(id -gn) $REMOTE_DIR" >> "$LOG_FILE" 2>&1

    # Restart services
    log_info "Starting services..."
    if ssh "$VPS_HOST" "cd $REMOTE_DIR && ./jacker start" >> "$LOG_FILE" 2>&1; then
        log_success "Services started"
    else
        log_error "Failed to start services after rollback"
        return 1
    fi

    log_success "Rollback completed successfully"
    return 0
}

automatic_rollback() {
    log_error "Deployment failed, initiating automatic rollback..."

    if perform_rollback; then
        log_success "Automatic rollback completed"
        return 0
    else
        log_error "Automatic rollback failed"
        log_error "Manual intervention required"
        return 1
    fi
}

# ====================================================================
# CLEANUP FUNCTIONS
# ====================================================================

cleanup() {
    log_debug "Cleanup complete"
}

# ====================================================================
# REPORT FUNCTIONS
# ====================================================================

print_deployment_summary() {
    local status=$1
    local duration=$2

    echo ""
    echo "========================================"
    echo "Deployment Summary"
    echo "========================================"
    echo "Status:        $status"
    echo "VPS Host:      $VPS_HOST"
    echo "Remote Dir:    $REMOTE_DIR"
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Duration:      ${duration}s"
    echo "Log File:      $LOG_FILE"

    if [[ -n "$BACKUP_NAME" ]]; then
        echo "Backup:        $BACKUP_NAME"
    fi

    echo ""

    if [[ "$status" == "SUCCESS" ]]; then
        log_success "Deployment completed successfully!"
        echo ""
        echo "Next steps:"
        echo "  1. Verify services: ssh $VPS_HOST 'cd $REMOTE_DIR && ./jacker status'"
        echo "  2. Check logs: ssh $VPS_HOST 'cd $REMOTE_DIR && ./jacker logs'"
        echo "  3. Monitor health: ssh $VPS_HOST 'cd $REMOTE_DIR && ./jacker health'"
    else
        log_error "Deployment failed"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Review log file: $LOG_FILE"
        echo "  2. Check remote logs: ssh $VPS_HOST 'cd $REMOTE_DIR && ./jacker logs'"
        echo "  3. Rollback if needed: $SCRIPT_NAME --rollback"
    fi

    echo "========================================"
}

# ====================================================================
# ARGUMENT PARSING
# ====================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--host)
                VPS_HOST="$2"
                shift 2
                ;;
            -d|--remote-dir)
                REMOTE_DIR="$2"
                shift 2
                ;;
            -b|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --rollback)
                ROLLBACK_MODE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# ====================================================================
# MAIN DEPLOYMENT FUNCTION
# ====================================================================

deploy_to_vps() {
    local start_time
    local end_time
    local duration

    start_time=$(date +%s)

    log_step "Jacker VPS Deployment Starting"
    log_info "Version: $VERSION"
    log_info "Target: $VPS_HOST"
    log_info "Remote Directory: $REMOTE_DIR"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi

    # Execute deployment phases
    if ! validate_dependencies; then
        return 1
    fi

    if ! validate_local_environment; then
        return 1
    fi

    if ! test_ssh_connectivity; then
        return 1
    fi

    if ! create_remote_backup; then
        log_error "Backup creation failed"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        else
            log_warn "Continuing due to --force flag"
        fi
    fi

    if ! transfer_files; then
        log_error "File transfer failed"
        return 1
    fi

    if ! set_remote_permissions; then
        log_error "Permission setup failed"
        return 1
    fi

    if ! execute_remote_deployment; then
        log_error "Remote deployment failed"
        automatic_rollback
        return 1
    fi

    if ! validate_remote_deployment; then
        log_error "Deployment validation failed"
        automatic_rollback
        return 1
    fi

    # Calculate duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Success
    cleanup
    print_deployment_summary "SUCCESS" "$duration"
    return 0
}

# ====================================================================
# MAIN ENTRY POINT
# ====================================================================

main() {
    # Parse arguments
    parse_arguments "$@"

    # Initialize logging
    init_logging

    # Handle rollback mode
    if [[ "$ROLLBACK_MODE" == "true" ]]; then
        log_step "Rollback Mode"

        if [[ "$FORCE" != "true" ]]; then
            echo -n "Are you sure you want to rollback? (yes/no): "
            read -r confirm
            if [[ "$confirm" != "yes" ]]; then
                log_info "Rollback cancelled"
                exit 0
            fi
        fi

        if perform_rollback; then
            log_success "Rollback completed"
            exit 0
        else
            log_error "Rollback failed"
            exit 4
        fi
    fi

    # Confirmation prompt for production deployment
    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "You are about to deploy to: $VPS_HOST"
        echo -n "Continue? (yes/no): "
        read -r confirm

        if [[ "$confirm" != "yes" ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Execute deployment
    if deploy_to_vps; then
        exit 0
    else
        exit 3
    fi
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
