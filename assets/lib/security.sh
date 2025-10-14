#!/usr/bin/env bash
# Jacker Security Library
# CrowdSec, firewall, and security operations

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

#########################################
# CrowdSec Management
#########################################

manage_crowdsec() {
    local action="${1:-status}"

    case "$action" in
        status)
            crowdsec_status
            ;;
        install-collections)
            install_crowdsec_collections
            ;;
        add-bouncer)
            add_crowdsec_bouncer
            ;;
        list-decisions)
            list_crowdsec_decisions
            ;;
        ban)
            ban_ip "$2"
            ;;
        unban)
            unban_ip "$2"
            ;;
        whitelist)
            whitelist_ip "$2"
            ;;
        scenarios)
            manage_scenarios "$2"
            ;;
        hub-update)
            update_crowdsec_hub
            ;;
        *)
            log_error "Unknown action: $action"
            show_crowdsec_help
            ;;
    esac
}

crowdsec_status() {
    log_section "CrowdSec Status"

    # Check if CrowdSec is running
    if ! docker ps --format '{{.Names}}' | grep -q 'jacker-crowdsec'; then
        log_error "CrowdSec container is not running"
        return 1
    fi

    # Show CrowdSec metrics
    log_subsection "CrowdSec Metrics"
    docker compose exec -T crowdsec cscli metrics 2>/dev/null || log_error "Failed to get metrics"

    # Show installed collections
    log_subsection "Installed Collections"
    docker compose exec -T crowdsec cscli collections list 2>/dev/null || log_error "Failed to list collections"

    # Show bouncers
    log_subsection "Registered Bouncers"
    docker compose exec -T crowdsec cscli bouncers list 2>/dev/null || log_error "Failed to list bouncers"

    # Show recent decisions
    log_subsection "Recent Decisions"
    docker compose exec -T crowdsec cscli decisions list --limit 10 2>/dev/null || log_error "Failed to list decisions"

    # Show alerts
    log_subsection "Recent Alerts"
    docker compose exec -T crowdsec cscli alerts list --limit 10 2>/dev/null || log_error "Failed to list alerts"
}

install_crowdsec_collections() {
    log_info "Installing CrowdSec collections..."

    local collections=(
        "crowdsecurity/traefik"
        "crowdsecurity/http-cve"
        "crowdsecurity/whitelist-good-actors"
        "crowdsecurity/iptables"
        "crowdsecurity/linux"
        "crowdsecurity/sshd"
    )

    for collection in "${collections[@]}"; do
        log_info "Installing $collection..."
        docker compose exec -T crowdsec cscli collections install "$collection" 2>/dev/null || \
            log_warn "Failed to install $collection"
    done

    # Reload CrowdSec
    docker compose exec -T crowdsec cscli reload 2>/dev/null || true

    log_success "Collections installed"
}

add_crowdsec_bouncer() {
    log_info "Adding CrowdSec bouncer..."

    read -rp "Bouncer name: " bouncer_name
    read -rp "Generate random key? (Y/n): " gen_key
    gen_key="${gen_key:-Y}"

    if [[ "${gen_key,,}" == "y" ]]; then
        local api_key=$(openssl rand -hex 32)
        log_info "Generated API key: $api_key"
    else
        read -rp "API key: " api_key
    fi

    # Add bouncer
    docker compose exec -T crowdsec cscli bouncers add "$bouncer_name" -k "$api_key" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "Bouncer '$bouncer_name' added"
        echo "API Key: $api_key"
        echo "Save this key securely - it cannot be retrieved later"
    else
        log_error "Failed to add bouncer"
    fi
}

list_crowdsec_decisions() {
    log_section "CrowdSec Decisions"

    echo "Active bans:"
    docker compose exec -T crowdsec cscli decisions list 2>/dev/null || log_error "Failed to list decisions"
}

ban_ip() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        read -rp "IP address to ban: " ip
    fi

    log_info "Banning IP: $ip"

    docker compose exec -T crowdsec cscli decisions add -i "$ip" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "IP $ip banned"
    else
        log_error "Failed to ban IP"
    fi
}

unban_ip() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        read -rp "IP address to unban: " ip
    fi

    log_info "Unbanning IP: $ip"

    docker compose exec -T crowdsec cscli decisions delete -i "$ip" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        log_success "IP $ip unbanned"
    else
        log_error "Failed to unban IP"
    fi
}

