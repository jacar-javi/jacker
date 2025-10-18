#!/usr/bin/env bash
#
# Test script for TUI library
#

set -euo pipefail

# Mock environment
export JACKER_ROOT="/workspaces/jacker"
export VERSION="3.0.0"

# Source common functions (for colors and utilities)
source "$JACKER_ROOT/assets/lib/common.sh"

# Mock docker commands for testing
docker() {
    if [[ "$1" == "compose" ]] && [[ "$2" == "config" ]] && [[ "$3" == "--services" ]]; then
        # Return mock services
        cat << EOF
traefik
homepage
oauth2-proxy
redis
postgresql
grafana
prometheus
loki
crowdsec
portainer
EOF
    elif [[ "$1" == "compose" ]] && [[ "$2" == "ps" ]]; then
        # Return mock running services
        cat << EOF
traefik
homepage
redis
EOF
    else
        echo "Mock docker command: $*" >&2
        return 0
    fi
}

export -f docker

# Test 1: Check if dialog is available
echo "Test 1: Checking for dialog/whiptail..."
if command -v dialog &>/dev/null; then
    echo "✓ dialog found: $(which dialog)"
elif command -v whiptail &>/dev/null; then
    echo "✓ whiptail found: $(which whiptail)"
else
    echo "✗ Neither dialog nor whiptail found"
    exit 1
fi

# Test 2: Source TUI library
echo ""
echo "Test 2: Sourcing TUI library..."
if source "$JACKER_ROOT/assets/lib/tui.sh"; then
    echo "✓ TUI library sourced successfully"
else
    echo "✗ Failed to source TUI library"
    exit 1
fi

# Test 3: Initialize TUI
echo ""
echo "Test 3: Initializing TUI..."
if init_tui; then
    echo "✓ TUI initialized successfully"
    echo "  TUI_CMD=$TUI_CMD"
else
    echo "✗ Failed to initialize TUI"
    exit 1
fi

# Test 4: Test service list functions
echo ""
echo "Test 4: Testing service list functions..."
services=$(get_services_list)
if [[ -n "$services" ]]; then
    echo "✓ get_services_list() returned services:"
    echo "$services" | sed 's/^/  - /'
else
    echo "✗ get_services_list() returned no services"
    exit 1
fi

# Test 5: Test checklist builder
echo ""
echo "Test 5: Testing checklist builder..."
items=$(build_services_checklist "off")
if [[ -n "$items" ]]; then
    echo "✓ build_services_checklist() returned items"
    echo "  Item count: $(echo "$items" | wc -w)"
else
    echo "✗ build_services_checklist() returned no items"
    exit 1
fi

# Test 6: Test radiolist builder
echo ""
echo "Test 6: Testing radiolist builder..."
items=$(build_services_radiolist)
if [[ -n "$items" ]]; then
    echo "✓ build_services_radiolist() returned items"
    echo "  Item count: $(echo "$items" | wc -w)"
else
    echo "✗ build_services_radiolist() returned no items"
    exit 1
fi

# Test 7: Check all menu functions exist
echo ""
echo "Test 7: Checking menu functions exist..."
functions=(
    "show_menu"
    "show_checklist"
    "show_radiolist"
    "show_yesno"
    "show_msgbox"
    "show_inputbox"
    "show_gauge"
    "show_main_menu"
    "show_service_menu"
    "show_status_menu"
    "show_config_menu"
    "show_maintenance_menu"
    "show_security_menu"
    "show_troubleshooting_menu"
    "show_info_menu"
    "handle_service_menu"
    "handle_status_menu"
    "handle_config_menu"
    "handle_maintenance_menu"
    "handle_security_menu"
    "handle_troubleshooting_menu"
    "handle_info_menu"
    "run_interactive_mode"
)

all_exist=true
for func in "${functions[@]}"; do
    if declare -f "$func" > /dev/null; then
        echo "  ✓ $func"
    else
        echo "  ✗ $func (not found)"
        all_exist=false
    fi
done

if $all_exist; then
    echo "✓ All required functions exist"
else
    echo "✗ Some functions are missing"
    exit 1
fi

echo ""
echo "=========================================="
echo "All tests passed! ✓"
echo "=========================================="
echo ""
echo "TUI library is ready for use."
echo "To launch interactive mode: ./jacker --interactive"
