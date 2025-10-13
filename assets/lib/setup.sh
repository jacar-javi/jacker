#!/usr/bin/env bash
# Jacker Setup Library
# Simplified and unified setup functions

set -euo pipefail

# Source common functions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

# Map log functions to common.sh functions
log_info() { info "$@"; }
log_success() { success "$@"; }
log_warn() { warning "$@"; }
log_error() { error "$@"; }
log_section() { section "$@"; }

#########################################
# Configuration Detection
#########################################

detect_system_config() {
    log_info "Detecting system configuration..."

    # Detect user and paths
    PUID=$(id -u)
    PGID=$(id -g)
    USERDIR="${HOME}"
    DOCKERDIR="$(cd "${JACKER_DIR}" && pwd)"
    DATADIR="${DOCKERDIR}/data"

    # Detect hostname and domain
    HOSTNAME=$(hostname -s)

    # Try to detect existing domain from various sources
    if compgen -G "/etc/letsencrypt/renewal/*.conf" > /dev/null; then
        DETECTED_DOMAIN=$(ls /etc/letsencrypt/renewal/*.conf 2>/dev/null | head -1 | xargs basename | sed 's/\.conf$//')
    elif command -v hostname &>/dev/null && hostname -f 2>/dev/null | grep -q '\.'; then
        DETECTED_DOMAIN=$(hostname -f)
    else
        DETECTED_DOMAIN=""
    fi

    # Detect if running in VM/container
    if grep -q "docker\|lxc\|virtualization" /proc/1/cgroup 2>/dev/null || \
       systemd-detect-virt 2>/dev/null | grep -qE "docker|lxc|kvm|qemu|vmware|virtualbox|hyperv"; then
        HOST_IS_VM=true
    else
        HOST_IS_VM=false
    fi

    log_success "System configuration detected"
}

#########################################
# Environment Setup
#########################################

load_existing_config() {
    # Load existing configuration values if .env exists
    if [[ -f "${JACKER_DIR}/.env" ]]; then
        log_info "Loading existing configuration..."

        # First, fix any known problematic unquoted values
        if grep -q '^HOMEPAGE_VAR_TITLE=Jacker Dashboard$' "${JACKER_DIR}/.env"; then
            sed -i 's/^HOMEPAGE_VAR_TITLE=Jacker Dashboard$/HOMEPAGE_VAR_TITLE="Jacker Dashboard"/' "${JACKER_DIR}/.env"
        fi

        # Source the existing .env file to get current values
        # Use a safer approach to avoid command execution from unquoted values
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Remove leading/trailing whitespace
            key="${key%%[[:space:]]}"
            value="${value#[[:space:]]}"
            
            # Export the variable
            export "$key=$value"
        done < "${JACKER_DIR}/.env"

        # Store existing values in variables with EXISTING_ prefix
        # Core configuration
        EXISTING_DOMAINNAME="${DOMAINNAME:-}"
        EXISTING_HOSTNAME="${HOSTNAME:-}"
        EXISTING_PUBLIC_FQDN="${PUBLIC_FQDN:-}"
        EXISTING_LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
        EXISTING_TZ="${TZ:-}"
        
        # OAuth configuration
        EXISTING_OAUTH_PROVIDER="${OAUTH_PROVIDER:-}"
        EXISTING_OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:-}"
        EXISTING_OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET:-}"
        EXISTING_OAUTH_WHITELIST="${OAUTH_WHITELIST:-}"
        EXISTING_OAUTH_SECRET="${OAUTH_SECRET:-}"
        EXISTING_OAUTH_COOKIE_SECRET="${OAUTH_COOKIE_SECRET:-}"
        EXISTING_OAUTH_SIGNATURE_KEY="${OAUTH_SIGNATURE_KEY:-}"
        
        # Email/SMTP configuration
        EXISTING_SMTP_HOST="${SMTP_HOST:-}"
        EXISTING_SMTP_PORT="${SMTP_PORT:-}"
        EXISTING_SMTP_USERNAME="${SMTP_USERNAME:-}"
        EXISTING_SMTP_PASSWORD="${SMTP_PASSWORD:-}"
        EXISTING_ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
        
        # Telegram configuration
        EXISTING_TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
        EXISTING_TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
        
        # Slack configuration
        EXISTING_SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
        
        # Network configuration
        EXISTING_DOCKER_DEFAULT_SUBNET="${DOCKER_DEFAULT_SUBNET:-}"
        EXISTING_SOCKET_PROXY_SUBNET="${SOCKET_PROXY_SUBNET:-}"
        EXISTING_TRAEFIK_PROXY_SUBNET="${TRAEFIK_PROXY_SUBNET:-}"
        
        # Database passwords
        EXISTING_POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
        EXISTING_REDIS_PASSWORD="${REDIS_PASSWORD:-}"
        
        # CrowdSec API keys
        EXISTING_CROWDSEC_TRAEFIK_BOUNCER_API_KEY="${CROWDSEC_TRAEFIK_BOUNCER_API_KEY:-}"
        EXISTING_CROWDSEC_IPTABLES_BOUNCER_API_KEY="${CROWDSEC_IPTABLES_BOUNCER_API_KEY:-}"
        EXISTING_CROWDSEC_API_LOCAL_PASSWORD="${CROWDSEC_API_LOCAL_PASSWORD:-}"
        EXISTING_CROWDSEC_AGENT_PASSWORD="${CROWDSEC_AGENT_PASSWORD:-}"
        
        # Authentik configuration
        EXISTING_AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
        EXISTING_AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD:-}"
        
        # Grafana configuration
        EXISTING_GF_SECURITY_ADMIN_PASSWORD="${GF_SECURITY_ADMIN_PASSWORD:-}"
        
        # Service-specific passwords
        EXISTING_PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-}"
        EXISTING_CODE_PASSWORD="${CODE_PASSWORD:-}"
        EXISTING_CODE_SUDO_PASSWORD="${CODE_SUDO_PASSWORD:-}"

        log_success "Existing configuration loaded"
    fi
}

create_env_file() {
    local quick_mode="${1:-false}"
    local preserve_existing="${2:-false}"

    log_info "Creating .env configuration..."

    # Load existing configuration if preserving
    if [[ "$preserve_existing" == "true" ]]; then
        load_existing_config
    fi

    # Start with defaults
    cp "${JACKER_DIR}/.env.defaults" "${JACKER_DIR}/.env.tmp"

    # Apply detected values
    sed -i "s|^PUID=.*|PUID=${PUID}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PGID=.*|PGID=${PGID}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^USERDIR=.*|USERDIR=${USERDIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^DOCKERDIR=.*|DOCKERDIR=${DOCKERDIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^DATADIR=.*|DATADIR=${DATADIR}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOSTNAME=.*|HOSTNAME=${HOSTNAME}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOST_IS_VM=.*|HOST_IS_VM=${HOST_IS_VM}|" "${JACKER_DIR}/.env.tmp"

    if [[ "$quick_mode" == "false" ]]; then
        # Interactive configuration
        configure_interactive "$preserve_existing"
    else
        # Quick mode - use minimal required inputs
        configure_quick "$preserve_existing"
    fi

    # Generate secrets
    generate_all_secrets "$preserve_existing"

    # Move tmp to final
    mv "${JACKER_DIR}/.env.tmp" "${JACKER_DIR}/.env"
    chmod 600 "${JACKER_DIR}/.env"

    log_success ".env file created"
}

configure_quick() {
    local preserve_existing="${1:-false}"
    log_info "Quick configuration mode"

    # Domain configuration
    local default_domain="${EXISTING_DOMAINNAME:-example.com}"
    local default_hostname="${EXISTING_HOSTNAME:-myserver}"
    
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_DOMAINNAME}" ]]; then
        read -rp "Enter your domain name [${default_domain}]: " domain
        domain="${domain:-${default_domain}}"
        read -rp "Enter your hostname [${default_hostname}]: " hostname_input
        hostname_input="${hostname_input:-${default_hostname}}"
    else
        read -rp "Enter your domain name (e.g., example.com): " domain
        read -rp "Enter your hostname (e.g., myserver): " hostname_input
    fi

    sed -i "s|^DOMAINNAME=.*|DOMAINNAME=${domain}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOSTNAME=.*|HOSTNAME=${hostname_input}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PUBLIC_FQDN=.*|PUBLIC_FQDN=${hostname_input}.${domain}|" "${JACKER_DIR}/.env.tmp"

    # Let's Encrypt
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_LETSENCRYPT_EMAIL}" ]]; then
        read -rp "Enter email for Let's Encrypt certificates [${EXISTING_LETSENCRYPT_EMAIL}]: " le_email
        le_email="${le_email:-${EXISTING_LETSENCRYPT_EMAIL}}"
    else
        read -rp "Enter email for Let's Encrypt certificates: " le_email
    fi
    sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${le_email}|" "${JACKER_DIR}/.env.tmp"

    # OAuth (optional)
    echo
    echo "OAuth configuration (press Enter to skip for now):"
    
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_CLIENT_ID}" ]]; then
        read -rp "Google OAuth Client ID [${EXISTING_OAUTH_CLIENT_ID}]: " oauth_id
        oauth_id="${oauth_id:-${EXISTING_OAUTH_CLIENT_ID}}"
        read -rsp "Google OAuth Client Secret [****] (press Enter to keep): " oauth_secret
        echo
        oauth_secret="${oauth_secret:-${EXISTING_OAUTH_CLIENT_SECRET}}"
        read -rp "Allowed emails (comma-separated) [${EXISTING_OAUTH_WHITELIST}]: " oauth_emails
        oauth_emails="${oauth_emails:-${EXISTING_OAUTH_WHITELIST}}"
    else
        read -rp "Google OAuth Client ID: " oauth_id
        read -rp "Google OAuth Client Secret: " oauth_secret
        read -rp "Allowed emails (comma-separated): " oauth_emails
    fi

    if [[ -n "$oauth_id" ]]; then
        sed -i "s|^OAUTH_CLIENT_ID=.*|OAUTH_CLIENT_ID=${oauth_id}|" "${JACKER_DIR}/.env.tmp"
        sed -i "s|^OAUTH_CLIENT_SECRET=.*|OAUTH_CLIENT_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
        sed -i "s|^OAUTH_WHITELIST=.*|OAUTH_WHITELIST=${oauth_emails}|" "${JACKER_DIR}/.env.tmp"
    fi
}

configure_interactive() {
    local preserve_existing="${1:-false}"
    log_info "Interactive configuration mode"

    # Full interactive configuration
    # Domain and networking
    local default_domain="${EXISTING_DOMAINNAME:-${DETECTED_DOMAIN:-example.com}}"
    read -rp "Domain name [${default_domain}]: " domain
    domain="${domain:-${default_domain}}"

    local default_hostname="${EXISTING_HOSTNAME:-${HOSTNAME}}"
    read -rp "Hostname [${default_hostname}]: " hostname_input
    hostname_input="${hostname_input:-${default_hostname}}"

    sed -i "s|^DOMAINNAME=.*|DOMAINNAME=${domain}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^HOSTNAME=.*|HOSTNAME=${hostname_input}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^PUBLIC_FQDN=.*|PUBLIC_FQDN=${hostname_input}.${domain}|" "${JACKER_DIR}/.env.tmp"

    # Let's Encrypt
    local default_le_email="${EXISTING_LETSENCRYPT_EMAIL:-}"
    if [[ -n "$default_le_email" ]]; then
        read -rp "Let's Encrypt email address [${default_le_email}]: " le_email
        le_email="${le_email:-${default_le_email}}"
    else
        read -rp "Let's Encrypt email address: " le_email
    fi
    sed -i "s|^LETSENCRYPT_EMAIL=.*|LETSENCRYPT_EMAIL=${le_email}|" "${JACKER_DIR}/.env.tmp"

    # OAuth configuration
    echo
    echo "Authentication Configuration:"

    # Determine current auth method if reconfiguring
    local default_auth_choice="1"
    if [[ "$preserve_existing" == "true" ]]; then
        if [[ -n "${EXISTING_AUTHENTIK_SECRET_KEY}" ]]; then
            default_auth_choice="2"
            echo "(Currently using: Authentik)"
        elif [[ -n "${EXISTING_OAUTH_CLIENT_ID}" ]]; then
            default_auth_choice="1"
            echo "(Currently using: Google OAuth)"
        else
            default_auth_choice="3"
            echo "(Currently using: No authentication)"
        fi
    fi

    echo "1. Google OAuth (recommended)"
    echo "2. Authentik (self-hosted)"
    echo "3. Skip authentication (not recommended for production)"
    read -rp "Choose authentication method [${default_auth_choice}]: " auth_choice
    auth_choice="${auth_choice:-${default_auth_choice}}"

    case "$auth_choice" in
        1)
            configure_google_oauth "$preserve_existing"
            ;;
        2)
            configure_authentik "$preserve_existing"
            ;;
        3)
            log_warn "Skipping authentication - services will be publicly accessible!"
            ;;
        *)
            log_error "Invalid option: $auth_choice"
            return 1
            ;;
    esac

    # Advanced options
    echo
    read -rp "Configure advanced options? (y/N): " advanced
    if [[ "${advanced,,}" == "y" ]]; then
        configure_advanced_options "$preserve_existing"
    fi
}

configure_google_oauth() {
    local preserve_existing="${1:-false}"
    echo
    echo "Google OAuth Configuration"
    echo "See: https://console.cloud.google.com/apis/credentials"

    # OAuth Client ID
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_CLIENT_ID}" ]]; then
        read -rp "OAuth Client ID [${EXISTING_OAUTH_CLIENT_ID}]: " oauth_id
        oauth_id="${oauth_id:-${EXISTING_OAUTH_CLIENT_ID}}"
    else
        read -rp "OAuth Client ID: " oauth_id
    fi

    # OAuth Client Secret
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_CLIENT_SECRET}" ]]; then
        read -rsp "OAuth Client Secret [****] (press Enter to keep existing): " oauth_secret
        echo
        oauth_secret="${oauth_secret:-${EXISTING_OAUTH_CLIENT_SECRET}}"
    else
        read -rp "OAuth Client Secret: " oauth_secret
    fi

    # Allowed emails
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_WHITELIST}" ]]; then
        read -rp "Allowed email addresses (comma-separated) [${EXISTING_OAUTH_WHITELIST}]: " oauth_emails
        oauth_emails="${oauth_emails:-${EXISTING_OAUTH_WHITELIST}}"
    else
        read -rp "Allowed email addresses (comma-separated): " oauth_emails
    fi

    sed -i "s|^OAUTH_CLIENT_ID=.*|OAUTH_CLIENT_ID=${oauth_id}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_CLIENT_SECRET=.*|OAUTH_CLIENT_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_WHITELIST=.*|OAUTH_WHITELIST=${oauth_emails}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^OAUTH_PROVIDER=.*|OAUTH_PROVIDER=google|" "${JACKER_DIR}/.env.tmp"
}

configure_authentik() {
    local preserve_existing="${1:-false}"
    echo
    echo "Authentik will be configured automatically"

    # Use existing secrets if preserving, otherwise generate new ones
    local secret_key
    local pg_password
    
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_AUTHENTIK_SECRET_KEY}" ]]; then
        echo "Using existing Authentik configuration"
        secret_key="${EXISTING_AUTHENTIK_SECRET_KEY}"
        pg_password="${EXISTING_AUTHENTIK_POSTGRES_PASSWORD:-$(openssl rand -base64 32 | tr -d '\n')}"
    else
        # Generate new Authentik secrets
        secret_key=$(openssl rand -base64 60 | tr -d '\n')
        pg_password=$(openssl rand -base64 32 | tr -d '\n')
    fi

    # Update .env.tmp
    sed -i "/^# AUTHENTIK_VERSION=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_SECRET_KEY=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_PASSWORD=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_DB=/s/^# //" "${JACKER_DIR}/.env.tmp"
    sed -i "/^# AUTHENTIK_POSTGRES_USER=/s/^# //" "${JACKER_DIR}/.env.tmp"

    sed -i "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=${secret_key}|" "${JACKER_DIR}/.env.tmp"
    sed -i "s|^AUTHENTIK_POSTGRES_PASSWORD=.*|AUTHENTIK_POSTGRES_PASSWORD=${pg_password}|" "${JACKER_DIR}/.env.tmp"

    # Enable Authentik in docker-compose.yml
    sed -i '/path: compose\/authentik.yml/s/^#[[:space:]]*//' "${JACKER_DIR}/docker-compose.yml"

    # Get domain from .env.tmp for the log message
    local domain=$(grep "^DOMAINNAME=" "${JACKER_DIR}/.env.tmp" | cut -d= -f2)
    log_info "Authentik configured - will be available at https://auth.${domain}"
}

configure_advanced_options() {
    local preserve_existing="${1:-false}"
    echo
    echo "Advanced Configuration Options:"

    # Timezone
    local default_tz="${EXISTING_TZ:-Europe/Madrid}"
    read -rp "Timezone [${default_tz}]: " tz
    tz="${tz:-${default_tz}}"
    sed -i "s|^TZ=.*|TZ=${tz}|" "${JACKER_DIR}/.env.tmp"

    # Network configuration
    local default_custom_net="N"
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_DOCKER_DEFAULT_SUBNET}" ]]; then
        default_custom_net="y"
        echo "(Currently using custom Docker network: ${EXISTING_DOCKER_DEFAULT_SUBNET})"
    fi
    read -rp "Configure custom Docker networks? (y/N) [${default_custom_net}]: " custom_net
    custom_net="${custom_net:-${default_custom_net}}"

    if [[ "${custom_net,,}" == "y" ]]; then
        local default_subnet="${EXISTING_DOCKER_DEFAULT_SUBNET:-192.168.69.0/24}"
        read -rp "Docker default subnet [${default_subnet}]: " docker_subnet
        docker_subnet="${docker_subnet:-${default_subnet}}"
        sed -i "s|^DOCKER_DEFAULT_SUBNET=.*|DOCKER_DEFAULT_SUBNET=${docker_subnet}|" "${JACKER_DIR}/.env.tmp"
    fi

    # Alerting
    local default_alerts="N"
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_SMTP_HOST}" ]]; then
        default_alerts="y"
        echo "(Email alerts currently configured)"
    fi
    read -rp "Configure email alerts? (y/N) [${default_alerts}]: " alerts
    alerts="${alerts:-${default_alerts}}"

    if [[ "${alerts,,}" == "y" ]]; then
        configure_alerting "$preserve_existing"
    fi
}

