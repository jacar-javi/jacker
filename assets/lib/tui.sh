#!/usr/bin/env bash
#
# tui.sh - Whiptail/Dialog TUI library for Jacker
# Provides interactive menu-driven interface for all Jacker operations
#

# ============================================================================
# Global Variables
# ============================================================================

# Dialog command (set by init_tui)
TUI_CMD=""

# Dialog dimensions
TUI_HEIGHT=20
TUI_WIDTH=70
TUI_MENU_HEIGHT=12
TUI_LIST_HEIGHT=10

# Backtitle for all dialogs
TUI_BACKTITLE="Jacker - Docker Home Server Management Platform v${VERSION}"

# Temp file for dialog output
TUI_TEMP_FILE="/tmp/jacker-tui-$$"

# Cleanup on exit
trap 'rm -f "$TUI_TEMP_FILE"' EXIT

# ============================================================================
# Initialization
# ============================================================================

# Initialize TUI - detect dialog/whiptail
init_tui() {
    # Check for dialog first (preferred)
    if command -v dialog &>/dev/null; then
        TUI_CMD="dialog"
    elif command -v whiptail &>/dev/null; then
        TUI_CMD="whiptail"
    else
        error "Neither dialog nor whiptail found"
        error "Please install dialog: sudo apt-get install dialog"
        return 1
    fi

    # Ensure temp file is clean
    rm -f "$TUI_TEMP_FILE"

    return 0
}

# ============================================================================
# Core Dialog Wrapper Functions
# ============================================================================

# Show message box
# Usage: show_msgbox "Title" "Message" [height] [width]
show_msgbox() {
    local title="$1"
    local message="$2"
    local height="${3:-10}"
    local width="${4:-60}"

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --msgbox "$message" "$height" "$width" 2>&1 >/dev/tty
}

# Show yes/no dialog
# Usage: show_yesno "Title" "Question" [height] [width]
# Returns: 0 for yes, 1 for no
show_yesno() {
    local title="$1"
    local question="$2"
    local height="${3:-8}"
    local width="${4:-60}"

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --yesno "$question" "$height" "$width" 2>&1 >/dev/tty
    return $?
}

# Show input box
# Usage: result=$(show_inputbox "Title" "Prompt" "Default Value" [height] [width])
show_inputbox() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    local height="${4:-10}"
    local width="${5:-60}"

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --inputbox "$prompt" "$height" "$width" "$default" \
             2>&1 >/dev/tty
}

# Show menu
# Usage: choice=$(show_menu "Title" "Prompt" menu_item1 menu_desc1 menu_item2 menu_desc2 ...)
show_menu() {
    local title="$1"
    local prompt="$2"
    shift 2

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --menu "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$TUI_MENU_HEIGHT" \
             "$@" \
             2>&1 >/dev/tty
}

# Show checklist
# Usage: selected=$(show_checklist "Title" "Prompt" tag1 item1 status1 tag2 item2 status2 ...)
# Returns: Space-separated list of selected tags
show_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --checklist "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$TUI_LIST_HEIGHT" \
             "$@" \
             2>&1 >/dev/tty
}

# Show radiolist
# Usage: selected=$(show_radiolist "Title" "Prompt" tag1 item1 status1 tag2 item2 status2 ...)
show_radiolist() {
    local title="$1"
    local prompt="$2"
    shift 2

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --radiolist "$prompt" "$TUI_HEIGHT" "$TUI_WIDTH" "$TUI_LIST_HEIGHT" \
             "$@" \
             2>&1 >/dev/tty
}

# Show progress gauge
# Usage: some_command | show_gauge "Title" "Message" [height] [width]
show_gauge() {
    local title="$1"
    local message="$2"
    local height="${3:-8}"
    local width="${4:-60}"

    $TUI_CMD --backtitle "$TUI_BACKTITLE" \
             --title "$title" \
             --gauge "$message" "$height" "$width" 0 2>&1 >/dev/tty
}

