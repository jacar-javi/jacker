#!/usr/bin/env bash
#
# system.sh - System configuration and tuning library
# This module handles system-level configurations
#

# Source common library
# shellcheck source=assets/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ============================================================================
# System Tuning Functions
# ============================================================================

# Apply system optimizations
tune_system() {
    section "System Tuning"

    # Apply sysctl optimizations
    apply_sysctl_settings

    # Configure system limits
    configure_system_limits

    # Configure logrotate
    configure_logrotate

    success "System tuning complete"
}

# Apply sysctl settings for production
apply_sysctl_settings() {
    subsection "Applying sysctl settings"

    cat <<EOF | sudo tee /etc/sysctl.d/99-jacker.conf > /dev/null
# Jacker System Optimizations

# Network optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 1
net.ipv4.ip_nonlocal_bind = 1

# File system
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# Virtual memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# Security
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    sudo sysctl -p /etc/sysctl.d/99-jacker.conf &> /dev/null
    success "Sysctl settings applied"
}

# Configure system limits
configure_system_limits() {
    subsection "Configuring system limits"

    cat <<EOF | sudo tee /etc/security/limits.d/jacker.conf > /dev/null
# Jacker System Limits
* soft nofile 65535
* hard nofile 65535
* soft nproc 32768
* hard nproc 32768
* soft memlock unlimited
* hard memlock unlimited
EOF

    success "System limits configured"
}

# Configure logrotate for Jacker logs
configure_logrotate() {
    subsection "Configuring logrotate"

    local jacker_root="$(get_jacker_root)"

    cat <<EOF | sudo tee /etc/logrotate.d/jacker > /dev/null
${jacker_root}/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 $USER $USER
    sharedscripts
    postrotate
        docker kill -s USR1 \$(docker ps -q) 2>/dev/null || true
    endscript
}
EOF

    success "Logrotate configured"
}

# ============================================================================
# Docker Installation Functions
# ============================================================================

# Install Docker
install_docker() {
    section "Docker Installation"

    if check_docker 2>/dev/null; then
        info "Docker is already installed"
        docker --version
        return 0
    fi

    # Detect OS and install Docker accordingly
    local os_info=$(detect_os)
    local os="${os_info%%:*}"
    local dist="${os_info##*:}"

    case "$os" in
        ubuntu|debian)
            install_docker_debian "$os" "$dist"
            ;;
        centos|rhel|rocky|almalinux)
            install_docker_rhel "$os" "$dist"
            ;;
        *)
            error "Unsupported OS: $os"
            return 1
            ;;
    esac

    # Configure Docker
    configure_docker

    # Add user to docker group
    add_user_to_docker_group

    success "Docker installation complete"
}

# Install Docker on Debian/Ubuntu
install_docker_debian() {
    local os="$1"
    local dist="$2"

    info "Installing Docker on $os $dist"

    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/$os/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$os \
        $dist stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    success "Docker installed successfully"
}

# Install Docker on RHEL-based systems
install_docker_rhel() {
    local os="$1"
    local dist="$2"

    info "Installing Docker on $os $dist"

    # Remove old versions
    sudo yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    # Install prerequisites
    sudo yum install -y yum-utils

    # Set up the repository
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install Docker Engine
    sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Start Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    success "Docker installed successfully"
}

# Configure Docker daemon
configure_docker() {
    subsection "Configuring Docker daemon"

    sudo mkdir -p /etc/docker

    cat <<EOF | sudo tee /etc/docker/daemon.json > /dev/null
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "10"
  },
  "default-ulimits": {
    "nofile": {
      "Hard": 65535,
      "Soft": 65535
    }
  },
  "dns": ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4"],
  "dns-opts": ["ndots:0"],
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "metrics-addr": "127.0.0.1:9323"
}
EOF

    sudo systemctl restart docker
    success "Docker daemon configured"
}

# Add current user to docker group
add_user_to_docker_group() {
    subsection "Adding user to docker group"

    if ! groups | grep -q docker; then
        sudo usermod -aG docker "$USER"
        warning "User added to docker group. You may need to log out and back in."
    else
        info "User is already in docker group"
    fi
}

# ============================================================================
# Firewall Configuration Functions
# ============================================================================

# Configure UFW firewall
configure_firewall() {
    section "Firewall Configuration"

    if ! command_exists ufw; then
        info "Installing UFW..."
        sudo apt-get install -y ufw || sudo yum install -y ufw
    fi

    # Load firewall settings from .env if available
    if [ -f ".env" ]; then
        load_env
    fi

    configure_ufw_rules

    success "Firewall configuration complete"
}

# Configure UFW rules
configure_ufw_rules() {
    subsection "Configuring UFW rules"

    # Set default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Allow SSH (with restrictions if specified)
    local ssh_allow="${UFW_ALLOW_SSH:-any}"
    if [ "$ssh_allow" = "any" ]; then
        sudo ufw allow ssh
    else
        IFS=',' read -ra ssh_sources <<< "$ssh_allow"
        for source in "${ssh_sources[@]}"; do
            sudo ufw allow from "$source" to any port 22
        done
    fi

    # Allow HTTP and HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp

    # Allow additional ports if specified
    if [ -n "${UFW_ALLOW_PORTS:-}" ]; then
        IFS=',' read -ra ports <<< "$UFW_ALLOW_PORTS"
        for port in "${ports[@]}"; do
            sudo ufw allow "$port"
        done
    fi

    # Docker Swarm ports (if needed)
    if [ "${ENABLE_SWARM:-false}" = "true" ]; then
        sudo ufw allow 2377/tcp  # Cluster management
        sudo ufw allow 7946/tcp  # Communication among nodes
        sudo ufw allow 7946/udp  # Communication among nodes
        sudo ufw allow 4789/udp  # Overlay network traffic
    fi

    # Enable UFW
    sudo ufw --force enable

    success "UFW rules configured"
    sudo ufw status verbose
}

# ============================================================================
# Package Installation Functions
# ============================================================================

# Install system packages
install_packages() {
    section "Installing System Packages"

    local os_info=$(detect_os)
    local os="${os_info%%:*}"

    case "$os" in
        ubuntu|debian)
            install_packages_debian
            ;;
        centos|rhel|rocky|almalinux)
            install_packages_rhel
            ;;
        *)
            warning "Unknown OS, skipping package installation"
            ;;
    esac
}

# Install packages on Debian/Ubuntu
install_packages_debian() {
    info "Installing packages for Debian/Ubuntu"

    sudo apt-get update
    sudo apt-get install -y \
        curl wget git make jq \
        htop iotop net-tools \
        ufw fail2ban \
        software-properties-common \
        apache2-utils \
        openssl \
        vim nano

    success "Packages installed"
}

# Install packages on RHEL-based systems
install_packages_rhel() {
    info "Installing packages for RHEL-based systems"

    sudo yum install -y \
        curl wget git make jq \
        htop iotop net-tools \
        firewalld fail2ban \
        openssl \
        vim nano

    success "Packages installed"
}

# ============================================================================
# Export Functions
# ============================================================================

export -f tune_system apply_sysctl_settings configure_system_limits configure_logrotate
export -f install_docker install_docker_debian install_docker_rhel configure_docker add_user_to_docker_group
export -f configure_firewall configure_ufw_rules
export -f install_packages install_packages_debian install_packages_rhel