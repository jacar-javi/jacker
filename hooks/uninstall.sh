#!/usr/bin/env bash
#
# Git hooks uninstallation script for Jacker project
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Print functions
print_header() {
    echo -e "\n${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# ============================================================================
# Welcome Banner
# ============================================================================
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    JACKER GIT HOOKS UNINSTALLATION        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "This script will remove git hooks for the Jacker project."
echo ""

# ============================================================================
# Check if we're in a git repository
# ============================================================================
print_header "Checking git repository"

if [ ! -d "$REPO_ROOT/.git" ]; then
    print_error "Not in a git repository!"
    echo "Please run this script from the Jacker repository root."
    exit 1
fi

print_success "Git repository found"

# ============================================================================
# Check for installed hooks
# ============================================================================
print_header "Checking for installed hooks"

GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOKS_TO_REMOVE=(
    "pre-commit"
    "pre-push"
    "commit-msg"
)

INSTALLED_HOOKS=()
for hook in "${HOOKS_TO_REMOVE[@]}"; do
    TARGET_HOOK="$GIT_HOOKS_DIR/$hook"
    if [ -L "$TARGET_HOOK" ]; then
        # Check if it's a symlink pointing to our hooks
        LINK_TARGET=$(readlink "$TARGET_HOOK")
        if [[ "$LINK_TARGET" == *"/hooks/$hook" ]]; then
            INSTALLED_HOOKS+=("$hook")
        fi
    fi
done

if [ ${#INSTALLED_HOOKS[@]} -eq 0 ]; then
    print_info "No Jacker git hooks found"
    exit 0
fi

print_info "Found Jacker hooks: ${INSTALLED_HOOKS[*]}"

# ============================================================================
# Confirm uninstallation
# ============================================================================
echo ""
read -rp "Are you sure you want to uninstall these hooks? [y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Uninstallation cancelled"
    exit 0
fi

# ============================================================================
# Remove hooks
# ============================================================================
print_header "Removing git hooks"

REMOVED_COUNT=0
for hook in "${INSTALLED_HOOKS[@]}"; do
    TARGET_HOOK="$GIT_HOOKS_DIR/$hook"

    rm -f "$TARGET_HOOK"
    print_success "Removed: $hook"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))

    # Check for backup files
    BACKUP_FILES=$(find "$GIT_HOOKS_DIR" -name "$hook.backup.*" 2>/dev/null || true)
    if [ -n "$BACKUP_FILES" ]; then
        print_info "Found backup files for $hook:"
        echo "$BACKUP_FILES" | while read -r backup; do
            echo "    - $(basename "$backup")"
        done

        read -rp "  Restore most recent backup? [y/N]: " restore
        if [[ "$restore" =~ ^[Yy]$ ]]; then
            LATEST_BACKUP=$(echo "$BACKUP_FILES" | tail -n 1)
            mv "$LATEST_BACKUP" "$TARGET_HOOK"
            print_success "Restored $hook from backup"
        fi
    fi
done

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo -e "${GREEN}       UNINSTALLATION COMPLETE!             ${NC}"
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  • Removed hooks: $REMOVED_COUNT"
echo ""
echo "Git hooks have been uninstalled."
echo "Commits and pushes will no longer trigger automatic validation."
echo ""
echo "To reinstall hooks, run:"
echo "  ${CYAN}./hooks/install.sh${NC}"
echo ""

exit 0