configure_alerting() {
    local preserve_existing="${1:-false}"
    echo
    echo "Alert Configuration:"
    echo "1. Email alerts only"
    echo "2. Telegram alerts only" 
    echo "3. Both Email and Telegram alerts"
    echo "4. Skip alert configuration"
    
    local default_alert_choice="1"
    if [[ "$preserve_existing" == "true" ]]; then
        if [[ -n "${EXISTING_TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${EXISTING_SMTP_HOST}" ]]; then
            default_alert_choice="3"
        elif [[ -n "${EXISTING_TELEGRAM_BOT_TOKEN}" ]]; then
            default_alert_choice="2"
        elif [[ -n "${EXISTING_SMTP_HOST}" ]]; then
            default_alert_choice="1"
        else
            default_alert_choice="4"
        fi
    fi
    
    read -rp "Choose alert configuration [${default_alert_choice}]: " alert_choice
    alert_choice="${alert_choice:-${default_alert_choice}}"
    
    case "$alert_choice" in
        1|3)
            echo
            echo "Email Alert Configuration:"
            
            # SMTP Host
            local default_smtp_host="${EXISTING_SMTP_HOST:-smtp.gmail.com}"
            read -rp "SMTP Host [${default_smtp_host}]: " smtp_host
            smtp_host="${smtp_host:-${default_smtp_host}}"
            
            # SMTP Port
            local default_smtp_port="${EXISTING_SMTP_PORT:-587}"
            read -rp "SMTP Port [${default_smtp_port}]: " smtp_port
            smtp_port="${smtp_port:-${default_smtp_port}}"
            
            # SMTP Username
            if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_SMTP_USERNAME}" ]]; then
                read -rp "SMTP Username [${EXISTING_SMTP_USERNAME}]: " smtp_user
                smtp_user="${smtp_user:-${EXISTING_SMTP_USERNAME}}"
            else
                read -rp "SMTP Username: " smtp_user
            fi
            
            # SMTP Password
            if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_SMTP_PASSWORD}" ]]; then
                read -rsp "SMTP Password [****] (press Enter to keep existing): " smtp_pass
                echo
                smtp_pass="${smtp_pass:-${EXISTING_SMTP_PASSWORD}}"
            else
                read -rsp "SMTP Password: " smtp_pass
                echo
            fi
            
            # Alert recipient email
            if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_ALERT_EMAIL_TO}" ]]; then
                read -rp "Alert recipient email [${EXISTING_ALERT_EMAIL_TO}]: " alert_email
                alert_email="${alert_email:-${EXISTING_ALERT_EMAIL_TO}}"
            else
                read -rp "Alert recipient email: " alert_email
            fi
            
            sed -i "s|^SMTP_HOST=.*|SMTP_HOST=${smtp_host}|" "${JACKER_DIR}/.env.tmp"
            sed -i "s|^SMTP_PORT=.*|SMTP_PORT=${smtp_port}|" "${JACKER_DIR}/.env.tmp"
            sed -i "s|^SMTP_USERNAME=.*|SMTP_USERNAME=${smtp_user}|" "${JACKER_DIR}/.env.tmp"
            sed -i "s|^SMTP_PASSWORD=.*|SMTP_PASSWORD=${smtp_pass}|" "${JACKER_DIR}/.env.tmp"
            sed -i "s|^ALERT_EMAIL_TO=.*|ALERT_EMAIL_TO=${alert_email}|" "${JACKER_DIR}/.env.tmp"
            ;;
    esac
    
    case "$alert_choice" in
        2|3)
            echo
            echo "Telegram Alert Configuration:"
            echo "To set up Telegram alerts:"
            echo "1. Create a bot with @BotFather on Telegram"
            echo "2. Get your bot token from @BotFather"
            echo "3. Add the bot to a group/channel or message it directly"
            echo "4. Get the chat ID (you can use @userinfobot or @RawDataBot)"
            echo
            
            # Telegram Bot Token
            if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_TELEGRAM_BOT_TOKEN}" ]]; then
                read -rp "Telegram Bot Token [${EXISTING_TELEGRAM_BOT_TOKEN:0:10}...] (Enter to keep): " telegram_token
                telegram_token="${telegram_token:-${EXISTING_TELEGRAM_BOT_TOKEN}}"
            else
                read -rp "Telegram Bot Token: " telegram_token
            fi
            
            # Telegram Chat ID
            if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_TELEGRAM_CHAT_ID}" ]]; then
                read -rp "Telegram Chat ID [${EXISTING_TELEGRAM_CHAT_ID}]: " telegram_chat_id
                telegram_chat_id="${telegram_chat_id:-${EXISTING_TELEGRAM_CHAT_ID}}"
            else
                read -rp "Telegram Chat ID (can be negative for groups): " telegram_chat_id
            fi
            
            sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=${telegram_token}|" "${JACKER_DIR}/.env.tmp"
            sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=${telegram_chat_id}|" "${JACKER_DIR}/.env.tmp"
            
            # Test Telegram connection if token and chat ID are provided
            if [[ -n "$telegram_token" ]] && [[ -n "$telegram_chat_id" ]]; then
                echo
                read -rp "Send a test message to Telegram? (y/N): " test_telegram
                if [[ "${test_telegram,,}" == "y" ]]; then
                    local test_message="🚀 Jacker Alert System Test - Configuration successful!"
                    if curl -s -X POST "https://api.telegram.org/bot${telegram_token}/sendMessage" \
                        -d "chat_id=${telegram_chat_id}" \
                        -d "text=${test_message}" \
                        -d "parse_mode=Markdown" > /dev/null 2>&1; then
                        log_success "Test message sent to Telegram successfully!"
                    else
                        log_warn "Failed to send test message. Please verify your bot token and chat ID."
                    fi
                fi
            fi
            ;;
        4)
            log_info "Skipping alert configuration"
            ;;
    esac
}