# ============================================================================
# Service Helper Functions
# ============================================================================

# Get list of all services from docker-compose
get_services_list() {
    docker compose config --services 2>/dev/null | sort
}

# Get list of running services
get_running_services() {
    docker compose ps --format "{{.Service}}" --status running 2>/dev/null | sort
}

# Build checklist items for services
# Usage: build_services_checklist [default_status]
# Returns: Checklist arguments (tag item status tag item status ...)
build_services_checklist() {
    local default_status="${1:-off}"
    local services
    services=$(get_services_list)

    local items=()
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        items+=("$service" "$service" "$default_status")
    done <<< "$services"

    echo "${items[@]}"
}

# Build radiolist items for services
# Usage: build_services_radiolist [default_selected]
build_services_radiolist() {
    local default_selected="${1:-}"
    local services
    services=$(get_services_list)

    local items=()
    local first=true
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if [[ "$service" == "$default_selected" ]] || { [[ -z "$default_selected" ]] && $first; }; then
            items+=("$service" "$service" "on")
            first=false
        else
            items+=("$service" "$service" "off")
        fi
    done <<< "$services"

    echo "${items[@]}"
}

# ============================================================================
# Progress Indicator Functions
# ============================================================================

# Execute command with progress bar
# Usage: exec_with_progress "Title" "Command to execute"
exec_with_progress() {
    local title="$1"
    local cmd="$2"

    {
        echo "0"
        echo "# Starting..."
        sleep 0.5

        echo "25"
        echo "# Executing command..."
        sleep 0.5

        echo "50"
        echo "# Processing..."

        # Execute the command
        eval "$cmd" &>/dev/null
        local result=$?

        echo "75"
        echo "# Finalizing..."
        sleep 0.5

        echo "100"
        echo "# Complete"
        sleep 0.5

        return $result
    } | show_gauge "$title" "Please wait..." 8 60
}

# ============================================================================
# Main Menu
# ============================================================================

show_main_menu() {
    show_menu "Jacker Main Menu" "Select an operation:" \
        1 "Service Management" \
        2 "Status & Monitoring" \
        3 "Configuration" \
        4 "Maintenance" \
        5 "Security" \
        6 "Troubleshooting" \
        7 "System Information" \
        8 "Exit"
}

# ============================================================================
# Service Management Menu
# ============================================================================

show_service_menu() {
    show_menu "Service Management" "Select service operation:" \
        1 "Start All Services" \
        2 "Stop All Services" \
        3 "Restart All Services" \
        4 "Start Selected Services" \
        5 "Stop Selected Services" \
        6 "Restart Selected Services" \
        7 "Access Service Shell" \
        8 "Back to Main Menu"
}

handle_service_menu() {
    while true; do
        local choice
        choice=$(show_service_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # Start all
                if show_yesno "Confirm Start" "Start all services?" 8 50; then
                    show_msgbox "Starting Services" "Starting all services...\n\nThis may take a moment." 8 50
                    cmd_start
                    show_msgbox "Complete" "All services have been started." 8 50
                fi
                ;;
            2)  # Stop all
                if show_yesno "Confirm Stop" "Stop all services?" 8 50; then
                    show_msgbox "Stopping Services" "Stopping all services...\n\nThis may take a moment." 8 50
                    cmd_stop
                    show_msgbox "Complete" "All services have been stopped." 8 50
                fi
                ;;
            3)  # Restart all
                if show_yesno "Confirm Restart" "Restart all services?" 8 50; then
                    show_msgbox "Restarting Services" "Restarting all services...\n\nThis may take a moment." 8 50
                    cmd_restart
                    show_msgbox "Complete" "All services have been restarted." 8 50
                fi
                ;;
            4)  # Start selected
                handle_start_selected_services
                ;;
            5)  # Stop selected
                handle_stop_selected_services
                ;;
            6)  # Restart selected
                handle_restart_selected_services
                ;;
            7)  # Shell access
                handle_service_shell
                ;;
            8|"")  # Back
                return 0
                ;;
        esac
    done
}

