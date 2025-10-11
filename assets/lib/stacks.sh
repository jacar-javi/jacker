#!/usr/bin/env bash
#
# stacks.sh - Jacker Stack Management Library
# Provides functions for managing Docker stacks
#

# Check if already sourced
if [ -n "${JACKER_STACKS_LIB_LOADED:-}" ]; then
    return 0
fi
readonly JACKER_STACKS_LIB_LOADED=1

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/common.sh"

#================================================================
# CONFIGURATION
#================================================================

# Get stack directories
get_stacks_dir() {
    local jacker_root="$(get_jacker_root)"
    echo "$jacker_root/jacker-stacks"
}

get_installed_dir() {
    local jacker_root="$(get_jacker_root)"
    echo "$jacker_root/stacks"
}

get_config_dir() {
    local jacker_root="$(get_jacker_root)"
    echo "$jacker_root/.jacker"
}

get_repos_file() {
    echo "$(get_config_dir)/repositories.json"
}

# Ensure stack directories exist
init_stack_dirs() {
    ensure_dir "$(get_installed_dir)"
    ensure_dir "$(get_config_dir)"
}

#================================================================
# REPOSITORY FUNCTIONS
#================================================================

init_default_repos() {
    local repos_file="$(get_repos_file)"

    if [[ -f "$repos_file" ]]; then
        return 0
    fi

    cat > "$repos_file" << 'EOF'
{
  "repositories": [
    {
      "name": "jacker-stacks",
      "type": "local",
      "path": "./jacker-stacks",
      "enabled": true
    },
    {
      "name": "awesome-compose",
      "type": "git",
      "url": "https://github.com/docker/awesome-compose",
      "enabled": false
    },
    {
      "name": "compose-examples",
      "type": "git",
      "url": "https://github.com/Haxxnet/Compose-Examples",
      "enabled": false
    }
  ]
}
EOF
}

list_repos() {
    init_default_repos
    local repos_file="$(get_repos_file)"

    if ! command_exists jq; then
        error "jq is required for repository management"
        return 1
    fi

    # Parse and return repo information
    jq -r '.repositories[] | "\(.name)|\(.type)|\(.enabled)"' "$repos_file"
}

add_repo() {
    local url="$1"
    local name="$(basename "$url" .git)"
    local repos_file="$(get_repos_file)"

    init_default_repos

    if ! command_exists jq; then
        error "jq is required for repository management"
        return 1
    fi

    # Check if already exists
    if jq -e ".repositories[] | select(.name==\"$name\")" "$repos_file" >/dev/null 2>&1; then
        error "Repository '$name' already exists"
        return 1
    fi

    # Add to repos file
    local tmp="$(mktemp)"
    jq ".repositories += [{\"name\": \"$name\", \"type\": \"git\", \"url\": \"$url\", \"enabled\": true}]" \
        "$repos_file" > "$tmp"
    mv "$tmp" "$repos_file"

    success "Added repository: $name"
}

remove_repo() {
    local name="$1"
    local repos_file="$(get_repos_file)"

    if ! command_exists jq; then
        error "jq is required for repository management"
        return 1
    fi

    # Remove from repos file
    local tmp="$(mktemp)"
    jq ".repositories |= map(select(.name != \"$name\"))" "$repos_file" > "$tmp"
    mv "$tmp" "$repos_file"

    success "Removed repository: $name"
}

#================================================================
# STACK DISCOVERY FUNCTIONS
#================================================================

find_stacks() {
    local search_query="${1:-}"
    local stacks_dir="$(get_stacks_dir)"

    if [[ ! -d "$stacks_dir" ]]; then
        return 0
    fi

    # Find all docker-compose.yml files
    while IFS= read -r -d '' compose_file; do
        local stack_dir="$(dirname "$compose_file")"
        local stack_name="$(basename "$stack_dir")"
        local category="$(basename "$(dirname "$stack_dir")")"

        # Skip if searching and doesn't match
        if [[ -n "$search_query" ]] && [[ ! "$stack_name" =~ $search_query ]]; then
            continue
        fi

        # Get description from README
        local description=""
        if [[ -f "$stack_dir/README.md" ]]; then
            description="$(head -n 5 "$stack_dir/README.md" | grep -v "^#" | head -n 1 | xargs)"
        fi

        echo "$category/$stack_name|$description|local"
    done < <(find "$stacks_dir" -mindepth 2 -maxdepth 3 -name "docker-compose.yml" -print0 2>/dev/null)
}

list_stacks_simple() {
    find_stacks | sort
}

search_stacks_simple() {
    local query="$1"
    find_stacks "$query"
}

