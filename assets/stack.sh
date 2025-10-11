#!/usr/bin/env bash

#================================================================
# JACKER STACK - CLI Interface
#================================================================
#% DESCRIPTION
#%    Jacker Stack Manager - Browse, install, and manage Docker stacks
#%
#% USAGE
#%    stack.sh [COMMAND] [OPTIONS]
#%
#% COMMANDS
#%    list              List all available stacks
#%    search <query>    Search for stacks
#%    info <stack>      Show detailed information about a stack
#%    install <stack>   Install a stack
#%    uninstall <stack> Uninstall a stack
#%    installed         List installed stacks
#%    repos             List configured repositories
#%    repo-add <url>    Add a stack repository
#%    repo-remove <name> Remove a stack repository
#%
#% SYSTEMD COMMANDS
#%    systemd-create <stack>  Create systemd service for a stack
#%    systemd-remove <stack>  Remove systemd service
#%    systemd-enable <stack>  Enable systemd service (auto-start on boot)
#%    systemd-disable <stack> Disable systemd service
#%    systemd-start <stack>   Start systemd service
#%    systemd-stop <stack>    Stop systemd service
#%    systemd-restart <stack> Restart systemd service
#%    systemd-status <stack>  Show systemd service status
#%    systemd-logs <stack> [lines] View systemd service logs
#%    systemd-list            List all Jacker systemd services
#%
#% OPTIONS
#%    -h, --help        Display this help message
#%    -v, --verbose     Enable verbose output
#%
#================================================================

set -euo pipefail

# Script directory and library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/stacks.sh"

# All colors are defined in common.sh (BLUE, GREEN, YELLOW, CYAN, MAGENTA, NC, etc.)

# Initialize stack directories
init_stack_dirs