whitelist_ip() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        read -rp "IP address to whitelist: " ip
    fi

    log_info "Whitelisting IP: $ip"

    # Add to whitelist file
    local whitelist_file="${JACKER_DIR}/data/crowdsec/config/parsers/s02-enrich/whitelist.yaml"
    mkdir -p "$(dirname "$whitelist_file")"

    if [[ ! -f "$whitelist_file" ]]; then
        cat > "$whitelist_file" <<EOF
name: whitelist
description: "Whitelist specific IPs"
whitelist:
  reason: "Manual whitelist"
  ip:
    - "$ip"
EOF
    else
        # Add IP to existing whitelist
        if ! grep -q "$ip" "$whitelist_file"; then
            sed -i "/^  ip:/a\    - \"$ip\"" "$whitelist_file"
        fi
    fi

    # Reload CrowdSec
    docker compose exec -T crowdsec cscli reload 2>/dev/null

    log_success "IP $ip whitelisted"
}

manage_scenarios() {
    local action="${1:-list}"

    case "$action" in
        list)
            log_info "Installed scenarios:"
            docker compose exec -T crowdsec cscli scenarios list 2>/dev/null
            ;;
        install)
            read -rp "Scenario to install: " scenario
            docker compose exec -T crowdsec cscli scenarios install "$scenario" 2>/dev/null
            docker compose exec -T crowdsec cscli reload 2>/dev/null
            ;;
        remove)
            read -rp "Scenario to remove: " scenario
            docker compose exec -T crowdsec cscli scenarios remove "$scenario" 2>/dev/null
            docker compose exec -T crowdsec cscli reload 2>/dev/null
            ;;
        *)
            log_error "Unknown scenario action: $action"
            ;;
    esac
}

update_crowdsec_hub() {
    log_info "Updating CrowdSec hub..."

    docker compose exec -T crowdsec cscli hub update 2>/dev/null
    docker compose exec -T crowdsec cscli hub upgrade 2>/dev/null

    log_success "CrowdSec hub updated"
}

show_crowdsec_help() {
    echo "CrowdSec management commands:"
    echo "  status              - Show CrowdSec status and metrics"
    echo "  install-collections - Install recommended collections"
    echo "  add-bouncer        - Add a new bouncer"
    echo "  list-decisions     - List active decisions/bans"
    echo "  ban <ip>           - Ban an IP address"
    echo "  unban <ip>         - Unban an IP address"
    echo "  whitelist <ip>     - Whitelist an IP address"
    echo "  scenarios <action> - Manage scenarios (list/install/remove)"
    echo "  hub-update         - Update CrowdSec hub"
}

#########################################
# Firewall Management
#########################################

manage_firewall() {
    local action="${1:-status}"

    case "$action" in
        status)
            firewall_status
            ;;
        enable)
            enable_firewall
            ;;
        disable)
            disable_firewall
            ;;
        allow)
            allow_firewall_rule "$2" "$3"
            ;;
        deny)
            deny_firewall_rule "$2" "$3"
            ;;
        list)
            list_firewall_rules
            ;;
        reset)
            reset_firewall
            ;;
        *)
            log_error "Unknown action: $action"
            show_firewall_help
            ;;
    esac
}

firewall_status() {
    log_section "Firewall Status"

    if command -v ufw &>/dev/null; then
        log_subsection "UFW Status"
        sudo ufw status verbose
    elif command -v firewall-cmd &>/dev/null; then
        log_subsection "Firewalld Status"
        sudo firewall-cmd --state
        sudo firewall-cmd --list-all
    elif command -v iptables &>/dev/null; then
        log_subsection "IPTables Rules"
        sudo iptables -L -n -v
    else
        log_warn "No firewall tool found"
    fi
}

