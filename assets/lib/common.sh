#!/usr/bin/env bash
#
# common.sh - Common functions library for Jacker scripts
# This file contains shared functions used across all Jacker scripts
#

# Script version (check if already set to avoid readonly variable errors in tests)
if [ -z "${JACKER_VERSION:-}" ]; then
    readonly JACKER_VERSION="2.0.0"
fi

# ============================================================================
# Colors and Formatting
# ============================================================================

# Color codes (check if already set to avoid readonly variable errors in tests)
if [ -z "${RED:-}" ]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m' # No Color

    # Unicode symbols
    readonly CHECK_MARK="✓"
    readonly CROSS_MARK="✗"
    readonly WARNING_SIGN="⚠"
    readonly INFO_SIGN="ℹ"
    readonly ROCKET="🚀"
fi

# ============================================================================
# Output Functions
# ============================================================================

# Print colored output
print_color() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

# Print info message (respects QUIET flag)
info() {
    if [ "${QUIET:-false}" = "true" ]; then
        return
    fi
    print_color "$BLUE" "$INFO_SIGN $*"
}

# Print success message
success() {
    if [ "${QUIET:-false}" = "true" ] && [ "${VERBOSE:-false}" != "true" ]; then
        return
    fi
    print_color "$GREEN" "$CHECK_MARK $*"
}

# Print warning message (always shown)
warning() {
    print_color "$YELLOW" "$WARNING_SIGN $*"
}

# Print error message (always shown)
error() {
    print_color "$RED" "$CROSS_MARK $*" >&2
}

# Print verbose message (only shown with VERBOSE flag)
verbose() {
    if [ "${VERBOSE:-false}" = "true" ]; then
        print_color "$CYAN" "[VERBOSE] $*"
    fi
}

# Print section header
section() {
    echo ""
    echo "=========================================="
    print_color "$CYAN" "  $*"
    echo "=========================================="
    echo ""
}

# Print subsection header
subsection() {
    echo ""
    print_color "$MAGENTA" "→ $*"
    echo ""
}

# ============================================================================
# Path and Environment Functions
# ============================================================================

# Get Jacker root directory
get_jacker_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$script_dir/../.." && pwd)"
}

# Change to Jacker root directory
cd_jacker_root() {
    local jacker_root="$(get_jacker_root)"
    cd "$jacker_root" || {
        error "Failed to change to Jacker root directory: $jacker_root"
        exit 1
    }
}

# Get data directory
get_data_dir() {
    echo "$(get_jacker_root)/data"
}

# Get compose directory
get_compose_dir() {
    echo "$(get_jacker_root)/compose"
}

# Get assets directory
get_assets_dir() {
    echo "$(get_jacker_root)/assets"
}

# ============================================================================
# Environment File Functions
# ============================================================================

# Load .env file
load_env() {
    local env_file="${1:-.env}"

    if [ ! -f "$env_file" ]; then
        error "Environment file not found: $env_file"
        return 1
    fi

    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a

    return 0
}

# Check if .env exists
check_env_exists() {
    if [ ! -f ".env" ]; then
        error "No .env file found. Please run 'make install' first."
        exit 1
    fi
}

# Get environment variable with default
get_env_var() {
    local var_name="$1"
    local default_value="${2:-}"

    local value="${!var_name}"
    echo "${value:-$default_value}"
}

# Set environment variable in .env file
set_env_var() {
    local var_name="$1"
    local value="$2"
    local env_file="${3:-.env}"

    if grep -q "^$var_name=" "$env_file" 2>/dev/null; then
        sed -i "s|^$var_name=.*|$var_name=$value|" "$env_file"
    else
        echo "$var_name=$value" >> "$env_file"
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate hostname
validate_hostname() {
    local hostname="$1"

    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        error "Invalid hostname format: $hostname"
        error "Use only alphanumeric characters and hyphens."
        return 1
    fi

    return 0
}

# Validate domain
validate_domain() {
    local domain="$1"

    # Allow domains and subdomains (e.g., example.com, sub.example.com, my.sub.example.com)
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid domain format: $domain"
        error "Example: example.com or subdomain.example.com"
        return 1
    fi

    return 0
}

# Validate email
validate_email() {
    local email="$1"

    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: $email"
        return 1
    fi

    return 0
}

# Validate IP address
validate_ip() {
    local ip="$1"

    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        error "Invalid IP address: $ip"
        return 1
    fi

    # Check each octet
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            error "Invalid IP address: $ip (octet $octet > 255)"
            return 1
        fi
    done

    return 0
}

# Validate port number
validate_port() {
    local port="$1"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        error "Invalid port: $port (not a number)"
        return 1
    fi

    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error "Invalid port: $port (must be 1-65535)"
        return 1
    fi

    return 0
}

# ============================================================================
# Docker Functions
# ============================================================================

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
        return 1
    fi

    if ! docker info &> /dev/null; then
        error "Docker daemon is not running or you don't have permission"
        return 1
    fi

    return 0
}