get_stack_path() {
    local stack_name="$1"
    local stacks_dir="$(get_stacks_dir)"

    # Find stack by name
    while IFS='|' read -r path desc source; do
        if [[ "$(basename "$path")" == "$stack_name" ]]; then
            echo "$stacks_dir/$path"
            return 0
        fi
    done < <(find_stacks)

    return 1
}

get_stack_info() {
    local stack_name="$1"
    local stack_path="$(get_stack_path "$stack_name")"

    if [[ -z "$stack_path" ]]; then
        return 1
    fi

    # Return: path|readme|services
    local readme=""
    if [[ -f "$stack_path/README.md" ]]; then
        readme="$(head -n 20 "$stack_path/README.md")"
    fi

    local services=""
    if [[ -f "$stack_path/docker-compose.yml" ]]; then
        services="$(grep "^  [a-zA-Z]" "$stack_path/docker-compose.yml" | sed 's/:$//' | xargs)"
    fi

    echo "$stack_path|$readme|$services"
}

#================================================================
# STACK INSTALLATION FUNCTIONS
#================================================================

install_stack() {
    local stack_name="$1"
    local custom_name="${2:-$stack_name}"
    local install_dir="$(get_installed_dir)"

    # Find stack source
    local stack_source="$(get_stack_path "$stack_name")"
    if [[ -z "$stack_source" ]]; then
        error "Stack '$stack_name' not found"
        return 1
    fi

    local install_path="$install_dir/$custom_name"

    # Check if already installed
    if [[ -d "$install_path" ]]; then
        error "Stack '$custom_name' is already installed"
        return 1
    fi

    info "Installing stack: $stack_name → $custom_name"

    # Copy stack files
    cp -r "$stack_source" "$install_path"

    # Create .env if doesn't exist
    if [[ ! -f "$install_path/.env" ]] && [[ -f "$install_path/.env.sample" ]]; then
        cp "$install_path/.env.sample" "$install_path/.env"
        warning "Created .env from .env.sample - please configure it"
    fi

    success "Stack installed: $custom_name"
    info "Location: $install_path"
}

uninstall_stack() {
    local stack_name="$1"
    local install_dir="$(get_installed_dir)"
    local install_path="$install_dir/$stack_name"

    if [[ ! -d "$install_path" ]]; then
        error "Stack '$stack_name' is not installed"
        return 1
    fi

    # Stop containers first
    if [[ -f "$install_path/docker-compose.yml" ]]; then
        info "Stopping containers..."
        (cd "$install_path" && docker compose down 2>/dev/null) || true
    fi

    # Remove directory
    rm -rf "$install_path"

    success "Stack uninstalled: $stack_name"
}