handle_start_selected_services() {
    local items
    items=$(build_services_checklist "off")

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local selected
    selected=$(show_checklist "Start Services" "Select services to start:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$selected" ]]; then
        show_msgbox "Info" "No services selected" 8 50
        return 0
    fi

    # Remove quotes from selection
    selected=$(echo "$selected" | tr -d '"')

    if show_yesno "Confirm Start" "Start selected services:\n\n$selected" 12 60; then
        show_msgbox "Starting Services" "Starting: $selected\n\nPlease wait..." 10 60
        cmd_start $selected
        show_msgbox "Complete" "Selected services have been started." 8 50
    fi
}

handle_stop_selected_services() {
    local items
    items=$(build_services_checklist "off")

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local selected
    selected=$(show_checklist "Stop Services" "Select services to stop:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$selected" ]]; then
        show_msgbox "Info" "No services selected" 8 50
        return 0
    fi

    # Remove quotes from selection
    selected=$(echo "$selected" | tr -d '"')

    if show_yesno "Confirm Stop" "Stop selected services:\n\n$selected" 12 60; then
        show_msgbox "Stopping Services" "Stopping: $selected\n\nPlease wait..." 10 60
        cmd_stop $selected
        show_msgbox "Complete" "Selected services have been stopped." 8 50
    fi
}

handle_restart_selected_services() {
    local items
    items=$(build_services_checklist "off")

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local selected
    selected=$(show_checklist "Restart Services" "Select services to restart:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$selected" ]]; then
        show_msgbox "Info" "No services selected" 8 50
        return 0
    fi

    # Remove quotes from selection
    selected=$(echo "$selected" | tr -d '"')

    if show_yesno "Confirm Restart" "Restart selected services:\n\n$selected" 12 60; then
        show_msgbox "Restarting Services" "Restarting: $selected\n\nPlease wait..." 10 60
        cmd_restart $selected
        show_msgbox "Complete" "Selected services have been restarted." 8 50
    fi
}

handle_service_shell() {
    local items
    items=$(build_services_radiolist)

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local service
    service=$(show_radiolist "Service Shell" "Select service for shell access:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$service" ]]; then
        show_msgbox "Info" "No service selected" 8 50
        return 0
    fi

    # Remove quotes from selection
    service=$(echo "$service" | tr -d '"')

    # Clear screen and launch shell
    clear
    echo "Accessing shell for service: $service"
    echo "Type 'exit' to return to menu"
    echo ""

    cmd_shell "$service"

    # Return to TUI after shell exits
    echo ""
    read -rp "Press Enter to continue..."
}

# ============================================================================
# Status & Monitoring Menu
# ============================================================================

show_status_menu() {
    show_menu "Status & Monitoring" "Select monitoring operation:" \
        1 "View Status" \
        2 "Watch Status (Live)" \
        3 "View Logs" \
        4 "Follow Logs (Live)" \
        5 "Run Health Check" \
        6 "Back to Main Menu"
}

handle_status_menu() {
    while true; do
        local choice
        choice=$(show_status_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # View status
                clear
                echo "Current Service Status"
                echo "======================"
                echo ""
                cmd_status
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)  # Watch status
                clear
                echo "Watching Service Status (Press Ctrl+C to stop)"
                echo "=============================================="
                echo ""
                cmd_status --watch || true
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)  # View logs
                handle_view_logs
                ;;
            4)  # Follow logs
                handle_follow_logs
                ;;
            5)  # Health check
                handle_health_check
                ;;
            6|"")  # Back
                return 0
                ;;
        esac
    done
}

handle_view_logs() {
    local items
    items=$(build_services_radiolist)

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local service
    service=$(show_radiolist "View Logs" "Select service to view logs:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$service" ]]; then
        return 0
    fi

    # Remove quotes
    service=$(echo "$service" | tr -d '"')

    clear
    echo "Logs for: $service"
    echo "=================="
    echo ""
    cmd_logs "$service" --tail 100
    echo ""
    read -rp "Press Enter to continue..."
}