# Check if Docker Compose is installed
check_docker_compose() {
    if ! docker compose version &> /dev/null; then
        error "Docker Compose is not installed"
        return 1
    fi

    return 0
}

# Check if container is running
is_container_running() {
    local container="$1"

    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        return 0
    else
        return 1
    fi
}

# Wait for container to be healthy
wait_for_healthy() {
    local container="$1"
    local max_wait="${2:-60}"
    local interval="${3:-2}"

    info "Waiting for $container to be healthy..."

    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        if docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null | grep -q "healthy"; then
            success "$container is healthy"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    error "$container failed to become healthy within ${max_wait} seconds"
    return 1
}

# Execute command in container
docker_exec() {
    local container="$1"
    shift

    if ! is_container_running "$container"; then
        error "Container $container is not running"
        return 1
    fi

    docker compose exec -T "$container" "$@"
}

# ============================================================================
# Service Management Functions
# ============================================================================

# Start services
start_services() {
    local services="${*:-}"

    info "Starting services${services:+: $services}..."

    if docker compose up -d $services; then
        success "Services started successfully"
        return 0
    else
        error "Failed to start services"
        return 1
    fi
}

# Stop services
stop_services() {
    local services="${*:-}"

    info "Stopping services${services:+: $services}..."

    if docker compose down $services; then
        success "Services stopped successfully"
        return 0
    else
        error "Failed to stop services"
        return 1
    fi
}

# Restart services
restart_services() {
    local services="${*:-}"

    info "Restarting services${services:+: $services}..."

    if docker compose restart $services; then
        success "Services restarted successfully"
        return 0
    else
        error "Failed to restart services"
        return 1
    fi
}

# Pull latest images
pull_images() {
    local services="${*:-}"

    info "Pulling latest images${services:+: $services}..."

    if docker compose pull $services; then
        success "Images pulled successfully"
        return 0
    else
        error "Failed to pull images"
        return 1
    fi
}

# ============================================================================
# System Functions
# ============================================================================

# Detect operating system
detect_os() {
    local os=""
    local dist=""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os="${ID,,}"
        dist="${VERSION_CODENAME:-${VERSION_ID}}"
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        os="${DISTRIB_ID,,}"
        dist="${DISTRIB_CODENAME}"
    elif command -v lsb_release &> /dev/null; then
        os="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
        dist="$(lsb_release -sc)"
    else
        error "Unable to detect operating system"
        return 1
    fi

    echo "$os:$dist"
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Require root privileges
require_root() {
    if ! check_root; then
        error "This script must be run with root privileges"
        error "Please run with sudo or as root user"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    local min_memory="${1:-2097152}"  # 2GB in KB
    local min_disk="${2:-20}"  # 20GB

    # Check memory
    local total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [ "$total_memory" -lt "$min_memory" ]; then
        warning "System has less than recommended memory"
        warning "Available: $((total_memory / 1024))MB, Recommended: $((min_memory / 1024))MB"
    fi

    # Check disk space
    local available_disk=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
    if [ "$available_disk" -lt "$min_disk" ]; then
        warning "System has less than recommended disk space"
        warning "Available: ${available_disk}GB, Recommended: ${min_disk}GB"
    fi

    return 0
}

# ============================================================================
# User Interaction Functions
# ============================================================================

# Prompt for input with default value
prompt_with_default() {
    local prompt_text="$1"
    local default_value="$2"
    local response

    if [ -n "$default_value" ]; then
        read -r -p "$prompt_text [$default_value]: " response
        echo "${response:-$default_value}"
    else
        read -r -p "$prompt_text: " response
        echo "$response"
    fi
}

# Confirm action
confirm_action() {
    local prompt_text="$1"
    local default="${2:-N}"
    local response

    if [ "$default" = "Y" ]; then
        read -r -p "$prompt_text [Y/n]: " response
        case "${response:-Y}" in
            [nN][oO]|[nN]) return 1 ;;
            *) return 0 ;;
        esac
    else
        read -r -p "$prompt_text [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# Select from menu
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    echo "$prompt"
    select opt in "${options[@]}"; do
        if [ -n "$opt" ]; then
            echo "$opt"
            return 0
        else
            error "Invalid selection"
        fi
    done
}

