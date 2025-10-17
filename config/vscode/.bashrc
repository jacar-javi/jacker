#!/bin/bash
# Jacker Infrastructure - VSCode Custom Shell Configuration
# This file is automatically sourced by bash when an interactive shell starts

# =============================================================================
# Interactive Shell Check
# =============================================================================
# Only proceed if this is an interactive shell (not a script)
[[ $- != *i* ]] && return

# =============================================================================
# Global Configuration
# =============================================================================
# Source global bashrc if it exists
[ -f /etc/bash.bashrc ] && source /etc/bash.bashrc
[ -f /etc/bashrc ] && source /etc/bashrc

# Source the default LinuxServer.io configuration if present
[ -f /etc/profile ] && source /etc/profile

# =============================================================================
# System Information Display
# =============================================================================
# Display system information on startup
# Set JACKER_DISABLE_SYSINFO=1 in environment to disable this
if [ -z "$JACKER_DISABLE_SYSINFO" ] && [ -x /data/jacker/config/vscode/system-info.sh ]; then
    /data/jacker/config/vscode/system-info.sh
elif [ -n "$JACKER_DISABLE_SYSINFO" ]; then
    echo "System info display disabled (JACKER_DISABLE_SYSINFO set)"
fi

# =============================================================================
# Jacker Project Aliases
# =============================================================================
# Navigation
alias jacker='cd /data/jacker'
alias home='cd /data/home'

# Docker Compose shortcuts
alias dc='docker compose'
alias dclogs='docker compose logs -f'
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcrestart='docker compose restart'
alias dcps='docker compose ps'
alias dcpull='docker compose pull'
alias dcbuild='docker compose build'

# Docker shortcuts
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dimages='docker images'
alias dprune='docker system prune -af'
alias dstop='docker stop $(docker ps -q)'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# System shortcuts
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Quick access to important directories
alias logs='cd /data/jacker/logs'
alias compose='cd /data/jacker/compose'
alias configs='cd /data/jacker/config'
alias scripts='cd /data/jacker/scripts'

# Helpful utilities
alias ports='netstat -tulanp'
alias diskusage='df -h'
alias meminfo='free -h'
alias cpuinfo='lscpu'
alias sysinfo='/data/jacker/config/vscode/system-info.sh'

# =============================================================================
# Environment Variables
# =============================================================================
export EDITOR=nano
export VISUAL=nano
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_SCAN_SUGGEST=false

# Set history options
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "

# Append to history file, don't overwrite it
shopt -s histappend

# Check window size after each command
shopt -s checkwinsize

# Enable recursive globbing with **
shopt -s globstar 2>/dev/null

# Correct minor errors in cd commands
shopt -s cdspell 2>/dev/null

# =============================================================================
# Custom Prompt (PS1)
# =============================================================================
# Color codes for prompt
PS1_GREEN='\[\033[01;32m\]'
PS1_BLUE='\[\033[01;34m\]'
PS1_CYAN='\[\033[01;36m\]'
PS1_YELLOW='\[\033[01;33m\]'
PS1_RESET='\[\033[00m\]'

# Git branch in prompt (if git is available)
git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

# Custom prompt with (jacker) prefix and git branch
export PS1="${PS1_CYAN}(jacker)${PS1_RESET} ${PS1_GREEN}\u@\h${PS1_RESET}:${PS1_BLUE}\w${PS1_YELLOW}\$(git_branch)${PS1_RESET}\$ "

# =============================================================================
# Colored Man Pages
# =============================================================================
export LESS_TERMCAP_mb=$'\e[1;32m'     # begin bold
export LESS_TERMCAP_md=$'\e[1;32m'     # begin blink
export LESS_TERMCAP_me=$'\e[0m'        # reset bold/blink
export LESS_TERMCAP_so=$'\e[01;44;33m' # begin reverse video
export LESS_TERMCAP_se=$'\e[0m'        # reset reverse video
export LESS_TERMCAP_us=$'\e[1;4;31m'   # begin underline
export LESS_TERMCAP_ue=$'\e[0m'        # reset underline

# =============================================================================
# Welcome Message
# =============================================================================
# Display a minimal welcome message after system info
echo ""
echo "Welcome to Jacker Infrastructure VSCode Environment"
echo "Type 'jacker' to navigate to project root, 'sysinfo' to display system info"
echo ""

# =============================================================================
# Custom Functions
# =============================================================================

# Quick container logs
clogs() {
    if [ -z "$1" ]; then
        echo "Usage: clogs <container-name>"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        docker logs -f "$1"
    fi
}

# Quick container shell access
cexec() {
    if [ -z "$1" ]; then
        echo "Usage: cexec <container-name> [command]"
        docker ps --format "table {{.Names}}\t{{.Status}}"
    else
        local container="$1"
        shift
        if [ -z "$1" ]; then
            docker exec -it "$container" /bin/sh 2>/dev/null || docker exec -it "$container" /bin/bash
        else
            docker exec -it "$container" "$@"
        fi
    fi
}

# Quick compose service restart
restart() {
    if [ -z "$1" ]; then
        echo "Usage: restart <service-name>"
        cd /data/jacker && docker compose ps --services
    else
        cd /data/jacker && docker compose restart "$1"
    fi
}

# Show running containers with their networks
dnetwork() {
    docker ps --format "table {{.Names}}\t{{.Networks}}\t{{.Ports}}"
}

# Clean up Docker resources
dclean() {
    echo "Cleaning up Docker resources..."
    docker system prune -af --volumes
    docker network prune -f
    docker volume prune -f
    echo "Docker cleanup complete!"
}

# =============================================================================
# End of Configuration
# =============================================================================