list_installed_stacks() {
    local install_dir="$(get_installed_dir)"

    if [[ ! -d "$install_dir" ]] || [[ -z "$(ls -A "$install_dir" 2>/dev/null)" ]]; then
        return 0
    fi

    for stack_dir in "$install_dir"/*; do
        if [[ -d "$stack_dir" ]]; then
            local stack_name="$(basename "$stack_dir")"

            # Check if running
            local status="stopped"
            if [[ -f "$stack_dir/docker-compose.yml" ]]; then
                if (cd "$stack_dir" && docker compose ps --format json 2>/dev/null | jq -e '. | length > 0' >/dev/null 2>&1); then
                    status="running"
                fi
            fi

            echo "$stack_name|$stack_dir|$status"
        fi
    done
}

is_stack_installed() {
    local stack_name="$1"
    local install_dir="$(get_installed_dir)"
    [[ -d "$install_dir/$stack_name" ]]
}

#================================================================
# SYSTEMD SERVICE FUNCTIONS
#================================================================

get_systemd_service_name() {
    local stack_name="$1"
    echo "jacker-${stack_name}.service"
}

get_systemd_service_path() {
    local stack_name="$1"
    echo "/etc/systemd/system/$(get_systemd_service_name "$stack_name")"
}

systemd_service_exists() {
    local stack_name="$1"
    [[ -f "$(get_systemd_service_path "$stack_name")" ]]
}

systemd_create_service() {
    local stack_name="$1"
    local install_dir="$(get_installed_dir)"
    local install_path="$install_dir/$stack_name"

    if [[ ! -d "$install_path" ]]; then
        error "Stack '$stack_name' is not installed"
        return 1
    fi

    local service_name="$(get_systemd_service_name "$stack_name")"
    local service_file="$(get_systemd_service_path "$stack_name")"

    info "Creating systemd service: $service_name"

    # Get stack metadata
    local stack_display_name="$stack_name"
    local stack_description="Jacker Stack"

    if [[ -f "$install_path/stack.yml" ]]; then
        stack_display_name="$(grep "^display_name:" "$install_path/stack.yml" | cut -d'"' -f2 || echo "$stack_name")"
        stack_description="$(grep "^description:" "$install_path/stack.yml" | cut -d'"' -f2 || echo "Jacker Stack")"
    fi

    # Create systemd service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=$stack_display_name - Jacker Stack
Documentation=https://jacker.jacar.es
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$install_path
Environment="COMPOSE_PROJECT_NAME=$stack_name"
$(if [[ -f "$install_path/.env" ]]; then echo "EnvironmentFile=$install_path/.env"; fi)

ExecStartPre=-/usr/bin/bash -c 'if [ -x $install_path/scripts/pre-start.sh ]; then $install_path/scripts/pre-start.sh; fi'
ExecStartPre=/usr/bin/docker compose -f $install_path/docker-compose.yml config --quiet
ExecStart=/usr/bin/docker compose -f $install_path/docker-compose.yml up -d --remove-orphans
ExecStartPost=-/usr/bin/bash -c 'if [ -x $install_path/scripts/post-start.sh ]; then $install_path/scripts/post-start.sh; fi'

ExecStop=-/usr/bin/bash -c 'if [ -x $install_path/scripts/pre-stop.sh ]; then $install_path/scripts/pre-stop.sh; fi'
ExecStop=/usr/bin/docker compose -f $install_path/docker-compose.yml down
ExecStopPost=-/usr/bin/bash -c 'if [ -x $install_path/scripts/post-stop.sh ]; then $install_path/scripts/post-stop.sh; fi'

ExecReload=/usr/bin/docker compose -f $install_path/docker-compose.yml up -d --force-recreate

Restart=on-failure
RestartSec=10s
TimeoutStartSec=120s
TimeoutStopSec=60s

StandardOutput=journal
StandardError=journal
SyslogIdentifier=jacker-$stack_name

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    success "Systemd service created: $service_name"
}

systemd_remove_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"
    local service_file="$(get_systemd_service_path "$stack_name")"

    if [[ ! -f "$service_file" ]]; then
        error "Service not found: $service_name"
        return 1
    fi

    info "Removing systemd service: $service_name"

    sudo systemctl stop "$service_name" 2>/dev/null || true
    sudo systemctl disable "$service_name" 2>/dev/null || true
    sudo rm "$service_file"
    sudo systemctl daemon-reload

    success "Systemd service removed: $service_name"
}

systemd_enable_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl enable "$service_name"
    success "Service enabled: $service_name"
}

systemd_disable_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl disable "$service_name"
    success "Service disabled: $service_name"
}

systemd_start_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl start "$service_name"

    if sudo systemctl is-active --quiet "$service_name"; then
        success "Service started: $service_name"
    else
        error "Failed to start service: $service_name"
        return 1
    fi
}

systemd_stop_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl stop "$service_name"
    success "Service stopped: $service_name"
}

systemd_restart_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl restart "$service_name"

    if sudo systemctl is-active --quiet "$service_name"; then
        success "Service restarted: $service_name"
    else
        error "Failed to restart service: $service_name"
        return 1
    fi
}

systemd_status_service() {
    local stack_name="$1"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo systemctl status "$service_name" --no-pager
}

systemd_logs_service() {
    local stack_name="$1"
    local lines="${2:-100}"
    local service_name="$(get_systemd_service_name "$stack_name")"

    if ! systemd_service_exists "$stack_name"; then
        error "Service not found: $service_name"
        return 1
    fi

    sudo journalctl -u "$service_name" -n "$lines" --no-pager
}

systemd_list_services() {
    systemctl list-unit-files "jacker-*.service" --no-legend 2>/dev/null | awk '{print $1}' | while read -r service; do
        if [[ -n "$service" ]]; then
            local stack_name="$(echo "$service" | sed 's/jacker-//;s/.service//')"
            local enabled="$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")"
            local active="$(systemctl is-active "$service" 2>/dev/null || echo "inactive")"
            echo "$stack_name|$service|$enabled|$active"
        fi
    done
}

# Export functions
export -f get_stacks_dir get_installed_dir get_config_dir get_repos_file init_stack_dirs
export -f init_default_repos list_repos add_repo remove_repo
export -f find_stacks list_stacks_simple search_stacks_simple get_stack_path get_stack_info
export -f install_stack uninstall_stack list_installed_stacks is_stack_installed
export -f get_systemd_service_name get_systemd_service_path systemd_service_exists
export -f systemd_create_service systemd_remove_service systemd_enable_service systemd_disable_service
export -f systemd_start_service systemd_stop_service systemd_restart_service
export -f systemd_status_service systemd_logs_service systemd_list_services