enable_firewall() {
    log_info "Enabling firewall..."

    # Load configuration
    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    if command -v ufw &>/dev/null; then
        # Configure UFW
        sudo ufw --force enable

        # Allow SSH
        if [[ -n "${UFW_ALLOW_SSH:-}" ]]; then
            IFS=',' read -ra SSH_SOURCES <<< "${UFW_ALLOW_SSH}"
            for source in "${SSH_SOURCES[@]}"; do
                sudo ufw allow from "$source" to any port 22 proto tcp comment "SSH from $source"
            done
        else
            sudo ufw allow 22/tcp comment "SSH"
        fi

        # Allow HTTP and HTTPS
        sudo ufw allow 80/tcp comment "HTTP"
        sudo ufw allow 443/tcp comment "HTTPS"

        # Allow Docker networks
        sudo ufw allow in on docker0
        sudo ufw allow from 192.168.0.0/16 comment "Docker networks"

        # Reload UFW
        sudo ufw reload

        log_success "UFW firewall enabled"
    elif command -v firewall-cmd &>/dev/null; then
        # Configure firewalld
        sudo systemctl enable firewalld
        sudo systemctl start firewalld

        # Add services
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        sudo firewall-cmd --permanent --add-service=ssh

        # Add Docker interface
        sudo firewall-cmd --permanent --zone=trusted --add-interface=docker0

        # Reload
        sudo firewall-cmd --reload

        log_success "Firewalld enabled"
    else
        log_error "No supported firewall found"
    fi
}

disable_firewall() {
    log_warn "Disabling firewall - this will leave your system exposed!"
    read -rp "Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    if command -v ufw &>/dev/null; then
        sudo ufw --force disable
        log_success "UFW disabled"
    elif command -v firewall-cmd &>/dev/null; then
        sudo systemctl stop firewalld
        sudo systemctl disable firewalld
        log_success "Firewalld disabled"
    fi
}

allow_firewall_rule() {
    local port="$1"
    local source="$2"

    if [[ -z "$port" ]]; then
        read -rp "Port or service to allow: " port
    fi

    if command -v ufw &>/dev/null; then
        if [[ -n "$source" ]]; then
            sudo ufw allow from "$source" to any port "$port"
        else
            sudo ufw allow "$port"
        fi
        log_success "Rule added"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port="${port}/tcp"
        sudo firewall-cmd --reload
        log_success "Rule added"
    fi
}

deny_firewall_rule() {
    local port="$1"
    local source="$2"

    if [[ -z "$port" ]]; then
        read -rp "Port or service to deny: " port
    fi

    if command -v ufw &>/dev/null; then
        if [[ -n "$source" ]]; then
            sudo ufw deny from "$source" to any port "$port"
        else
            sudo ufw deny "$port"
        fi
        log_success "Rule added"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --remove-port="${port}/tcp"
        sudo firewall-cmd --reload
        log_success "Rule removed"
    fi
}

list_firewall_rules() {
    if command -v ufw &>/dev/null; then
        sudo ufw status numbered
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --list-all
    elif command -v iptables &>/dev/null; then
        sudo iptables -L -n --line-numbers
    fi
}

reset_firewall() {
    log_warn "This will reset all firewall rules to defaults!"
    read -rp "Are you sure? (y/N): " confirm

    if [[ "${confirm,,}" != "y" ]]; then
        return
    fi

    if command -v ufw &>/dev/null; then
        sudo ufw --force reset
        log_success "UFW reset to defaults"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --complete-reload
        log_success "Firewalld reset"
    fi
}

show_firewall_help() {
    echo "Firewall management commands:"
    echo "  status          - Show firewall status"
    echo "  enable          - Enable and configure firewall"
    echo "  disable         - Disable firewall"
    echo "  allow <port>    - Allow traffic on port"
    echo "  deny <port>     - Deny traffic on port"
    echo "  list            - List firewall rules"
    echo "  reset           - Reset firewall to defaults"
}

#########################################
# Security Scanning
#########################################

run_security_scan() {
    log_section "Security Scan"

    local scan_type="${1:-basic}"

    case "$scan_type" in
        basic)
            basic_security_scan
            ;;
        containers)
            scan_containers
            ;;
        network)
            scan_network
            ;;
        vulnerabilities)
            scan_vulnerabilities
            ;;
        compliance)
            check_compliance
            ;;
        *)
            log_error "Unknown scan type: $scan_type"
            ;;
    esac
}

