#!/usr/bin/env bash
#
# Git hooks installation script for Jacker project
# Installs pre-commit, pre-push, and commit-msg hooks
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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
echo -e "${BLUE}║     JACKER GIT HOOKS INSTALLATION         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""
echo "This script will install git hooks for the Jacker project."
echo "The hooks will run tests and validations before commits and pushes."
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
# Check for existing hooks
# ============================================================================
print_header "Checking for existing hooks"

GIT_HOOKS_DIR="$REPO_ROOT/.git/hooks"
EXISTING_HOOKS=()

for hook in pre-commit pre-push commit-msg; do
    if [ -f "$GIT_HOOKS_DIR/$hook" ] && [ ! -L "$GIT_HOOKS_DIR/$hook" ]; then
        EXISTING_HOOKS+=("$hook")
    fi
done

if [ ${#EXISTING_HOOKS[@]} -gt 0 ]; then
    print_warning "Found existing hooks: ${EXISTING_HOOKS[*]}"
    echo ""
    echo "Options:"
    echo "  1) Backup existing hooks and install new ones"
    echo "  2) Skip installation of conflicting hooks"
    echo "  3) Cancel installation"
    echo ""
    read -rp "Choose an option [1-3]: " choice

    case $choice in
        1)
            print_info "Backing up existing hooks..."
            for hook in "${EXISTING_HOOKS[@]}"; do
                mv "$GIT_HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook.backup.$(date +%Y%m%d_%H%M%S)"
                print_success "Backed up $hook"
            done
            ;;
        2)
            print_info "Skipping conflicting hooks"
            ;;
        3)
            print_info "Installation cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
else
    print_success "No conflicting hooks found"
fi

# ============================================================================
# Install hooks
# ============================================================================
print_header "Installing git hooks"

HOOKS_TO_INSTALL=(
    "pre-commit"
    "pre-push"
    "commit-msg"
)

INSTALLED_COUNT=0
SKIPPED_COUNT=0

for hook in "${HOOKS_TO_INSTALL[@]}"; do
    SOURCE_HOOK="$SCRIPT_DIR/$hook"
    TARGET_HOOK="$GIT_HOOKS_DIR/$hook"

    if [ ! -f "$SOURCE_HOOK" ]; then
        print_error "Source hook not found: $hook"
        continue
    fi

    # Skip if hook exists and user chose to skip
    if [ -f "$TARGET_HOOK" ] && [ "$choice" == "2" ] && [[ " ${EXISTING_HOOKS[*]} " =~ " ${hook} " ]]; then
        print_warning "Skipped: $hook (existing hook preserved)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi

    # Create symlink to the hook
    ln -sf "$SOURCE_HOOK" "$TARGET_HOOK"
    chmod +x "$SOURCE_HOOK"

    print_success "Installed: $hook"
    INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
done

# ============================================================================
# Check for required tools
# ============================================================================
print_header "Checking for required tools"

MISSING_TOOLS=()

# Check for shellcheck
if ! command -v shellcheck >/dev/null 2>&1; then
    MISSING_TOOLS+=("shellcheck")
    print_warning "shellcheck not found"
else
    SHELLCHECK_VERSION=$(shellcheck --version | grep version: | awk '{print $2}')
    print_success "shellcheck installed (version $SHELLCHECK_VERSION)"
fi

# Check for yamllint
if ! command -v yamllint >/dev/null 2>&1; then
    MISSING_TOOLS+=("yamllint")
    print_warning "yamllint not found"
else
    YAMLLINT_VERSION=$(yamllint --version | awk '{print $2}')
    print_success "yamllint installed (version $YAMLLINT_VERSION)"
fi

# Check for docker
if ! command -v docker >/dev/null 2>&1; then
    MISSING_TOOLS+=("docker")
    print_warning "docker not found"
else
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
    print_success "docker installed (version $DOCKER_VERSION)"
fi

# Check for git
GIT_VERSION=$(git --version | awk '{print $3}')
print_success "git installed (version $GIT_VERSION)"

# ============================================================================
# Installation recommendations
# ============================================================================
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    print_header "Installation recommendations"
    echo ""
    echo "The following tools are recommended for full hook functionality:"
    echo ""

    for tool in "${MISSING_TOOLS[@]}"; do
        case $tool in
            shellcheck)
                echo "  ${MAGENTA}shellcheck${NC} - Shell script static analysis"
                echo "    Install: apt-get install shellcheck"
                echo "         or: brew install shellcheck (macOS)"
                echo ""
                ;;
            yamllint)
                echo "  ${MAGENTA}yamllint${NC} - YAML file linter"
                echo "    Install: pip install yamllint"
                echo "         or: apt-get install yamllint"
                echo ""
                ;;
            docker)
                echo "  ${MAGENTA}docker${NC} - Container platform"
                echo "    Install: https://docs.docker.com/get-docker/"
                echo ""
                ;;
        esac
    done
fi

# ============================================================================
# Configuration options
# ============================================================================
print_header "Configuration options"

echo ""
echo "You can configure hook behavior with environment variables:"
echo ""
echo "  ${CYAN}SKIP_SHELLCHECK=1${NC}    Skip ShellCheck validation"
echo "  ${CYAN}SKIP_YAML_CHECK=1${NC}    Skip YAML validation"
echo "  ${CYAN}SKIP_DOCKER_CHECK=1${NC}  Skip Docker Compose validation"
echo ""
echo "Example: SKIP_SHELLCHECK=1 git commit -m 'feat: add feature'"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo -e "${GREEN}        INSTALLATION COMPLETE!              ${NC}"
echo -e "${BLUE}════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  • Installed hooks: $INSTALLED_COUNT"
if [ $SKIPPED_COUNT -gt 0 ]; then
    echo "  • Skipped hooks: $SKIPPED_COUNT"
fi
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "  • Missing tools: ${#MISSING_TOOLS[@]} (see recommendations above)"
fi
echo ""
echo "The following hooks are now active:"
echo ""
echo "  ${GREEN}pre-commit${NC}  - Runs quick validations before each commit"
echo "  ${GREEN}pre-push${NC}    - Runs comprehensive tests before pushing"
echo "  ${GREEN}commit-msg${NC}  - Validates commit message format"
echo ""
echo "To bypass hooks temporarily (not recommended):"
echo "  git commit --no-verify"
echo "  git push --no-verify"
echo ""
echo "To uninstall hooks, run:"
echo "  ${CYAN}./hooks/uninstall.sh${NC}"
echo ""

exit 0