handle_follow_logs() {
    local items
    items=$(build_services_radiolist)

    if [[ -z "$items" ]]; then
        show_msgbox "Error" "No services found" 8 50
        return 1
    fi

    local service
    service=$(show_radiolist "Follow Logs" "Select service to follow logs:" $items)
    local ret=$?

    # User canceled
    [[ $ret -ne 0 ]] && return 0

    if [[ -z "$service" ]]; then
        return 0
    fi

    # Remove quotes
    service=$(echo "$service" | tr -d '"')

    clear
    echo "Following logs for: $service (Press Ctrl+C to stop)"
    echo "==================================================="
    echo ""
    cmd_logs "$service" -f || true
    echo ""
    read -rp "Press Enter to continue..."
}

handle_health_check() {
    if show_yesno "Health Check" "Run comprehensive health check?" 8 50; then
        clear
        echo "Running Health Check"
        echo "==================="
        echo ""
        cmd_health --verbose
        echo ""
        read -rp "Press Enter to continue..."
    fi
}

# ============================================================================
# Configuration Menu
# ============================================================================

show_config_menu() {
    show_menu "Configuration" "Select configuration operation:" \
        1 "Show Configuration" \
        2 "Validate Configuration" \
        3 "Configure OAuth" \
        4 "Configure Domain" \
        5 "Configure SSL" \
        6 "Configure Authentik" \
        7 "Configure Tracing" \
        8 "Back to Main Menu"
}

handle_config_menu() {
    while true; do
        local choice
        choice=$(show_config_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # Show config
                clear
                echo "Current Configuration"
                echo "===================="
                echo ""
                cmd_config show
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)  # Validate config
                clear
                echo "Validating Configuration"
                echo "======================="
                echo ""
                if cmd_config validate; then
                    show_msgbox "Success" "Configuration is valid!" 8 50
                else
                    show_msgbox "Error" "Configuration validation failed.\nCheck the output for details." 10 60
                fi
                ;;
            3)  # OAuth
                clear
                echo "OAuth Configuration"
                echo "==================="
                echo ""
                cmd_config oauth
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)  # Domain
                local domain
                domain=$(show_inputbox "Configure Domain" "Enter domain name:" "" 10 60)
                if [[ -n "$domain" ]]; then
                    clear
                    cmd_config domain "$domain"
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            5)  # SSL
                clear
                echo "SSL Configuration"
                echo "================="
                echo ""
                cmd_config ssl
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            6)  # Authentik
                clear
                echo "Authentik Configuration"
                echo "======================"
                echo ""
                cmd_config authentik
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            7)  # Tracing
                clear
                echo "Tracing Configuration"
                echo "===================="
                echo ""
                cmd_config tracing
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            8|"")  # Back
                return 0
                ;;
        esac
    done
}

# ============================================================================
# Maintenance Menu
# ============================================================================

show_maintenance_menu() {
    show_menu "Maintenance" "Select maintenance operation:" \
        1 "Backup Configuration" \
        2 "Restore from Backup" \
        3 "Update Jacker" \
        4 "Check for Updates" \
        5 "Clean Up" \
        6 "Wipe All Data" \
        7 "Tune Resources" \
        8 "Back to Main Menu"
}

