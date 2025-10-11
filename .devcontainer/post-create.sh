#!/usr/bin/env bash
#
# post-create.sh - Dev container post-creation setup
#
# This script runs after the dev container is created to:
# - Install additional dependencies
# - Configure the development environment
# - Set up tools and utilities
#

set -euo pipefail

echo "🚀 Running post-create setup for Jacker dev container..."

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================================================
# System Dependencies
# ============================================================================

info "Installing system dependencies..."

# Update package lists
sudo apt-get update -qq

# Install essential development tools
sudo apt-get install -y -qq \
    shellcheck \
    shfmt \
    jq \
    curl \
    wget \
    git \
    make \
    netcat \
    dnsutils \
    iputils-ping \
    vim \
    tree \
    htop

success "System dependencies installed"

# ============================================================================
# BATS Testing Framework
# ============================================================================

info "Installing BATS testing framework..."

if ! command -v bats &> /dev/null; then
    BATS_VERSION="v1.10.0"

    # Install bats-core
    git clone --depth 1 --branch "${BATS_VERSION}" https://github.com/bats-core/bats-core.git /tmp/bats-core
    sudo /tmp/bats-core/install.sh /usr/local
    rm -rf /tmp/bats-core

    # Install bats helper libraries
    for lib in bats-support bats-assert bats-file; do
        git clone --depth 1 "https://github.com/bats-core/${lib}.git" "/tmp/${lib}"
        sudo mkdir -p "/usr/local/lib/${lib}"
        sudo cp -r "/tmp/${lib}"/* "/usr/local/lib/${lib}/"
        rm -rf "/tmp/${lib}"
    done

    success "BATS ${BATS_VERSION} installed"
else
    success "BATS already installed: $(bats --version)"
fi

# ============================================================================
# Docker Configuration
# ============================================================================

info "Configuring Docker..."

# Ensure Docker socket is accessible
if [ -S /var/run/docker.sock ]; then
    # Add current user to docker group if not already
    if ! groups | grep -q docker; then
        sudo usermod -aG docker "${USER}"
        warning "Added user to docker group (may require container restart)"
    fi
    success "Docker socket accessible"
else
    warning "Docker socket not found (will be available after container fully starts)"
fi

# ============================================================================
# Git Configuration
# ============================================================================

info "Configuring Git..."

# Set safe directory for git operations
git config --global --add safe.directory /workspaces/jacker

# Set default branch name
git config --global init.defaultBranch main

# Helpful git aliases
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.unstage 'reset HEAD --'
git config --global alias.last 'log -1 HEAD'
git config --global alias.lg "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

success "Git configured with helpful aliases"

# ============================================================================
# Shell Configuration
# ============================================================================

info "Configuring shell environment..."

# Add helpful aliases to bashrc
cat >> ~/.bashrc <<'EOF'

# Jacker Development Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'

# Docker aliases
alias dc='docker compose'
alias dps='docker ps'
alias di='docker images'
alias dl='docker logs'
alias dex='docker exec -it'

# Jacker aliases
alias jup='make up'
alias jdown='make down'
alias jrestart='make restart'
alias jlogs='make logs'
alias jps='make ps'
alias jhealth='make health'
alias jtest='./tests/run_tests.sh'

# Git aliases
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gbr='git branch'

# Make colors
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

EOF

success "Shell aliases configured"

# ============================================================================
# Workspace Setup
# ============================================================================

info "Setting up workspace..."

# Ensure directories exist
mkdir -p tests/results
mkdir -p tests/coverage
mkdir -p logs

# Set permissions
chmod +x assets/*.sh 2>/dev/null || true
chmod +x tests/*.sh 2>/dev/null || true
chmod +x tests/**/*.bats 2>/dev/null || true

success "Workspace setup complete"

# ============================================================================
# Tool Verification
# ============================================================================

info "Verifying installed tools..."

TOOLS=(
    "bash:$(bash --version | head -1)"
    "docker:$(docker --version)"
    "docker compose:$(docker compose version)"
    "git:$(git --version)"
    "make:$(make --version | head -1)"
    "shellcheck:$(shellcheck --version | head -2 | tail -1)"
    "jq:$(jq --version)"
    "bats:$(bats --version)"
)

for tool in "${TOOLS[@]}"; do
    name="${tool%%:*}"
    version="${tool#*:}"
    echo "  ✓ ${name}: ${version}"
done

# ============================================================================
# Final Messages
# ============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════"
success "Dev container setup complete!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📚 Quick Start:"
echo "  make help              - Show all available commands"
echo "  make install           - Install Jacker platform"
echo "  make up                - Start all services"
echo "  make health            - Check service health"
echo "  ./tests/run_tests.sh   - Run test suite"
echo ""
echo "🔧 Development Tools:"
echo "  ShellCheck:  Bash linting (runs on save)"
echo "  BATS:        Test framework (./tests/)"
echo "  Docker:      Container management"
echo "  Make:        Task automation"
echo ""
echo "📖 Documentation:"
echo "  README.md                  - Project overview"
echo "  .vscode/README.md          - VS Code configuration"
echo "  compose/README.md          - Services documentation"
echo "  assets/README.md           - Scripts documentation"
echo "  data/README.md             - Data directory guide"
echo "  tests/README.md            - Testing guide"
echo ""
echo "💡 Tip: Press Ctrl+Shift+B to see available VS Code tasks"
echo ""