basic_security_scan() {
    log_info "Running basic security scan..."

    local issues=0

    # Check for default passwords
    log_subsection "Password Security"

    set -a
    source "${JACKER_DIR}/.env" 2>/dev/null || true
    set +a

    if [[ "${POSTGRES_PASSWORD}" == "changeme" ]] || [[ -z "${POSTGRES_PASSWORD}" ]]; then
        log_error "PostgreSQL using default or empty password"
        ((issues++))
    else
        log_success "PostgreSQL password is set"
    fi

    # Check authentication
    log_subsection "Authentication"

    if [[ -z "${OAUTH_CLIENT_ID:-}" ]] && [[ -z "${AUTHENTIK_SECRET_KEY:-}" ]]; then
        log_warn "No authentication configured"
        ((issues++))
    else
        log_success "Authentication is configured"
    fi

    # Check SSL configuration
    log_subsection "SSL/TLS"

    if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
        log_warn "Let's Encrypt not configured"
        ((issues++))
    else
        log_success "Let's Encrypt configured"
    fi

    # Check file permissions
    log_subsection "File Permissions"

    if [[ -f "${JACKER_DIR}/data/traefik/acme/acme.json" ]]; then
        local acme_perms=$(stat -c %a "${JACKER_DIR}/data/traefik/acme/acme.json" 2>/dev/null)
        if [[ "$acme_perms" != "600" ]]; then
            log_error "acme.json has incorrect permissions: $acme_perms (should be 600)"
            ((issues++))
        else
            log_success "acme.json permissions are correct"
        fi
    fi

    # Check exposed ports
    log_subsection "Exposed Ports"

    local exposed_ports=$(netstat -tuln 2>/dev/null | grep LISTEN | grep -v "127.0.0.1" | grep -v "::1" | awk '{print $4}' | cut -d: -f2 | sort -u)
    echo "Exposed ports: ${exposed_ports:-none}"

    # Summary
    echo
    if [[ $issues -eq 0 ]]; then
        log_success "No security issues found"
    else
        log_warn "Found $issues security issue(s)"
    fi
}

scan_containers() {
    log_info "Scanning containers for vulnerabilities..."

    if ! command -v trivy &>/dev/null; then
        log_warn "Trivy not installed. Installing..."
        install_trivy
    fi

    local containers=$(docker ps --format "{{.Names}}")

    for container in $containers; do
        log_subsection "Scanning $container"
        local image=$(docker inspect --format='{{.Config.Image}}' "$container")
        trivy image --severity HIGH,CRITICAL "$image" 2>/dev/null || log_warn "Failed to scan $image"
    done
}

install_trivy() {
    log_info "Installing Trivy..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
        sudo apt-get install -y wget apt-transport-https gnupg lsb-release
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
        echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
        sudo apt-get update
        sudo apt-get install -y trivy
    else
        # Download binary
        wget -qO- https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin
    fi
}

scan_network() {
    log_info "Scanning network configuration..."

    # Check Docker network isolation
    log_subsection "Docker Networks"

    docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}"

    # Check for containers on host network
    local host_containers=$(docker ps --filter "network=host" --format "{{.Names}}")
    if [[ -n "$host_containers" ]]; then
        log_warn "Containers using host network: $host_containers"
    else
        log_success "No containers using host network"
    fi

    # Check inter-container communication
    log_subsection "Inter-Container Communication"

    local icc_status=$(docker network inspect bridge | jq -r '.[0].Options."com.docker.network.bridge.enable_icc"')
    if [[ "$icc_status" == "false" ]]; then
        log_success "Inter-container communication disabled on bridge network"
    else
        log_warn "Inter-container communication enabled on bridge network"
    fi
}

scan_vulnerabilities() {
    log_info "Scanning for known vulnerabilities..."

    # Check Docker version
    local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
    log_info "Docker version: $docker_version"

    # Check compose files for security issues
    log_subsection "Compose Security"

    local security_issues=0

    # Check for privileged containers
    if grep -r "privileged: true" "${JACKER_DIR}/compose/" 2>/dev/null; then
        log_warn "Found privileged containers in compose files"
        ((security_issues++))
    fi

    # Check for containers running as root
    if grep -r "user: root" "${JACKER_DIR}/compose/" 2>/dev/null; then
        log_warn "Found containers explicitly running as root"
        ((security_issues++))
    fi

    # Check for host PID/network namespace
    if grep -r "pid: host" "${JACKER_DIR}/compose/" 2>/dev/null; then
        log_warn "Found containers using host PID namespace"
        ((security_issues++))
    fi

    if [[ $security_issues -eq 0 ]]; then
        log_success "No compose security issues found"
    else
        log_warn "Found $security_issues compose security issue(s)"
    fi
}