#########################################
# Secret Generation
#########################################

generate_all_secrets() {
    local preserve_existing="${1:-false}"
    log_info "Generating secrets..."

    # OAuth secrets
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_SECRET}" ]]; then
        sed -i "s|^OAUTH_SECRET=.*|OAUTH_SECRET=${EXISTING_OAUTH_SECRET}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^OAUTH_SECRET=.\+" "${JACKER_DIR}/.env.tmp"; then
        local oauth_secret=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^OAUTH_SECRET=.*|OAUTH_SECRET=${oauth_secret}|" "${JACKER_DIR}/.env.tmp"
    fi

    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_OAUTH_COOKIE_SECRET}" ]]; then
        sed -i "s|^OAUTH_COOKIE_SECRET=.*|OAUTH_COOKIE_SECRET=${EXISTING_OAUTH_COOKIE_SECRET}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^OAUTH_COOKIE_SECRET=.\+" "${JACKER_DIR}/.env.tmp"; then
        # Generate URL-safe base64-encoded 32-byte secret for OAuth2-Proxy
        local cookie_secret=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
        sed -i "s|^OAUTH_COOKIE_SECRET=.*|OAUTH_COOKIE_SECRET=${cookie_secret}|" "${JACKER_DIR}/.env.tmp"
    fi

    # PostgreSQL password
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_POSTGRES_PASSWORD}" ]]; then
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${EXISTING_POSTGRES_PASSWORD}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^POSTGRES_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local pg_password=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${pg_password}|" "${JACKER_DIR}/.env.tmp"
    fi

    # Redis password
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_REDIS_PASSWORD}" ]]; then
        sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${EXISTING_REDIS_PASSWORD}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^REDIS_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local redis_password=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${redis_password}|" "${JACKER_DIR}/.env.tmp"
    fi

    # CrowdSec API keys
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_CROWDSEC_TRAEFIK_BOUNCER_API_KEY}" ]]; then
        sed -i "s|^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.*|CROWDSEC_TRAEFIK_BOUNCER_API_KEY=${EXISTING_CROWDSEC_TRAEFIK_BOUNCER_API_KEY}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_traefik_key=$(openssl rand -hex 32)
        sed -i "s|^CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.*|CROWDSEC_TRAEFIK_BOUNCER_API_KEY=${cs_traefik_key}|" "${JACKER_DIR}/.env.tmp"
    fi

    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_CROWDSEC_IPTABLES_BOUNCER_API_KEY}" ]]; then
        sed -i "s|^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.*|CROWDSEC_IPTABLES_BOUNCER_API_KEY=${EXISTING_CROWDSEC_IPTABLES_BOUNCER_API_KEY}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_iptables_key=$(openssl rand -hex 32)
        sed -i "s|^CROWDSEC_IPTABLES_BOUNCER_API_KEY=.*|CROWDSEC_IPTABLES_BOUNCER_API_KEY=${cs_iptables_key}|" "${JACKER_DIR}/.env.tmp"
    fi

    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_CROWDSEC_API_LOCAL_PASSWORD}" ]]; then
        sed -i "s|^CROWDSEC_API_LOCAL_PASSWORD=.*|CROWDSEC_API_LOCAL_PASSWORD=${EXISTING_CROWDSEC_API_LOCAL_PASSWORD}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^CROWDSEC_API_LOCAL_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local cs_api_pass=$(openssl rand -base64 32 | tr -d '\n')
        sed -i "s|^CROWDSEC_API_LOCAL_PASSWORD=.*|CROWDSEC_API_LOCAL_PASSWORD=${cs_api_pass}|" "${JACKER_DIR}/.env.tmp"
    fi

    # Grafana admin password
    if [[ "$preserve_existing" == "true" ]] && [[ -n "${EXISTING_GF_SECURITY_ADMIN_PASSWORD}" ]]; then
        sed -i "s|^GF_SECURITY_ADMIN_PASSWORD=.*|GF_SECURITY_ADMIN_PASSWORD=${EXISTING_GF_SECURITY_ADMIN_PASSWORD}|" "${JACKER_DIR}/.env.tmp"
    elif ! grep -q "^GF_SECURITY_ADMIN_PASSWORD=.\+" "${JACKER_DIR}/.env.tmp"; then
        local grafana_password=$(openssl rand -base64 16 | tr -d '\n')
        sed -i "s|^GF_SECURITY_ADMIN_PASSWORD=.*|GF_SECURITY_ADMIN_PASSWORD=${grafana_password}|" "${JACKER_DIR}/.env.tmp"
    fi

    log_success "Secrets generated/preserved"
}

