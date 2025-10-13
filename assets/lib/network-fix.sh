#!/usr/bin/env bash
#
# network-fix.sh - Fix Docker network configuration issues
#

# Determine script directory and set JACKER_DIR
if [[ -z "${JACKER_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    export JACKER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Also set JACKER_ROOT for compatibility
export JACKER_ROOT="${JACKER_DIR}"

# Source common functions
source "${JACKER_DIR}/assets/lib/common.sh"

# Fix PostgreSQL multiple network issue
fix_postgres_networks() {
    info "Fixing PostgreSQL network configuration..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if ! docker info &>/dev/null; then
        docker_cmd="sudo docker"
    fi

    # Stop and remove postgres container if it exists
    if $docker_cmd ps -a | grep -q postgres; then
        info "Stopping PostgreSQL container..."
        $docker_cmd stop postgres 2>/dev/null || true
        $docker_cmd rm postgres 2>/dev/null || true
    fi

    # Ensure all required networks exist
    info "Ensuring networks exist..."
    for network in database monitoring backup; do
        if ! $docker_cmd network ls | grep -q "$network"; then
            info "Creating network: $network"
            $docker_cmd network create "$network" 2>/dev/null || true
        fi
    done

    # Create temporary override file to start with single network
    cat > "${JACKER_DIR}/docker-compose.override.yml" <<EOF
services:
  postgres:
    networks:
      - database
EOF

    # Start postgres with single network
    info "Starting PostgreSQL with single network..."
    $docker_cmd compose up -d postgres

    # Wait a moment for container to be created
    sleep 2

    # Connect to additional networks
    info "Connecting PostgreSQL to additional networks..."
    for network in monitoring backup; do
        $docker_cmd network connect "$network" postgres 2>/dev/null || {
            warning "Failed to connect to network: $network"
        }
    done

    # Remove override file
    rm -f "${JACKER_DIR}/docker-compose.override.yml"

    # Restart postgres to apply all configurations
    info "Restarting PostgreSQL to apply configuration..."
    $docker_cmd compose restart postgres

    success "PostgreSQL network configuration fixed!"
}

# Fix all network-related issues
fix_all_networks() {
    section "Fixing Network Issues"

    # Fix PostgreSQL
    fix_postgres_networks

    # Check other services that might have network issues
    local docker_cmd="docker"
    if ! docker info &>/dev/null; then
        docker_cmd="sudo docker"
    fi

    # Ensure all services are connected to their networks
    info "Verifying all service network connections..."

    # Get list of running containers
    local containers=$($docker_cmd ps --format "{{.Names}}")

    for container in $containers; do
        # Get expected networks from docker-compose
        local expected_networks=$($docker_cmd compose config --services 2>/dev/null | \
            xargs -I {} $docker_cmd compose config | \
            grep -A 10 "^  $container:" | \
            grep -A 5 "networks:" | \
            grep "^      - " | \
            sed 's/^      - //')

        # Get actual networks
        local actual_networks=$($docker_cmd inspect "$container" --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}')

        # Connect missing networks
        for network in $expected_networks; do
            if ! echo "$actual_networks" | grep -q "$network"; then
                info "Connecting $container to network: $network"
                $docker_cmd network connect "$network" "$container" 2>/dev/null || true
            fi
        done
    done

    success "All network issues fixed!"
}

# Main function
main() {
    case "${1:-}" in
        postgres)
            fix_postgres_networks
            ;;
        all)
            fix_all_networks
            ;;
        *)
            echo "Usage: $0 {postgres|all}"
            echo ""
            echo "Commands:"
            echo "  postgres  - Fix PostgreSQL network configuration"
            echo "  all       - Fix all network issues"
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

# Export functions
export -f fix_postgres_networks fix_all_networks