check_compliance() {
    log_info "Checking security compliance..."

    log_subsection "CIS Docker Benchmark"

    # Sample CIS checks
    local compliance_score=0
    local total_checks=0

    # Check: Ensure Docker daemon audit is configured
    ((total_checks++))
    if grep -q "dockerd" /etc/audit/audit.rules 2>/dev/null; then
        log_success "Docker daemon auditing configured"
        ((compliance_score++))
    else
        log_warn "Docker daemon auditing not configured"
    fi

    # Check: Ensure containers are restricted from acquiring new privileges
    ((total_checks++))
    if docker info 2>/dev/null | grep -q "no-new-privileges"; then
        log_success "no-new-privileges is set"
        ((compliance_score++))
    else
        log_warn "no-new-privileges not set"
    fi

    # Check: Ensure Docker content trust
    ((total_checks++))
    if [[ "${DOCKER_CONTENT_TRUST:-0}" == "1" ]]; then
        log_success "Docker content trust enabled"
        ((compliance_score++))
    else
        log_warn "Docker content trust not enabled"
    fi

    echo
    echo "Compliance Score: $compliance_score/$total_checks"
}

#########################################
# Security Hardening
#########################################

harden_security() {
    log_section "Security Hardening"

    echo "Hardening Options:"
    echo "1. Apply all recommendations"
    echo "2. Harden Docker daemon"
    echo "3. Harden containers"
    echo "4. Configure AppArmor/SELinux"
    echo "5. Enable audit logging"
    read -rp "Choose option [1]: " harden_choice
    harden_choice="${harden_choice:-1}"

    case "$harden_choice" in
        1)
            apply_all_hardening
            ;;
        2)
            harden_docker_daemon
            ;;
        3)
            harden_containers
            ;;
        4)
            configure_mandatory_access_control
            ;;
        5)
            enable_audit_logging
            ;;
        *)
            log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
            return 1 2>/dev/null || exit 1
            ;;
    esac
}

apply_all_hardening() {
    log_info "Applying all security hardening..."

    harden_docker_daemon
    harden_containers
    configure_mandatory_access_control
    enable_audit_logging

    log_success "Security hardening applied"
}

harden_docker_daemon() {
    log_info "Hardening Docker daemon..."

    # Update Docker daemon configuration
    local daemon_config="/etc/docker/daemon.json"
    local tmp_config="/tmp/daemon.json.tmp"

    # Read existing config or create new
    if [[ -f "$daemon_config" ]]; then
        cp "$daemon_config" "$tmp_config"
    else
        echo '{}' > "$tmp_config"
    fi

    # Add security settings
    jq '. + {
        "icc": false,
        "live-restore": true,
        "userland-proxy": false,
        "no-new-privileges": true,
        "seccomp-profile": "/etc/docker/seccomp.json",
        "log-level": "info",
        "log-driver": "json-file",
        "log-opts": {
            "max-size": "50m",
            "max-file": "5"
        }
    }' "$tmp_config" > "${tmp_config}.new"

    sudo mv "${tmp_config}.new" "$daemon_config"
    sudo systemctl restart docker

    log_success "Docker daemon hardened"
}

harden_containers() {
    log_info "Hardening container configurations..."

    # Create security policy file
    local policy_file="${JACKER_DIR}/compose/security-policy.yml"

    cat > "$policy_file" <<'EOF'
# Security policy to be included in all services
x-security-policy: &security-policy
  security_opt:
    - no-new-privileges:true
  cap_drop:
    - ALL
  read_only: false  # Set to true where possible
  tmpfs:
    - /tmp:noexec,nosuid,size=256M
EOF

    log_info "Security policy created at: $policy_file"
    log_warn "Include this policy in your service definitions where appropriate"
}

configure_mandatory_access_control() {
    log_info "Configuring mandatory access control..."

    if command -v aa-status &>/dev/null; then
        log_info "AppArmor detected"
        sudo aa-enforce /etc/apparmor.d/docker 2>/dev/null || log_warn "Failed to enforce Docker AppArmor profile"
    elif command -v getenforce &>/dev/null; then
        log_info "SELinux detected"
        if [[ "$(getenforce)" != "Enforcing" ]]; then
            log_warn "SELinux not in enforcing mode"
            read -rp "Enable SELinux enforcing mode? (y/N): " enable_selinux
            if [[ "${enable_selinux,,}" == "y" ]]; then
                sudo setenforce 1
                sudo sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
            fi
        else
            log_success "SELinux is in enforcing mode"
        fi
    else
        log_warn "No mandatory access control system found"
    fi
}