handle_maintenance_menu() {
    while true; do
        local choice
        choice=$(show_maintenance_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # Backup
                if show_yesno "Create Backup" "Create a backup now?" 8 50; then
                    clear
                    echo "Creating Backup"
                    echo "==============="
                    echo ""
                    cmd_backup
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            2)  # Restore
                local backup_file
                backup_file=$(show_inputbox "Restore Backup" "Enter backup file path:" "" 10 70)
                if [[ -n "$backup_file" ]]; then
                    if show_yesno "Confirm Restore" "Restore from:\n$backup_file\n\nThis will stop all services!" 12 70; then
                        clear
                        cmd_restore "$backup_file"
                        echo ""
                        read -rp "Press Enter to continue..."
                    fi
                fi
                ;;
            3)  # Update
                if show_yesno "Update Jacker" "Update Jacker and all services?\n\nThis will pull latest images." 10 60; then
                    clear
                    echo "Updating Jacker"
                    echo "==============="
                    echo ""
                    cmd_update
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            4)  # Check updates
                clear
                echo "Checking for Updates"
                echo "==================="
                echo ""
                cmd_update --check-only
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)  # Clean
                if show_yesno "Clean Up" "Clean up unused containers and images?" 10 60; then
                    clear
                    echo "Cleaning Up"
                    echo "==========="
                    echo ""
                    cmd_clean
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            6)  # Wipe data
                if show_yesno "DANGER!" "Wipe ALL data?\n\nThis is IRREVERSIBLE!\n\nSSL certs will be preserved." 12 60; then
                    if show_yesno "Final Confirmation" "Are you ABSOLUTELY SURE?\n\nAll data will be lost!" 10 60; then
                        clear
                        cmd_wipe_data
                        echo ""
                        read -rp "Press Enter to continue..."
                    fi
                fi
                ;;
            7)  # Tune
                if show_yesno "Resource Tuning" "Optimize resource allocation?" 8 60; then
                    clear
                    echo "Tuning Resources"
                    echo "================"
                    echo ""
                    cmd_tune
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            8|"")  # Back
                return 0
                ;;
        esac
    done
}

# ============================================================================
# Security Menu
# ============================================================================

show_security_menu() {
    show_menu "Security" "Select security operation:" \
        1 "Manage Secrets" \
        2 "Security Scan" \
        3 "Manage Whitelist" \
        4 "View Alerts" \
        5 "Back to Main Menu"
}

handle_security_menu() {
    while true; do
        local choice
        choice=$(show_security_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # Secrets
                clear
                echo "Secret Management"
                echo "================="
                echo ""
                cmd_secrets list
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)  # Security scan
                clear
                echo "Running Security Scan"
                echo "===================="
                echo ""
                cmd_security scan
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)  # Whitelist
                handle_whitelist_menu
                ;;
            4)  # Alerts
                clear
                echo "Alert Management"
                echo "==============="
                echo ""
                cmd_alerts list
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5|"")  # Back
                return 0
                ;;
        esac
    done
}

handle_whitelist_menu() {
    while true; do
        local choice
        choice=$(show_menu "Whitelist Management" "Select whitelist operation:" \
            1 "Show Whitelist" \
            2 "Add Entry" \
            3 "Remove Entry" \
            4 "Test Current IP" \
            5 "Reload Whitelist" \
            6 "Back")
        local ret=$?

        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)
                clear
                cmd_whitelist list
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)
                local entry
                entry=$(show_inputbox "Add Whitelist Entry" "Enter IP/CIDR to whitelist:" "" 10 60)
                if [[ -n "$entry" ]]; then
                    clear
                    cmd_whitelist add "$entry"
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            3)
                local entry
                entry=$(show_inputbox "Remove Whitelist Entry" "Enter IP/CIDR to remove:" "" 10 60)
                if [[ -n "$entry" ]]; then
                    if show_yesno "Confirm Remove" "Remove $entry from whitelist?" 8 60; then
                        clear
                        cmd_whitelist remove "$entry"
                        echo ""
                        read -rp "Press Enter to continue..."
                    fi
                fi
                ;;
            4)
                clear
                cmd_whitelist current
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5)
                if show_yesno "Reload Whitelist" "Restart CrowdSec to apply changes?" 8 60; then
                    clear
                    cmd_whitelist reload
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            6|"")
                return 0
                ;;
        esac
    done
}

# ============================================================================
# Troubleshooting Menu
# ============================================================================

show_troubleshooting_menu() {
    show_menu "Troubleshooting" "Select troubleshooting operation:" \
        1 "Fix Common Issues" \
        2 "View Diagnostics" \
        3 "Network Issues" \
        4 "Permission Issues" \
        5 "Back to Main Menu"
}