#================================================================
# UI FUNCTIONS
#================================================================

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  🎯 Jacker Stack Manager${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_help() {
    sed -n '/^#%/s/^#% \?//p' "$0"
}

#================================================================
# COMMAND IMPLEMENTATIONS
#================================================================

cmd_list() {
    print_header
    echo -e "${CYAN}Available Stacks:${NC}"
    echo ""

    local current_category=""
    local count=0

    while IFS='|' read -r stack_path description source; do
        if [[ -z "$stack_path" ]]; then
            continue
        fi

        local category="$(echo "$stack_path" | cut -d'/' -f1)"
        local stack_name="$(echo "$stack_path" | cut -d'/' -f2)"

        # Print category header
        if [[ "$category" != "$current_category" ]]; then
            [[ -n "$current_category" ]] && echo ""
            echo -e "${MAGENTA}📁 $category${NC}"
            current_category="$category"
        fi

        # Check if installed
        local installed_marker=""
        if is_stack_installed "$stack_name"; then
            installed_marker=" ${GREEN}[installed]${NC}"
        fi

        echo -e "  ${CYAN}•${NC} $stack_name$installed_marker"
        [[ -n "$description" ]] && echo -e "    ${NC}$description${NC}"

        ((count++))
    done < <(list_stacks_simple)

    echo ""
    echo -e "${BLUE}Total: $count stacks${NC}"
    echo ""
}

cmd_search() {
    local query="$1"

    print_header
    echo -e "${CYAN}Search results for: ${YELLOW}$query${NC}"
    echo ""

    local count=0

    while IFS='|' read -r stack_path description source; do
        if [[ -z "$stack_path" ]]; then
            continue
        fi

        local stack_name="$(basename "$stack_path")"

        # Check if installed
        local installed_marker=""
        if is_stack_installed "$stack_name"; then
            installed_marker=" ${GREEN}[installed]${NC}"
        fi

        echo -e "  ${CYAN}•${NC} $stack_name ($stack_path)$installed_marker"
        [[ -n "$description" ]] && echo -e "    $description"
        echo ""

        ((count++))
    done < <(search_stacks_simple "$query")

    echo -e "${BLUE}Found: $count stacks${NC}"
    echo ""
}

cmd_info() {
    local stack_name="$1"

    local info="$(get_stack_info "$stack_name")"
    if [[ -z "$info" ]]; then
        error "Stack '$stack_name' not found"
        return 1
    fi

    IFS='|' read -r stack_path readme services <<< "$info"

    print_header
    echo -e "${CYAN}Stack Information: ${YELLOW}$stack_name${NC}"
    echo ""

    # Show README
    if [[ -n "$readme" ]]; then
        echo -e "${BLUE}Description:${NC}"
        echo "$readme"
        echo ""
    fi

    # Show services
    if [[ -n "$services" ]]; then
        echo -e "${BLUE}Services:${NC}"
        for service in $services; do
            echo "  • $service"
        done
        echo ""
    fi

    # Show installation status
    if is_stack_installed "$stack_name"; then
        echo -e "${GREEN}✓ Installed${NC} at: $(get_installed_dir)/$stack_name"
    else
        echo -e "${YELLOW}○ Not installed${NC}"
    fi

    echo ""
}

cmd_install() {
    local stack_name="$1"
    local custom_name="${2:-$stack_name}"

    install_stack "$stack_name" "$custom_name"

    echo ""
    info "Next steps:"
    echo "  1. cd $(get_installed_dir)/$custom_name"
    echo "  2. Edit .env file with your settings"
    echo "  3. docker compose up -d"
    echo ""
}

cmd_uninstall() {
    local stack_name="$1"

    # Confirm
    echo -e "${YELLOW}⚠ This will remove the stack and all its data${NC}"
    if ! confirm_action "Are you sure you want to uninstall '$stack_name'?"; then
        warning "Uninstall cancelled"
        return 0
    fi

    uninstall_stack "$stack_name"
}

cmd_installed() {
    print_header
    echo -e "${CYAN}Installed Stacks:${NC}"
    echo ""

    local count=0
    while IFS='|' read -r stack_name stack_path status; do
        if [[ -z "$stack_name" ]]; then
            continue
        fi

        local status_display="${YELLOW}○ stopped${NC}"
        [[ "$status" == "running" ]] && status_display="${GREEN}● running${NC}"

        echo -e "  ${CYAN}•${NC} $stack_name - $status_display"
        echo -e "    📍 $stack_path"

        ((count++))
    done < <(list_installed_stacks)

    if [[ $count -eq 0 ]]; then
        echo -e "  ${YELLOW}No stacks installed${NC}"
    fi

    echo ""
    echo -e "${BLUE}Total: $count installed${NC}"
    echo ""
}

cmd_repos() {
    print_header
    echo -e "${CYAN}Configured Stack Repositories:${NC}"
    echo ""

    local count=1
    while IFS='|' read -r name type enabled; do
        if [[ -z "$name" ]]; then
            continue
        fi

        local status="${GREEN}✓ enabled${NC}"
        [[ "$enabled" == "false" ]] && status="${YELLOW}○ disabled${NC}"

        echo -e "  ${count}. ${CYAN}$name${NC} ($type) - $status"
        ((count++))
    done < <(list_repos)

    echo ""
}

cmd_repo_add() {
    local url="$1"
    add_repo "$url"
}

cmd_repo_remove() {
    local name="$1"
    remove_repo "$name"
}

cmd_systemd_create() {
    local stack_name="$1"
    systemd_create_service "$stack_name"
    info "To enable auto-start: stack.sh systemd-enable $stack_name"
    info "To start the service: stack.sh systemd-start $stack_name"
    echo ""
}

cmd_systemd_remove() {
    local stack_name="$1"
    systemd_remove_service "$stack_name"
}

cmd_systemd_enable() {
    local stack_name="$1"
    systemd_enable_service "$stack_name"
}

cmd_systemd_disable() {
    local stack_name="$1"
    systemd_disable_service "$stack_name"
}

cmd_systemd_start() {
    local stack_name="$1"
    systemd_start_service "$stack_name"
}

cmd_systemd_stop() {
    local stack_name="$1"
    systemd_stop_service "$stack_name"
}

cmd_systemd_restart() {
    local stack_name="$1"
    systemd_restart_service "$stack_name"
}

cmd_systemd_status() {
    local stack_name="$1"
    systemd_status_service "$stack_name"
}

cmd_systemd_logs() {
    local stack_name="$1"
    local lines="${2:-100}"
    systemd_logs_service "$stack_name" "$lines"
}

cmd_systemd_list() {
    print_header
    echo -e "${CYAN}Jacker Systemd Services:${NC}"
    echo ""

    local count=0
    while IFS='|' read -r stack_name service enabled active; do
        if [[ -z "$stack_name" ]]; then
            continue
        fi

        local status_color=$YELLOW
        [[ "$active" == "active" ]] && status_color=$GREEN
        [[ "$active" == "failed" ]] && status_color='\033[0;31m'

        local enabled_marker=""
        [[ "$enabled" == "enabled" ]] && enabled_marker="${GREEN}[auto-start]${NC}"

        echo -e "  ${CYAN}•${NC} $stack_name - ${status_color}$active${NC} $enabled_marker"
        ((count++))
    done < <(systemd_list_services)

    if [[ $count -eq 0 ]]; then
        echo -e "  ${YELLOW}No systemd services found${NC}"
    fi

    echo ""
    echo -e "${BLUE}Total: $count services${NC}"
    echo ""
}

#================================================================
# MAIN
#================================================================

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        list|ls)
            cmd_list
            ;;
        search)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh search <query>"; exit 1; }
            cmd_search "$1"
            ;;
        info)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh info <stack>"; exit 1; }
            cmd_info "$1"
            ;;
        install)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh install <stack> [custom-name]"; exit 1; }
            cmd_install "$1" "${2:-$1}"
            ;;
        uninstall|remove)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh uninstall <stack>"; exit 1; }
            cmd_uninstall "$1"
            ;;
        installed)
            cmd_installed
            ;;
        repos)
            cmd_repos
            ;;
        repo-add)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh repo-add <url>"; exit 1; }
            cmd_repo_add "$1"
            ;;
        repo-remove)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh repo-remove <name>"; exit 1; }
            cmd_repo_remove "$1"
            ;;
        systemd-create)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-create <stack>"; exit 1; }
            cmd_systemd_create "$1"
            ;;
        systemd-remove)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-remove <stack>"; exit 1; }
            cmd_systemd_remove "$1"
            ;;
        systemd-enable)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-enable <stack>"; exit 1; }
            cmd_systemd_enable "$1"
            ;;
        systemd-disable)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-disable <stack>"; exit 1; }
            cmd_systemd_disable "$1"
            ;;
        systemd-start)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-start <stack>"; exit 1; }
            cmd_systemd_start "$1"
            ;;
        systemd-stop)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-stop <stack>"; exit 1; }
            cmd_systemd_stop "$1"
            ;;
        systemd-restart)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-restart <stack>"; exit 1; }
            cmd_systemd_restart "$1"
            ;;
        systemd-status)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-status <stack>"; exit 1; }
            cmd_systemd_status "$1"
            ;;
        systemd-logs)
            [[ -z "${1:-}" ]] && { error "Usage: stack.sh systemd-logs <stack> [lines]"; exit 1; }
            cmd_systemd_logs "$1" "${2:-100}"
            ;;
        systemd-list)
            cmd_systemd_list
            ;;
        -h|--help|help)
            show_help
            ;;
        *)
            error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"