enable_audit_logging() {
    log_info "Enabling audit logging..."

    if command -v auditctl &>/dev/null; then
        # Add Docker audit rules
        cat << 'EOF' | sudo tee -a /etc/audit/rules.d/docker.rules
# Docker audit rules
-w /usr/bin/dockerd -k docker
-w /var/lib/docker -k docker
-w /etc/docker -k docker
-w /usr/lib/systemd/system/docker.service -k docker
-w /usr/lib/systemd/system/docker.socket -k docker
-w /etc/docker/daemon.json -k docker
-w /usr/bin/docker-containerd -k docker
-w /usr/bin/docker-runc -k docker
EOF

        # Restart audit service
        sudo service auditd restart 2>/dev/null || sudo systemctl restart auditd

        log_success "Audit logging enabled for Docker"
    else
        log_warn "Audit system not installed"
        read -rp "Install auditd? (y/N): " install_audit
        if [[ "${install_audit,,}" == "y" ]]; then
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y auditd
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y audit
            fi
            enable_audit_logging
        fi
    fi
}

#########################################
# Secrets Management
#########################################

list_secrets() {
    log_section "Docker Secrets"

    local secrets_dir="${JACKER_DIR}/secrets"

    if [[ ! -d "$secrets_dir" ]]; then
        log_error "Secrets directory not found: $secrets_dir"
        return 1
    fi

    log_info "Secrets in $secrets_dir:"
    echo ""

    local secret_files=(
        "postgres_password"
        "redis_password"
        "oauth_client_secret"
        "oauth_cookie_secret"
        "traefik_forward_oauth"
        "crowdsec_lapi_key"
        "crowdsec_bouncer_key"
    )

    local found=0
    local missing=0

    for secret in "${secret_files[@]}"; do
        if [[ -f "$secrets_dir/$secret" ]]; then
            local size=$(wc -c < "$secrets_dir/$secret")
            local perms=$(stat -c %a "$secrets_dir/$secret")
            if [[ "$perms" == "600" ]]; then
                log_success "$secret (${size} bytes, permissions: $perms)"
            else
                log_warn "$secret (${size} bytes, permissions: $perms - should be 600)"
            fi
            ((found++))
        else
            log_error "$secret - MISSING"
            ((missing++))
        fi
    done

    echo ""
    echo "Found: $found/$((found + missing)) secrets"

    if [[ $missing -gt 0 ]]; then
        log_warn "$missing secret(s) missing"
        log_info "Run 'jacker secrets generate' to create missing secrets"
        return 1
    else
        log_success "All secrets present"
    fi
}