# ============================================================================
# File and Directory Functions
# ============================================================================

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            error "Failed to create directory: $dir"
            return 1
        }
    fi

    return 0
}

# Backup file
backup_file() {
    local file="$1"
    local backup_suffix="${2:-.backup-$(date +%Y%m%d-%H%M%S)}"

    if [ ! -f "$file" ]; then
        warning "File does not exist: $file"
        return 1
    fi

    cp "$file" "${file}${backup_suffix}" || {
        error "Failed to backup file: $file"
        return 1
    }

    success "Backed up: $file -> ${file}${backup_suffix}"
    return 0
}

# Create file from template
create_from_template() {
    local template="$1"
    local output="$2"

    if [ ! -f "$template" ]; then
        error "Template file not found: $template"
        return 1
    fi

    envsubst < "$template" > "$output" || {
        error "Failed to create file from template"
        return 1
    }

    success "Created: $output"
    return 0
}

# ============================================================================
# Logging Functions
# ============================================================================

# Initialize logging
init_logging() {
    local log_dir="${1:-$(get_jacker_root)/logs}"
    local log_file="${2:-jacker-$(date +%Y%m%d-%H%M%S).log}"

    ensure_dir "$log_dir"

    export JACKER_LOG_FILE="$log_dir/$log_file"

    # Redirect stdout and stderr to log file while keeping console output
    exec 1> >(tee -a "$JACKER_LOG_FILE")
    exec 2>&1

    info "Logging to: $JACKER_LOG_FILE"
}

# Log message
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[$timestamp] [$level] $message" >> "${JACKER_LOG_FILE:-/dev/null}"

    case "$level" in
        ERROR) error "$message" ;;
        WARNING) warning "$message" ;;
        INFO) info "$message" ;;
        SUCCESS) success "$message" ;;
        *) echo "$message" ;;
    esac
}

# ============================================================================
# Utility Functions
# ============================================================================

# Generate random password
generate_password() {
    local length="${1:-32}"
    openssl rand -hex "$length" | head -c "$length"
}

# Get current timestamp
timestamp() {
    date +%Y%m%d-%H%M%S
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Run command with retry
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local command="$*"
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        if eval "$command"; then
            return 0
        fi

        warning "Command failed (attempt $attempt/$max_attempts): $command"

        if [ "$attempt" -lt "$max_attempts" ]; then
            info "Retrying in ${delay} seconds..."
            sleep "$delay"
        fi

        attempt=$((attempt + 1))
    done

    error "Command failed after $max_attempts attempts: $command"
    return 1
}

# Validate Docker service name
validate_service_name() {
    local service="$1"

    if [ -z "$service" ]; then
        error "Service name is required"
        return 1
    fi

    # Get list of available services
    local available_services
    available_services=$(docker compose config --services 2>/dev/null)

    if [ -z "$available_services" ]; then
        error "No services defined in docker-compose.yml"
        return 1
    fi

    # Check if service exists
    if ! echo "$available_services" | grep -q "^${service}$"; then
        error "Service '$service' not found"
        info "Available services:"
        echo "$available_services" | sed 's/^/  - /' | while IFS= read -r line; do
            echo "$line"
        done
        return 1
    fi

    return 0
}


# Check if in dry run mode
is_dry_run() {
    [ "${DRY_RUN:-false}" = "true" ]
}

# Execute command or show in dry run mode
execute_or_dry_run() {
    local cmd="$*"

    if is_dry_run; then
        info "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        verbose "Executing: $cmd"
        eval "$cmd"
        return $?
    fi
}

# Load user configuration if exists
load_user_config() {
    local config_file="${JACKER_CONFIG:-$HOME/.jackerrc}"

    if [ -f "$config_file" ]; then
        verbose "Loading user config from: $config_file"
        # shellcheck source=/dev/null
        source "$config_file"
    fi
}

# Export all functions
export -f print_color info success warning error section subsection verbose
export -f get_jacker_root cd_jacker_root get_data_dir get_compose_dir get_assets_dir
export -f load_env check_env_exists get_env_var set_env_var
export -f validate_hostname validate_domain validate_email validate_ip validate_port
export -f check_docker check_docker_compose is_container_running wait_for_healthy docker_exec
export -f start_services stop_services restart_services pull_images
export -f detect_os check_root require_root check_requirements
export -f prompt_with_default confirm_action select_option
export -f ensure_dir backup_file create_from_template
export -f init_logging log
export -f generate_password timestamp command_exists retry_command
export -f validate_service_name is_dry_run execute_or_dry_run load_user_config