#########################################
# Directory Structure
#########################################

create_directory_structure() {
    log_info "Creating directory structure..."

    # Create all required directories based on compose services
    local dirs=(
        "data/traefik/acme"
        "data/traefik/logs"
        "data/oauth2-proxy"
        # CrowdSec: Only create config/parsers and data directories
        # Hub, scenarios, and patterns are managed dynamically by CrowdSec
        "data/crowdsec/config/parsers/s02-enrich"
        "data/crowdsec/data"
        "data/postgres"
        "data/redis"
        "data/loki/data/rules"
        "data/loki/data/chunks"
        "data/loki/data/compactor"
        "data/promtail"
        "data/grafana/data"
        "data/prometheus"
        "data/alertmanager/data"
        "data/alertmanager/certs"
        "data/alertmanager/templates"
        "data/homepage"
        "data/portainer"
        "data/vscode"
        "data/node-exporter"
        "data/jaeger"
        "config/traefik/rules"
        "config/oauth2-proxy"
        "config/crowdsec"
        "config/postgres"
        "config/redis"
        "config/loki"
        "config/grafana/provisioning/dashboards"
        "config/grafana/provisioning/datasources"
        "config/grafana/provisioning/notifiers"
        "config/prometheus"
        "config/alertmanager"
        "config/homepage"
        "config/jaeger"
        "secrets"
    )

    for dir in "${dirs[@]}"; do
        if ! mkdir -p "${JACKER_DIR}/${dir}" 2>/dev/null; then
            # If mkdir fails due to permissions, try with sudo and fix ownership
            log_warn "Permission issue with ${dir}, fixing..."
            sudo mkdir -p "${JACKER_DIR}/${dir}"
            sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/${dir}"
        fi
    done

    # Set specific permissions
    touch "${JACKER_DIR}/data/traefik/acme/acme.json" 2>/dev/null || \
        { sudo touch "${JACKER_DIR}/data/traefik/acme/acme.json" && sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/data/traefik/acme/acme.json"; }
    chmod 600 "${JACKER_DIR}/data/traefik/acme/acme.json"

    # Secrets directory should be restricted
    chmod 700 "${JACKER_DIR}/secrets" 2>/dev/null || \
        { sudo chmod 700 "${JACKER_DIR}/secrets"; }

    log_success "Directory structure created"
}

#########################################
# Set Directory Ownership
#########################################

set_directory_ownership() {
    log_info "Setting directory ownership for service users..."

    # Load PUID/PGID from .env if it exists (for PostgreSQL)
    local puid=1000
    local pgid=1000
    if [[ -f "${JACKER_DIR}/.env" ]]; then
        puid=$(grep "^PUID=" "${JACKER_DIR}/.env" | cut -d= -f2)
        pgid=$(grep "^PGID=" "${JACKER_DIR}/.env" | cut -d= -f2)
    fi

    # PostgreSQL (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/postgres" ]]; then
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/postgres" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/postgres"
    fi

    # Redis (uses PUID:PGID from .env, same as PostgreSQL)
    if [[ -d "${JACKER_DIR}/data/redis" ]]; then
        # Ensure group write permission for redis data subdirectory
        chmod -R 775 "${JACKER_DIR}/data/redis/data" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/redis/data"

        # Set ownership to match PUID:PGID from .env
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/redis" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/redis"
    fi

    # Loki (UID:GID 10001:10001)
    if [[ -d "${JACKER_DIR}/data/loki" ]]; then
        chown -R 10001:10001 "${JACKER_DIR}/data/loki" 2>/dev/null || \
        sudo chown -R 10001:10001 "${JACKER_DIR}/data/loki"
    fi

    # Grafana (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/grafana" ]]; then
        # Ensure group write permission
        chmod -R 775 "${JACKER_DIR}/data/grafana" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/grafana"

        # Set ownership to match PUID:PGID from .env
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/grafana" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/grafana"
    fi

    # Prometheus (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/prometheus" ]]; then
        # Ensure group write permission
        chmod -R 775 "${JACKER_DIR}/data/prometheus" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/prometheus"

        # Set ownership to match PUID:PGID from .env
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/prometheus" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/prometheus"
    fi

    # Alertmanager (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/alertmanager" ]]; then
        # Ensure group write permission
        chmod -R 775 "${JACKER_DIR}/data/alertmanager" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/alertmanager"

        # Set ownership to match PUID:PGID from .env
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/alertmanager" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/alertmanager"
    fi

    # CrowdSec (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/crowdsec" ]]; then
        # Ensure group write permission
        chmod -R 775 "${JACKER_DIR}/data/crowdsec" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/crowdsec"

        # Set ownership to match PUID:PGID from .env
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/crowdsec" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/crowdsec"
    fi

    # Jaeger (uses PUID:PGID from .env)
    if [[ -d "${JACKER_DIR}/data/jaeger" ]]; then
        # Create badger subdirectory if it doesn't exist
        mkdir -p "${JACKER_DIR}/data/jaeger/badger" 2>/dev/null || \
        sudo mkdir -p "${JACKER_DIR}/data/jaeger/badger"

        # Ensure group write permission
        chmod -R 775 "${JACKER_DIR}/data/jaeger" 2>/dev/null || \
        sudo chmod -R 775 "${JACKER_DIR}/data/jaeger"

        # Set ownership to match PUID:PGID from .env (not hardcoded UID)
        chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/jaeger" 2>/dev/null || \
        sudo chown -R "${puid}:${pgid}" "${JACKER_DIR}/data/jaeger"
    fi

    log_success "Directory ownership configured"
}

#########################################
# Configuration Files
#########################################

create_configuration_files() {
    log_info "Creating configuration files..."

    # Source the .env file
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Process templates
    local templates_dir="${JACKER_DIR}/assets/templates"

    if [[ -d "$templates_dir" ]]; then
        # Traefik configuration
        if [[ -f "$templates_dir/traefik.yml.template" ]]; then
            envsubst < "$templates_dir/traefik.yml.template" > "${JACKER_DIR}/config/traefik/traefik.yml" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/traefik.yml.template' > '${JACKER_DIR}/config/traefik/traefik.yml'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/traefik/traefik.yml"; }
        fi

        # Loki configuration
        if [[ -f "$templates_dir/loki-config.yml.template" ]]; then
            envsubst < "$templates_dir/loki-config.yml.template" > "${JACKER_DIR}/config/loki/loki-config.yml" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/loki-config.yml.template' > '${JACKER_DIR}/config/loki/loki-config.yml'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/loki/loki-config.yml"; }
        fi

        # Promtail configuration
        if [[ -f "$templates_dir/promtail-config.yml.template" ]]; then
            envsubst < "$templates_dir/promtail-config.yml.template" > "${JACKER_DIR}/config/loki/promtail-config.yml" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/promtail-config.yml.template' > '${JACKER_DIR}/config/loki/promtail-config.yml'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/loki/promtail-config.yml"; }
        fi

        # OAuth2 Proxy configuration
        if [[ -f "$templates_dir/oauth2-proxy.cfg.template" ]]; then
            log_info "Generating OAuth2 Proxy configuration from template..."
            envsubst < "$templates_dir/oauth2-proxy.cfg.template" > "${JACKER_DIR}/config/oauth2-proxy/oauth2-proxy.cfg" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/oauth2-proxy.cfg.template' > '${JACKER_DIR}/config/oauth2-proxy/oauth2-proxy.cfg'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/oauth2-proxy/oauth2-proxy.cfg"; }

            # Append cookie_secret to config (OAuth2-Proxy reads it from config, not env _FILE in v7.7.1)
            echo "" >> "${JACKER_DIR}/config/oauth2-proxy/oauth2-proxy.cfg"
            echo "cookie_secret = \"${OAUTH_COOKIE_SECRET}\"" >> "${JACKER_DIR}/config/oauth2-proxy/oauth2-proxy.cfg"
        fi

        # CrowdSec configuration
        if [[ -f "$templates_dir/config.yaml.local.template" ]]; then
            envsubst < "$templates_dir/config.yaml.local.template" > "${JACKER_DIR}/data/crowdsec/config/config.yaml.local" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/config.yaml.local.template' > '${JACKER_DIR}/data/crowdsec/config/config.yaml.local'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/data/crowdsec/config/config.yaml.local"; }
        fi

        # CrowdSec hub pre-installation (read-only filesystem compatibility)
        log_info "Pre-installing CrowdSec hub collections..."

        # Create hub directory structure
        mkdir -p "${JACKER_DIR}/data/crowdsec/hub" 2>/dev/null || \
            { sudo mkdir -p "${JACKER_DIR}/data/crowdsec/hub" && \
              sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/data/crowdsec/hub"; }

        # Pre-install hub collections using temporary container
        log_info "Starting temporary CrowdSec container for hub setup..."
        docker run --rm \
            --name crowdsec-init \
            -v "${JACKER_DIR}/data/crowdsec/config:/etc/crowdsec:rw" \
            -v "${JACKER_DIR}/data/crowdsec/hub:/var/lib/crowdsec/data:rw" \
            crowdsecurity/crowdsec:v1.7.0 \
            sh -c "cscli hub update && \
                   cscli collections install crowdsecurity/linux && \
                   cscli collections install crowdsecurity/traefik && \
                   cscli parsers install crowdsecurity/whitelists && \
                   echo 'Hub collections pre-installed successfully'" 2>&1 || {
                log_warn "CrowdSec hub pre-installation failed, will retry during service initialization"
            }

        # Set proper ownership on hub directory
        chown -R "$(id -u):$(id -g)" "${JACKER_DIR}/data/crowdsec/hub" 2>/dev/null || \
            sudo chown -R "$(id -u):$(id -g)" "${JACKER_DIR}/data/crowdsec/hub"

        # Verify hub installation
        if [[ -d "${JACKER_DIR}/data/crowdsec/hub/collections" ]]; then
            log_success "CrowdSec hub collections pre-installed and verified"
        else
            log_warn "CrowdSec hub collections directory not found, may need runtime installation"
        fi

        # Homepage configuration
        if [[ -f "$templates_dir/homepage-settings.yaml.template" ]]; then
            envsubst < "$templates_dir/homepage-settings.yaml.template" > "${JACKER_DIR}/config/homepage/settings.yaml" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/homepage-settings.yaml.template' > '${JACKER_DIR}/config/homepage/settings.yaml'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/homepage/settings.yaml"; }
        fi

        # Homepage custom CSS and JS
        if [[ -f "$templates_dir/homepage-custom.css.template" ]]; then
            cp "$templates_dir/homepage-custom.css.template" "${JACKER_DIR}/config/homepage/custom.css" 2>/dev/null || \
                { sudo cp "$templates_dir/homepage-custom.css.template" "${JACKER_DIR}/config/homepage/custom.css" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/homepage/custom.css"; }
        fi
        if [[ -f "$templates_dir/homepage-custom.js.template" ]]; then
            cp "$templates_dir/homepage-custom.js.template" "${JACKER_DIR}/config/homepage/custom.js" 2>/dev/null || \
                { sudo cp "$templates_dir/homepage-custom.js.template" "${JACKER_DIR}/config/homepage/custom.js" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/homepage/custom.js"; }
        fi

        # Alertmanager configuration
        if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] || [[ -n "${SMTP_HOST}" ]] || [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
            log_info "Configuring Alertmanager with notification channels..."
            if [[ -f "$templates_dir/alertmanager-with-telegram.yml.template" ]]; then
                envsubst < "$templates_dir/alertmanager-with-telegram.yml.template" > "${JACKER_DIR}/config/alertmanager/alertmanager.yml" 2>/dev/null || \
                    { sudo bash -c "envsubst < '$templates_dir/alertmanager-with-telegram.yml.template' > '${JACKER_DIR}/config/alertmanager/alertmanager.yml'" && \
                      sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/alertmanager/alertmanager.yml"; }
            fi
        elif [[ -f "$templates_dir/alertmanager.yml.template" ]]; then
            envsubst < "$templates_dir/alertmanager.yml.template" > "${JACKER_DIR}/config/alertmanager/alertmanager.yml" 2>/dev/null || \
                { sudo bash -c "envsubst < '$templates_dir/alertmanager.yml.template' > '${JACKER_DIR}/config/alertmanager/alertmanager.yml'" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/config/alertmanager/alertmanager.yml"; }
        fi

        # Telegram webhook template
        if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
            log_info "Setting up Telegram webhook templates..."
            mkdir -p "${JACKER_DIR}/data/telegram-webhook/templates" 2>/dev/null || \
                { sudo mkdir -p "${JACKER_DIR}/data/telegram-webhook/templates" && \
                  sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/data/telegram-webhook/templates"; }
            if [[ -f "${JACKER_DIR}/assets/configs/telegram/telegram.tmpl" ]]; then
                cp "${JACKER_DIR}/assets/configs/telegram/telegram.tmpl" "${JACKER_DIR}/data/telegram-webhook/templates/" 2>/dev/null || \
                    { sudo cp "${JACKER_DIR}/assets/configs/telegram/telegram.tmpl" "${JACKER_DIR}/data/telegram-webhook/templates/" && \
                      sudo chown "$(id -u):$(id -g)" "${JACKER_DIR}/data/telegram-webhook/templates/telegram.tmpl"; }
            fi
        fi
    fi

    # Create Traefik middleware files
    create_traefik_middlewares

    # Create secrets files
    create_secrets_files
    
    # Configure alert integrations
    configure_alert_integrations

    log_success "Configuration files created"
}

create_traefik_middlewares() {
    local rules_dir="${JACKER_DIR}/config/traefik/rules"

    # OAuth middleware
    cat > "${rules_dir}/middlewares-oauth.yml" <<EOF
http:
  middlewares:
    oauth:
      forwardAuth:
        address: "http://oauth:4181"
        trustForwardHeader: true
        authResponseHeaders:
          - "X-Forwarded-User"
EOF

    # Rate limiting middleware
    cat > "${rules_dir}/middlewares-rate-limit.yml" <<EOF
http:
  middlewares:
    rate-limit-default:
      rateLimit:
        average: 100
        burst: 200
    rate-limit-strict:
      rateLimit:
        average: 10
        burst: 20
    rate-limit-api:
      rateLimit:
        average: 50
        burst: 100
EOF

    # Security headers middleware
    cat > "${rules_dir}/middlewares-secure-headers.yml" <<EOF
http:
  middlewares:
    middlewares-secure-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 63072000
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
EOF

    # Compression middleware
    cat > "${rules_dir}/middlewares-compress.yml" <<EOF
http:
  middlewares:
    middlewares-compress:
      compress:
        minResponseBodyBytes: 1024
EOF

    # CORS middleware
    cat > "${rules_dir}/middlewares-cors.yml" <<EOF
http:
  middlewares:
    middlewares-cors:
      headers:
        accessControlAllowMethods:
          - "GET"
          - "POST"
          - "PUT"
          - "DELETE"
          - "OPTIONS"
        accessControlAllowHeaders:
          - "*"
        accessControlAllowOriginList:
          - "*"
        accessControlMaxAge: 100
        addVaryHeader: true
EOF

    # Cache middleware
    cat > "${rules_dir}/middlewares-cache.yml" <<EOF
http:
  middlewares:
    middlewares-cache:
      plugin:
        cache:
          maxExpiry: 300s
EOF

    # Chain middlewares
    cat > "${rules_dir}/chain-oauth.yml" <<EOF
http:
  middlewares:
    chain-oauth:
      chain:
        middlewares:
          - rate-limit-default@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
          - oauth@file

    chain-oauth-no-crowdsec:
      chain:
        middlewares:
          - rate-limit-strict@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
          - oauth@file
EOF

    cat > "${rules_dir}/chain-no-oauth.yml" <<EOF
http:
  middlewares:
    chain-no-oauth:
      chain:
        middlewares:
          - rate-limit-default@file
          - middlewares-secure-headers@file
          - middlewares-compress@file

    chain-api:
      chain:
        middlewares:
          - rate-limit-api@file
          - middlewares-cors@file
          - middlewares-secure-headers@file
          - middlewares-compress@file
EOF

    # TLS options
    cat > "${rules_dir}/tls-opts.yml" <<EOF
tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
      curvePreferences:
        - CurveP521
        - CurveP384
      sniStrict: true
EOF
}

create_secrets_files() {
    local secrets_dir="${JACKER_DIR}/secrets"

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Create individual secret files for Docker secrets
    echo "${POSTGRES_PASSWORD}" > "${secrets_dir}/postgres_password"
    echo "${OAUTH_CLIENT_SECRET}" > "${secrets_dir}/oauth_client_secret"
    echo "${OAUTH_COOKIE_SECRET}" > "${secrets_dir}/oauth_cookie_secret"
    echo "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}" > "${secrets_dir}/crowdsec_bouncer_key"
    echo "${CROWDSEC_API_LOCAL_PASSWORD}" > "${secrets_dir}/crowdsec_lapi_key"

    # Generate additional secrets if needed
    openssl rand -base64 32 > "${secrets_dir}/grafana_admin_password"
    openssl rand -base64 32 > "${secrets_dir}/redis_password"
    openssl rand -base64 48 > "${secrets_dir}/portainer_secret"
    openssl rand -base64 48 > "${secrets_dir}/traefik_forward_oauth"

    # Set restrictive permissions on most secrets
    chmod 600 "${secrets_dir}"/*

    # However, some secrets need to be readable by containers running as different UIDs
    # OAuth secrets - used by OAuth2-proxy running as UID 65532
    chmod 644 "${secrets_dir}/oauth_client_secret" 2>/dev/null || true
    chmod 644 "${secrets_dir}/oauth_cookie_secret" 2>/dev/null || true

    # PostgreSQL password - used by postgres-exporter running as nobody user
    chmod 644 "${secrets_dir}/postgres_password" 2>/dev/null || true

    # Create .gitignore for secrets
    cat > "${secrets_dir}/.gitignore" <<EOF
# Ignore all secret files
*
# Except this file and README
!.gitignore
!README.md
EOF
}

# Configure alert integrations (Telegram, Slack, Email)
# Configure alert integrations (Telegram, Slack, Email)
configure_alert_integrations() {
    log_info "Configuring alert integrations..."
    
    # Configure Alertmanager if any notification method is set
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] || [[ -n "${SMTP_HOST}" ]] || [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        log_info "Setting up Alertmanager configuration..."
        
        # Create Alertmanager config directory if it doesn't exist
        mkdir -p "${JACKER_DIR}/config/alertmanager"
        
        # Note about Telegram configuration
        if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
            log_info "Telegram credentials configured"
            log_warn "Note: To receive Telegram alerts, you'll need to add alertmanager-bot service"
            log_info "See docs/TELEGRAM_ALERTS.md for setup instructions"
        fi
        
        log_success "Alert integrations configured"
    fi
    
    # Configure Grafana alerting
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] || [[ -n "${SMTP_HOST}" ]] || [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        configure_grafana_alerting
    fi
}

# Configure Grafana alerting channels
configure_grafana_alerting() {
    log_info "Configuring Grafana notification channels..."

    # Ensure directory exists with correct ownership
    # Use sudo to create and set ownership to avoid permission issues
    sudo mkdir -p "${JACKER_DIR}/config/grafana/provisioning/notifiers"
    sudo chown -R "$(id -u):$(id -g)" "${JACKER_DIR}/config/grafana"

    # Create notification channels configuration
    cat > "${JACKER_DIR}/config/grafana/provisioning/notifiers/telegram.yaml" <<EOF
apiVersion: 1

notifiers:
EOF
    
    # Add Telegram notifier if configured
    if [[ -n "${TELEGRAM_BOT_TOKEN}" ]] && [[ -n "${TELEGRAM_CHAT_ID}" ]]; then
        cat >> "${JACKER_DIR}/config/grafana/provisioning/notifiers/telegram.yaml" <<EOF
  - name: Telegram
    type: telegram
    uid: telegram-notifier
    org_id: 1
    is_default: true
    send_reminder: true
    frequency: 5m
    disable_resolve_message: false
    settings:
      chatid: "${TELEGRAM_CHAT_ID}"
      bottoken: "${TELEGRAM_BOT_TOKEN}"
      uploadImage: true
EOF
    fi
    
    # Add Email notifier if configured
    if [[ -n "${SMTP_HOST}" ]]; then
        cat >> "${JACKER_DIR}/config/grafana/provisioning/notifiers/telegram.yaml" <<EOF
  - name: Email
    type: email
    uid: email-notifier
    org_id: 1
    is_default: false
    send_reminder: true
    frequency: 1h
    disable_resolve_message: false
    settings:
      addresses: "${ALERT_EMAIL_TO}"
      singleEmail: false
EOF
    fi
    
    # Add Slack notifier if configured
    if [[ -n "${SLACK_WEBHOOK_URL}" ]]; then
        cat >> "${JACKER_DIR}/config/grafana/provisioning/notifiers/telegram.yaml" <<EOF
  - name: Slack
    type: slack
    uid: slack-notifier
    org_id: 1
    is_default: false
    send_reminder: true
    frequency: 30m
    disable_resolve_message: false
    settings:
      url: "${SLACK_WEBHOOK_URL}"
      channel: "${SLACK_CHANNEL_INFO:-#monitoring}"
      username: "Jacker Monitoring"
      icon_emoji: ":rocket:"
      uploadImage: true
EOF
    fi
    
    log_success "Grafana notification channels configured"
}

#########################################
# System Preparation
#########################################

prepare_system() {
    log_info "Preparing system..."

    # Update package lists
    update_system_packages

    # Install Docker if needed
    if ! command -v docker &>/dev/null; then
        install_docker
    fi

    # Install Docker Compose if needed
    if ! docker compose version &>/dev/null 2>&1; then
        install_docker_compose
    fi

    # Install required packages
    install_required_packages

    # Configure Docker
    configure_docker

    # Configure UFW if requested
    if command -v ufw &>/dev/null; then
        read -rp "Configure UFW firewall? (y/N): " configure_ufw
        if [[ "${configure_ufw,,}" == "y" ]]; then
            setup_ufw
        fi
    fi

    log_success "System prepared"
}

update_system_packages() {
    log_info "Updating system packages..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get update
    elif command -v dnf &>/dev/null; then
        sudo dnf check-update || true
    elif command -v yum &>/dev/null; then
        sudo yum check-update || true
    fi
}

install_docker() {
    log_info "Installing Docker..."

    if command -v apt-get &>/dev/null; then
        # Ubuntu/Debian
        curl -fsSL https://get.docker.com | sudo sh
    elif command -v dnf &>/dev/null; then
        # Fedora
        sudo dnf install -y docker-ce docker-ce-cli containerd.io
    elif command -v yum &>/dev/null; then
        # RHEL/CentOS
        sudo yum install -y docker-ce docker-ce-cli containerd.io
    else
        log_error "Unsupported distribution for Docker installation"
        return 1
    fi

    # Add user to docker group
    sudo usermod -aG docker "$USER"

    # Start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    log_success "Docker installed"
}

install_docker_compose() {
    log_info "Installing Docker Compose plugin..."

    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y docker-compose-plugin
    else
        # Manual installation for other distributions
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi

    log_success "Docker Compose installed"
}

install_required_packages() {
    log_info "Installing required packages..."

    local packages=(
        "curl"
        "wget"
        "git"
        "python3"
        "python3-pip"
        "openssl"
        "jq"
        "htop"
        "net-tools"
    )

    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y "${packages[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${packages[@]}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "${packages[@]}"
    fi
}

configure_docker() {
    log_info "Configuring Docker..."

    # Create docker group if it doesn't exist
    if ! getent group docker > /dev/null 2>&1; then
        log_info "Creating docker group..."
        sudo groupadd docker
    fi

    # Add current user to docker group
    if ! groups "$USER" | grep -q docker; then
        log_info "Adding $USER to docker group..."
        sudo usermod -aG docker "$USER"
        log_warn "You'll need to log out and back in for docker group membership to take effect"
        
        # For the current session, we need to use sudo for docker commands
        # Set a flag so we know to use sudo
        export NEED_DOCKER_SUDO=true
    else
        export NEED_DOCKER_SUDO=false
    fi

    # Create Docker daemon configuration
    sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "50m",
        "max-file": "3"
    },
    "default-address-pools": [
        {
            "base": "192.168.64.0/18",
            "size": 24
        }
    ]
}
EOF

    # Restart Docker to apply configuration
    sudo systemctl restart docker
    
    # If we need sudo, inform the user
    if [[ "${NEED_DOCKER_SUDO}" == "true" ]]; then
        log_info "Docker commands will use 'sudo' until you log out and back in"
    fi
}

setup_ufw() {
    log_info "Configuring UFW firewall..."

    # Load UFW configuration from .env
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Enable UFW
    sudo ufw --force enable

    # Allow SSH
    if [[ -n "${UFW_ALLOW_SSH}" ]]; then
        IFS=',' read -ra SSH_SOURCES <<< "${UFW_ALLOW_SSH}"
        for source in "${SSH_SOURCES[@]}"; do
            sudo ufw allow from "${source}" to any port 22 proto tcp comment "SSH from ${source}"
        done
    else
        sudo ufw allow 22/tcp comment "SSH"
    fi

    # Allow HTTP and HTTPS
    sudo ufw allow 80/tcp comment "HTTP"
    sudo ufw allow 443/tcp comment "HTTPS"

    # Allow from specific sources if configured
    if [[ -n "${UFW_ALLOW_FROM}" ]]; then
        IFS=',' read -ra ALLOW_SOURCES <<< "${UFW_ALLOW_FROM}"
        for source in "${ALLOW_SOURCES[@]}"; do
            sudo ufw allow from "${source}" comment "Allow from ${source}"
        done
    fi

    # Docker-specific rules
    sudo ufw allow in on docker0

    # Reload UFW
    sudo ufw reload

    log_success "UFW firewall configured"
}

#########################################
# Service Initialization
#########################################

initialize_services() {
    log_info "Initializing services..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if [[ "${NEED_DOCKER_SUDO:-false}" == "true" ]]; then
        docker_cmd="sudo docker"
    fi

    # Start core infrastructure services first
    log_info "Starting core services..."
    
    # Start socket-proxy and redis first (they don't have network conflicts)
    $docker_cmd compose up -d socket-proxy redis || {
        log_warn "Initial service start failed, trying alternate approach..."
        # If that fails, try starting services one at a time
        $docker_cmd compose up -d socket-proxy 2>/dev/null || true
        $docker_cmd compose up -d redis 2>/dev/null || true
    }
    
    # Start postgres separately to handle network issues
    log_info "Starting PostgreSQL..."
    $docker_cmd compose up -d postgres || {
        log_warn "PostgreSQL network conflict detected, fixing..."
        # If postgres fails due to multiple networks, we need to handle it differently
        # First check if postgres container exists but is stopped
        if $docker_cmd ps -a | grep -q postgres; then
            # Remove the existing container
            $docker_cmd rm -f postgres 2>/dev/null || true
        fi
        
        # Try starting postgres again
        $docker_cmd compose up -d postgres 2>/dev/null || {
            log_error "Failed to start PostgreSQL. This may be due to network configuration."
            log_info "Attempting to fix PostgreSQL network configuration..."
            
            # Create a temporary compose override to start postgres with single network
            cat > "${JACKER_DIR}/docker-compose.override.yml" <<EOF
services:
  postgres:
    networks:
      - database
EOF
            # Start with single network
            $docker_cmd compose up -d postgres
            
            # Remove override file
            rm -f "${JACKER_DIR}/docker-compose.override.yml"
            
            # Now connect to additional networks
            $docker_cmd network connect monitoring postgres 2>/dev/null || true
            $docker_cmd network connect backup postgres 2>/dev/null || true
        }
    }

    # Wait for PostgreSQL to be ready
    wait_for_postgres

    # Initialize PostgreSQL databases
    initialize_postgres_databases

    # Start remaining services
    log_info "Starting all services..."
    $docker_cmd compose up -d

    # Wait for services to be healthy
    wait_for_services

    # Configure CrowdSec
    configure_crowdsec

    log_success "Services initialized"
}

wait_for_postgres() {
    log_info "Waiting for PostgreSQL to be ready..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if [[ "${NEED_DOCKER_SUDO:-false}" == "true" ]]; then
        docker_cmd="sudo docker"
    fi

    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if $docker_cmd compose exec -T postgres pg_isready -U "${POSTGRES_USER:-crowdsec}" &>/dev/null; then
            log_success "PostgreSQL is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    log_error "PostgreSQL failed to start"
    return 1
}

initialize_postgres_databases() {
    log_info "Initializing PostgreSQL databases..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if [[ "${NEED_DOCKER_SUDO:-false}" == "true" ]]; then
        docker_cmd="sudo docker"
    fi

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    # Create databases from POSTGRES_MULTIPLE_DATABASES
    if [[ -n "${POSTGRES_MULTIPLE_DATABASES}" ]]; then
        IFS=',' read -ra DATABASES <<< "${POSTGRES_MULTIPLE_DATABASES}"
        for db in "${DATABASES[@]}"; do
            db=$(echo "$db" | xargs)  # Trim whitespace
            log_info "Creating database: ${db}"

            $docker_cmd compose exec -T postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE IF NOT EXISTS ${db};" 2>/dev/null || true
        done
    fi

    log_success "PostgreSQL databases initialized"
}

wait_for_services() {
    log_info "Waiting for services to be ready..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if [[ "${NEED_DOCKER_SUDO:-false}" == "true" ]]; then
        docker_cmd="sudo docker"
    fi

    local services=(
        "traefik:80"
        "oauth:4181"
        "grafana:3000"
        "prometheus:9090"
    )

    for service in "${services[@]}"; do
        local service_name="${service%:*}"
        local service_port="${service#*:}"

        log_info "Checking ${service_name}..."
        local max_attempts=30
        local attempt=0

        while [[ $attempt -lt $max_attempts ]]; do
            if $docker_cmd compose exec -T "${service_name}" wget -q --spider "http://localhost:${service_port}" 2>/dev/null; then
                log_success "${service_name} is ready"
                break
            fi

            attempt=$((attempt + 1))
            sleep 2
        done
    done
}

configure_crowdsec() {
    log_info "Configuring CrowdSec..."

    # Determine if we need to use sudo for docker commands
    local docker_cmd="docker"
    if [[ "${NEED_DOCKER_SUDO:-false}" == "true" ]]; then
        docker_cmd="sudo docker"
    fi

    # Note: Bouncer registration removed - CrowdSec auto-registers bouncers via
    # BOUNCER_KEY_TRAEFIK_FILE and BOUNCER_KEY_FIREWALL_FILE environment variables

    # Install collections
    $docker_cmd compose exec -T crowdsec cscli collections install crowdsecurity/traefik 2>/dev/null || true
    $docker_cmd compose exec -T crowdsec cscli collections install crowdsecurity/http-cve 2>/dev/null || true

    # Reload CrowdSec
    $docker_cmd compose exec -T crowdsec cscli reload 2>/dev/null || true

    log_success "CrowdSec configured"
}

#########################################
# Main Setup Function
#########################################

setup_jacker() {
    local mode="${1:-interactive}"
    local preserve_existing=false

    log_section "Jacker Setup"

    # Check if already installed
    if [[ -f "${JACKER_DIR}/.env" ]]; then
        log_warn "Existing installation detected"
        echo "1. Reinstall (preserve configuration)"
        echo "2. Fresh install (backup and start over)"
        echo "3. Cancel"
        read -rp "Choose option [1]: " install_choice
        install_choice="${install_choice:-1}"

        case "$install_choice" in
            1)
                backup_existing_installation
                preserve_existing=true
                ;;
            2)
                backup_existing_installation
                rm -f "${JACKER_DIR}/.env"
                preserve_existing=false
                ;;
            3)
                log_info "Installation cancelled"
                return 0
                ;;
            *)
                log_error "Invalid option: $1" 2>/dev/null || echo "Invalid option" >&2
                return 1 2>/dev/null || exit 1
                ;;
        esac
    fi

    # Detect system configuration
    detect_system_config

    # Create environment configuration
    if [[ "$mode" == "quick" ]]; then
        create_env_file true "$preserve_existing"
    else
        create_env_file false "$preserve_existing"
    fi

    # Create directory structure
    create_directory_structure

    # Create configuration files
    create_configuration_files

    # Set directory ownership (AFTER configs are written)
    set_directory_ownership

    # Prepare system
    prepare_system

    # Initialize services
    initialize_services

    # Install bash completion
    install_bash_completion

    # Show completion message
    show_completion_message
}

backup_existing_installation() {
    log_info "Backing up existing installation..."

    local backup_dir="${JACKER_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    # Backup .env
    [[ -f "${JACKER_DIR}/.env" ]] && cp "${JACKER_DIR}/.env" "$backup_dir/"

    # Backup data directory (use sudo to read files owned by service users)
    if [[ -d "${JACKER_DIR}/data" ]]; then
        sudo tar -czf "$backup_dir/data.tar.gz" -C "${JACKER_DIR}" data 2>&1 | grep -v "Cannot open" || true
    fi

    # Backup secrets (use sudo to read restricted files)
    if [[ -d "${JACKER_DIR}/secrets" ]]; then
        sudo tar -czf "$backup_dir/secrets.tar.gz" -C "${JACKER_DIR}" secrets 2>/dev/null || true
    fi

    log_success "Backup created at: $backup_dir"
}

#########################################
# Bash Completion Installation
#########################################

install_bash_completion() {
    log_info "Installing bash completion for jacker command..."

    local completion_file="${JACKER_DIR}/assets/jacker-completion.bash"
    local install_path=""

    # Determine installation path based on system
    if [[ -d /etc/bash_completion.d ]]; then
        install_path="/etc/bash_completion.d/jacker"
    elif [[ -d /usr/local/etc/bash_completion.d ]]; then
        install_path="/usr/local/etc/bash_completion.d/jacker"
    elif [[ -d /usr/share/bash-completion/completions ]]; then
        install_path="/usr/share/bash-completion/completions/jacker"
    else
        # Fallback: add to user's .bashrc
        log_info "No system-wide completion directory found, installing to ~/.bashrc"
        if ! grep -q "source.*jacker-completion.bash" ~/.bashrc 2>/dev/null; then
            echo "" >> ~/.bashrc
            echo "# Jacker CLI completion" >> ~/.bashrc
            echo "source ${completion_file}" >> ~/.bashrc
            log_success "Bash completion added to ~/.bashrc"
            log_info "Run 'source ~/.bashrc' or restart your shell to enable completion"
        else
            log_info "Bash completion already configured in ~/.bashrc"
        fi
        return 0
    fi

    # Install to system-wide location
    if [[ -f "$completion_file" ]]; then
        if sudo cp "$completion_file" "$install_path" 2>/dev/null; then
            sudo chmod 644 "$install_path"
            log_success "Bash completion installed to $install_path"
            log_info "Completion will be available in new shell sessions"
        else
            log_warn "Could not install bash completion to system directory"
            log_info "You can manually source it: source ${completion_file}"
        fi
    else
        log_warn "Completion file not found at $completion_file"
    fi
}

show_completion_message() {
    log_section "Installation Complete!"

    # Load environment variables
    set -a
    source "${JACKER_DIR}/.env"
    set +a

    echo
    echo "Jacker has been successfully installed!"
    echo
    echo "Access your services at:"
    echo "  Dashboard:    https://homepage.${PUBLIC_FQDN}"
    echo "  Traefik:      https://traefik.${PUBLIC_FQDN}"
    echo "  Grafana:      https://grafana.${PUBLIC_FQDN}"
    echo "  Prometheus:   https://prometheus.${PUBLIC_FQDN}"
    echo "  Portainer:    https://portainer.${PUBLIC_FQDN}"

    if [[ -n "${AUTHENTIK_SECRET_KEY}" ]]; then
        echo "  Authentik:    https://auth.${PUBLIC_FQDN}"
    fi

    echo
    echo "Management commands:"
    echo "  ./jacker start     - Start all services"
    echo "  ./jacker stop      - Stop all services"
    echo "  ./jacker status    - Check service status"
    echo "  ./jacker health    - Run health check"
    echo "  ./jacker help      - Show all commands"
    echo

    if [[ -z "${OAUTH_CLIENT_ID}" ]] && [[ -z "${AUTHENTIK_SECRET_KEY}" ]]; then
        log_warn "No authentication configured - services are publicly accessible!"
        echo "Run './jacker config oauth' to configure authentication"
    fi
}

# Export functions for use by jacker CLI
export -f setup_jacker
export -f detect_system_config
export -f create_env_file
export -f create_directory_structure
export -f create_configuration_files
export -f prepare_system
export -f initialize_services
export -f backup_existing_installation