generate_secrets() {
    log_section "Generating Docker Secrets"

    local secrets_dir="${JACKER_DIR}/secrets"

    # Ensure secrets directory exists
    mkdir -p "$secrets_dir"

    local secret_files=(
        "postgres_password"
        "redis_password"
        "oauth_client_secret"
        "oauth_cookie_secret"
        "traefik_forward_oauth"
        "crowdsec_lapi_key"
        "crowdsec_bouncer_key"
    )

    local generated=0
    local skipped=0

    for secret in "${secret_files[@]}"; do
        local secret_path="$secrets_dir/$secret"

        if [[ -f "$secret_path" ]]; then
            log_info "$secret - already exists (skipping)"
            ((skipped++))
        else
            log_info "Generating $secret..."
            openssl rand -base64 32 > "$secret_path"
            chmod 600 "$secret_path"
            log_success "$secret generated"
            ((generated++))
        fi
    done

    echo ""
    if [[ $generated -gt 0 ]]; then
        log_success "Generated $generated new secret(s)"
    fi
    if [[ $skipped -gt 0 ]]; then
        log_info "Skipped $skipped existing secret(s)"
    fi

    # Verify all secrets have correct permissions
    log_info "Verifying permissions..."
    chmod 600 "$secrets_dir"/*

    log_success "Secrets generation complete"
}

rotate_secrets() {
    local target="${1:-}"

    log_section "Rotating Docker Secrets"

    if [[ -z "$target" ]]; then
        log_error "Target secret required"
        echo "Usage: jacker secrets rotate <secret|all>"
        echo ""
        echo "Available secrets:"
        echo "  - postgres_password"
        echo "  - redis_password"
        echo "  - oauth_client_secret"
        echo "  - oauth_cookie_secret"
        echo "  - traefik_forward_oauth"
        echo "  - crowdsec_lapi_key"
        echo "  - crowdsec_bouncer_key"
        echo "  - all"
        return 1
    fi

    local secrets_dir="${JACKER_DIR}/secrets"

    if [[ ! -d "$secrets_dir" ]]; then
        log_error "Secrets directory not found: $secrets_dir"
        return 1
    fi

    # Create backup directory
    local backup_dir="${JACKER_DIR}/backups/secrets_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    if [[ "$target" == "all" ]]; then
        log_warn "This will rotate ALL secrets!"
        read -rp "Are you sure? (y/N): " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            log_info "Rotation cancelled"
            return 0
        fi

        log_info "Backing up existing secrets..."
        cp -a "$secrets_dir"/* "$backup_dir/" 2>/dev/null || true
        log_success "Backup created at: $backup_dir"

        log_info "Rotating all secrets..."

        local secret_files=(
            "postgres_password"
            "redis_password"
            "oauth_client_secret"
            "oauth_cookie_secret"
            "traefik_forward_oauth"
            "crowdsec_lapi_key"
            "crowdsec_bouncer_key"
        )

        for secret in "${secret_files[@]}"; do
            local secret_path="$secrets_dir/$secret"
            log_info "Rotating $secret..."
            openssl rand -base64 32 > "$secret_path"
            chmod 600 "$secret_path"
        done

        log_success "All secrets rotated"
        log_warn "You must restart services for changes to take effect:"
        log_info "  jacker stop && jacker start"
    else
        # Rotate single secret
        local secret_path="$secrets_dir/$target"

        if [[ ! -f "$secret_path" ]]; then
            log_error "Secret not found: $target"
            return 1
        fi

        log_info "Backing up $target..."
        cp "$secret_path" "$backup_dir/"
        log_success "Backup created at: $backup_dir/$target"

        log_info "Rotating $target..."
        openssl rand -base64 32 > "$secret_path"
        chmod 600 "$secret_path"

        log_success "Secret rotated: $target"
        log_warn "You must restart affected services for changes to take effect"
    fi
}

verify_secrets() {
    log_section "Verifying Docker Secrets"

    local secrets_dir="${JACKER_DIR}/secrets"

    if [[ ! -d "$secrets_dir" ]]; then
        log_error "Secrets directory not found: $secrets_dir"
        return 1
    fi

    local issues=0

    # Check directory permissions
    local dir_perms=$(stat -c %a "$secrets_dir")
    if [[ "$dir_perms" != "755" ]] && [[ "$dir_perms" != "775" ]]; then
        log_warn "Secrets directory permissions: $dir_perms (should be 755 or 775)"
        ((issues++))
    else
        log_success "Secrets directory permissions OK"
    fi

    # Check each secret
    local secret_files=(
        "postgres_password"
        "redis_password"
        "oauth_client_secret"
        "oauth_cookie_secret"
        "traefik_forward_oauth"
        "crowdsec_lapi_key"
        "crowdsec_bouncer_key"
    )

    for secret in "${secret_files[@]}"; do
        local secret_path="$secrets_dir/$secret"

        if [[ ! -f "$secret_path" ]]; then
            log_error "$secret - MISSING"
            ((issues++))
            continue
        fi

        # Check file permissions
        local perms=$(stat -c %a "$secret_path")
        if [[ "$perms" != "600" ]]; then
            log_warn "$secret - incorrect permissions: $perms (should be 600)"
            ((issues++))
        fi

        # Check file size (should be non-empty)
        local size=$(wc -c < "$secret_path")
        if [[ $size -eq 0 ]]; then
            log_error "$secret - empty file"
            ((issues++))
        elif [[ $size -lt 20 ]]; then
            log_warn "$secret - suspiciously small (${size} bytes)"
            ((issues++))
        else
            log_success "$secret - OK (${size} bytes)"
        fi
    done

    echo ""
    if [[ $issues -eq 0 ]]; then
        log_success "All secrets verified successfully"
    else
        log_error "Found $issues issue(s) with secrets"
        log_info "Run 'jacker secrets generate' to fix missing secrets"
        log_info "Run 'chmod 600 $secrets_dir/*' to fix permissions"
        return 1
    fi
}

# Export functions for use by jacker CLI
export -f manage_crowdsec
export -f manage_firewall
export -f run_security_scan
export -f harden_security
export -f list_secrets
export -f generate_secrets
export -f rotate_secrets
export -f verify_secrets