handle_troubleshooting_menu() {
    while true; do
        local choice
        choice=$(show_troubleshooting_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # Fix issues
                local component
                component=$(show_menu "Fix Issues" "Select component to fix:" \
                    "all" "Fix All Issues" \
                    "permissions" "Fix Permissions" \
                    "network" "Fix Network" \
                    "oauth" "Fix OAuth" \
                    "ssl" "Fix SSL")

                if [[ -n "$component" && "$component" != "" ]]; then
                    clear
                    echo "Running Fixes: $component"
                    echo "======================="
                    echo ""
                    cmd_fix "$component"
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            2)  # Diagnostics
                clear
                echo "System Diagnostics"
                echo "=================="
                echo ""
                cmd_info
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)  # Network
                clear
                echo "Network Diagnostics"
                echo "=================="
                echo ""
                cmd_fix network --check-only 2>/dev/null || cmd_info
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)  # Permissions
                if show_yesno "Fix Permissions" "Fix file and directory permissions?" 8 60; then
                    clear
                    cmd_fix permissions
                    echo ""
                    read -rp "Press Enter to continue..."
                fi
                ;;
            5|"")  # Back
                return 0
                ;;
        esac
    done
}

# ============================================================================
# Information Menu
# ============================================================================

show_info_menu() {
    show_menu "System Information" "Select information to display:" \
        1 "System Info" \
        2 "Version Info" \
        3 "Docker Info" \
        4 "Resource Usage" \
        5 "Back to Main Menu"
}

handle_info_menu() {
    while true; do
        local choice
        choice=$(show_info_menu)
        local ret=$?

        # User canceled (ESC)
        [[ $ret -ne 0 ]] && return 0

        case "$choice" in
            1)  # System info
                clear
                echo "System Information"
                echo "=================="
                echo ""
                cmd_info
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            2)  # Version info
                clear
                echo "Version Information"
                echo "==================="
                echo ""
                cmd_version
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            3)  # Docker info
                clear
                echo "Docker Information"
                echo "=================="
                echo ""
                docker info 2>/dev/null || echo "Error getting Docker info"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            4)  # Resource usage
                clear
                echo "Resource Usage"
                echo "=============="
                echo ""
                docker stats --no-stream 2>/dev/null || echo "Error getting stats"
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            5|"")  # Back
                return 0
                ;;
        esac
    done
}

# ============================================================================
# Main Interactive Loop
# ============================================================================

run_interactive_mode() {
    # Initialize TUI
    if ! init_tui; then
        return 1
    fi

    # Show welcome message
    show_msgbox "Welcome to Jacker" \
        "Welcome to the Jacker Interactive Menu!\n\n\
Use arrow keys to navigate, Enter to select.\n\
Press ESC to go back or cancel.\n\n\
Version: ${VERSION}" \
        14 60

    # Main loop
    while true; do
        local choice
        choice=$(show_main_menu)
        local ret=$?

        # User pressed ESC on main menu - exit
        if [[ $ret -ne 0 ]]; then
            if show_yesno "Exit" "Exit Jacker interactive mode?" 8 50; then
                clear
                echo "Thank you for using Jacker!"
                return 0
            fi
            continue
        fi

        case "$choice" in
            1)  # Service Management
                handle_service_menu
                ;;
            2)  # Status & Monitoring
                handle_status_menu
                ;;
            3)  # Configuration
                handle_config_menu
                ;;
            4)  # Maintenance
                handle_maintenance_menu
                ;;
            5)  # Security
                handle_security_menu
                ;;
            6)  # Troubleshooting
                handle_troubleshooting_menu
                ;;
            7)  # Information
                handle_info_menu
                ;;
            8|"")  # Exit
                if show_yesno "Exit" "Exit Jacker interactive mode?" 8 50; then
                    clear
                    echo "Thank you for using Jacker!"
                    return 0
                fi
                ;;
        esac
    done
}
