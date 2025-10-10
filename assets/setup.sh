#!/usr/bin/env bash
#
# Script: setup.sh
# Description: Main installation script for Jacker
# Usage: ./setup.sh
# Notes: This script runs in two phases (before and after reboot)
#

set -euo pipefail

# Initialize variables that may be set externally
os="${os:-}"
dist="${dist:-}"

# Logging setup
LOGDIR="$(cd "$(dirname "$0")" && pwd)/logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/jacker-setup-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "$LOGFILE")
exec 2>&1

echo "Jacker Setup Started at $(date)"
echo "Log file: $LOGFILE"
echo ""

unknown_os ()
{
  echo "ERROR: Unfortunately, your operating system distribution and version are not supported by Jacker."
  echo
  echo "You can override the OS detection by setting os= and dist= prior to running this script."
  echo
  echo "For example, to force Ubuntu Trusty: os=ubuntu dist=trusty ./setup.sh"
  exit 1
}

gpg_check ()
{
  echo "Checking for gpg..."
  if command -v gpg > /dev/null; then
    echo "Detected gpg..."
  else
    echo "Installing gnupg for GPG verification..."
    apt-get install -y gnupg
    if [ "$?" -ne "0" ]; then
      echo "Unable to install GPG! Your base system has a problem; please check your default OS's package repositories because GPG should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
    if [ "$?" -ne "0" ]; then
      echo "Unable to install curl! Your base system has a problem; please check your default OS's package repositories because curl should work."
      echo "Repository installation aborted."
      exit 1
    fi
  fi
}

install_debian_keyring ()
{
  if [ "${os,,}" = "debian" ]; then
    echo "Installing debian-archive-keyring which is needed for installing "
    echo "apt-transport-https on many Debian systems."
    apt-get install -y debian-archive-keyring &> /dev/null
  fi
}


detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      # Check for Raspbian using DISTRIB_ID (from lsb-release)
      if [ "${DISTRIB_ID:-}" = "Raspbian" ]; then
        os=raspbian
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`(cat /etc/issue || true) | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as $os/$dist."
}

detect_apt_version ()
{
  apt_version_full=`(apt-get -v || true) | head -1 | awk '{ print $2 }'`
  apt_version_major=`echo $apt_version_full | cut -d. -f1`
  apt_version_minor=`echo $apt_version_full | cut -d. -f2`
  apt_version_modified="${apt_version_major}${apt_version_minor}0"

  echo "Detected apt version as ${apt_version_full}"
}

validate_hostname ()
{
  local hostname=$1
  # Check hostname format (alphanumeric and hyphens, not starting/ending with hyphen)
  if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    echo "ERROR: Invalid hostname format. Use only alphanumeric characters and hyphens."
    return 1
  fi
  return 0
}

validate_domain ()
{
  local domain=$1
  # Basic domain validation
  if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: Invalid domain format. Example: example.com"
    return 1
  fi
  return 0
}

validate_email ()
{
  local email=$1
  # Basic email validation
  if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: Invalid email format."
    return 1
  fi
  return 0
}

validate_email_list ()
{
  local email_list=$1
  IFS=',' read -ra emails <<< "$email_list"
  for email in "${emails[@]}"; do
    email=$(echo "$email" | xargs) # trim whitespace
    if ! validate_email "$email"; then
      return 1
    fi
  done
  return 0
}

load_existing_env ()
{
  if [ -f ".env" ]; then
    echo "Loading existing .env values..."
    # Source the .env file to get existing values
    set -a
    source .env
    set +a

    # Store existing values
    EXISTING_HOSTNAME="${HOSTNAME:-}"
    EXISTING_DOMAINNAME="${DOMAINNAME:-}"
    EXISTING_TZ="${TZ:-}"
    EXISTING_UFW_ALLOW_PORTS="${UFW_ALLOW_PORTS:-}"
    EXISTING_UFW_ALLOW_SSH="${UFW_ALLOW_SSH:-}"
    EXISTING_OAUTH_CLIENT_ID="${OAUTH_CLIENT_ID:-}"
    EXISTING_OAUTH_CLIENT_SECRET="${OAUTH_CLIENT_SECRET:-}"
    EXISTING_OAUTH_WHITELIST="${OAUTH_WHITELIST:-}"
    EXISTING_LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
    EXISTING_LOCAL_IPS="${LOCAL_IPS:-}"
    EXISTING_DOCKER_SUBNETS="${CODE_TRAEFIK_SUBNET_IP:-},${DOCKER_DEFAULT_SUBNET:-},${TRAEFIK_PROXY_SUBNET:-}"

    # Store PostgreSQL values (no MySQL anymore)
    EXISTING_POSTGRES_DB="${POSTGRES_DB:-}"
    EXISTING_POSTGRES_USER="${POSTGRES_USER:-}"
    EXISTING_POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

    # Store alerting values
    EXISTING_SMTP_HOST="${SMTP_HOST:-}"
    EXISTING_SMTP_PORT="${SMTP_PORT:-}"
    EXISTING_SMTP_FROM="${SMTP_FROM:-}"
    EXISTING_SMTP_USERNAME="${SMTP_USERNAME:-}"
    EXISTING_SMTP_PASSWORD="${SMTP_PASSWORD:-}"
    EXISTING_ALERT_EMAIL_TO="${ALERT_EMAIL_TO:-}"
    EXISTING_TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
    EXISTING_TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

    return 0
  fi
  return 1
}

prompt_with_default ()
{
  local prompt_text="$1"
  local default_value="$2"
  local response

  if [ -n "$default_value" ]; then
    read -r -p "$prompt_text [$default_value]: " response
    echo "${response:-$default_value}"
  else
    read -r -p "$prompt_text: " response
    echo "$response"
  fi
}

confirm_action ()
{
  local prompt_text="$1"
  local default="${2:-N}"
  local response

  if [ "$default" = "Y" ]; then
    read -r -p "$prompt_text [Y/n]: " response
    case "${response:-Y}" in
      [nN][oO]|[nN]) return 1 ;;
      *) return 0 ;;
    esac
  else
    read -r -p "$prompt_text [y/N]: " response
    case "$response" in
      [yY][eE][sS]|[yY]) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

create_env_files()
{
  source .env.defaults

  # Initialize EXISTING_* variables with empty defaults
  EXISTING_HOSTNAME=""
  EXISTING_DOMAINNAME=""
  EXISTING_TZ=""
  EXISTING_UFW_ALLOW_PORTS=""
  EXISTING_UFW_ALLOW_SSH=""
  EXISTING_OAUTH_CLIENT_ID=""
  EXISTING_OAUTH_CLIENT_SECRET=""
  EXISTING_OAUTH_WHITELIST=""
  EXISTING_LETSENCRYPT_EMAIL=""
  EXISTING_LOCAL_IPS=""
  EXISTING_DOCKER_SUBNETS=""
  EXISTING_POSTGRES_DB=""
  EXISTING_POSTGRES_USER=""
  EXISTING_POSTGRES_PASSWORD=""
  EXISTING_SMTP_HOST=""
  EXISTING_SMTP_PORT=""
  EXISTING_SMTP_FROM=""
  EXISTING_SMTP_USERNAME=""
  EXISTING_SMTP_PASSWORD=""
  EXISTING_ALERT_EMAIL_TO=""
  EXISTING_TELEGRAM_BOT_TOKEN=""
  EXISTING_TELEGRAM_CHAT_ID=""

  # Check if we should load existing values
  local has_existing=false
  if load_existing_env; then
    has_existing=true
    echo ""
    echo "=========================================="
    echo "  Existing configuration detected"
    echo "=========================================="
    echo "You can keep existing values by pressing Enter"
    echo ""
  fi

  # Create .env from template
  export PUID=`id -u $USER`
  export PGID=`id -g $USER`

  # Set timezone with default
  local default_tz="${EXISTING_TZ:-$(cat /etc/timezone 2>/dev/null || echo 'UTC')}"
  export TZ=$(prompt_with_default "Enter your timezone" "$default_tz")

  export USERDIR=`eval echo ~$USER`
  export DOCKERDIR=`eval pwd`
  export DATADIR=$DOCKERDIR/data

  echo ""
  echo "=========================================="
  echo "  Basic Configuration"
  echo "=========================================="

  # Validate and set hostname
  while true; do
    response=$(prompt_with_default "Enter your Host Name (e.g. mybox)" "${EXISTING_HOSTNAME}")
    if [ -n "$response" ] && validate_hostname "$response"; then
      export HOSTNAME=$response
      break
    fi
    echo "ERROR: Invalid hostname. Please try again."
  done

  # Validate and set domain name
  while true; do
    response=$(prompt_with_default "Enter your Domain Name (e.g. example.com)" "${EXISTING_DOMAINNAME}")
    if [ -n "$response" ] && validate_domain "$response"; then
      export DOMAINNAME=$response
      break
    fi
    echo "ERROR: Invalid domain name. Please try again."
  done

  export PUBLIC_FQDN=$HOSTNAME.$DOMAINNAME
  echo "Your public FQDN will be: $PUBLIC_FQDN"

  echo ""
  echo "=========================================="
  echo "  Network Configuration"
  echo "=========================================="

  # Ask if user wants to customize network settings
  if confirm_action "Do you want to customize Docker network subnets?" "N"; then
    export LOCAL_IPS=$(prompt_with_default "Local IPs (comma separated CIDR)" "${EXISTING_LOCAL_IPS:-$LOCAL_IPS}")
    export CODE_TRAEFIK_SUBNET_IP=$(prompt_with_default "Code Traefik Subnet IP" "$CODE_TRAEFIK_SUBNET_IP")
    export DOCKER_DEFAULT_SUBNET=$(prompt_with_default "Docker Default Subnet" "$DOCKER_DEFAULT_SUBNET")
    export SOCKET_PROXY_SUBNET=$(prompt_with_default "Socket Proxy Subnet" "$SOCKET_PROXY_SUBNET")
    export SOCKET_PROXY_IP=$(prompt_with_default "Socket Proxy IP" "$SOCKET_PROXY_IP")
    export TRAEFIK_PROXY_SUBNET=$(prompt_with_default "Traefik Proxy Subnet" "$TRAEFIK_PROXY_SUBNET")
    export TRAEFIK_PROXY_IP=$(prompt_with_default "Traefik Proxy IP" "$TRAEFIK_PROXY_IP")
  else
    export LOCAL_IPS=${EXISTING_LOCAL_IPS:-$LOCAL_IPS}
    export CODE_TRAEFIK_SUBNET_IP=$CODE_TRAEFIK_SUBNET_IP
    export DOCKER_DEFAULT_SUBNET=$DOCKER_DEFAULT_SUBNET
    export SOCKET_PROXY_SUBNET=$SOCKET_PROXY_SUBNET
    export SOCKET_PROXY_IP=$SOCKET_PROXY_IP
    export TRAEFIK_PROXY_SUBNET=$TRAEFIK_PROXY_SUBNET
    export TRAEFIK_PROXY_IP=$TRAEFIK_PROXY_IP
    echo "Using default network configuration"
  fi

  response=`stat -c '%U' /proc`
  [ "$response" = "root" ] && export HOST_IS_VM=true || export HOST_IS_VM=false

  echo ""
  echo "=========================================="
  echo "  Firewall Configuration (UFW)"
  echo "=========================================="

  export UFW_ALLOW_FROM=$UFW_ALLOW_FROM

  response=$(prompt_with_default "Additional UFW ports to allow (e.g. 22,3306)" "${EXISTING_UFW_ALLOW_PORTS}")
  if [ "$response" != "${EXISTING_UFW_ALLOW_PORTS}" ] && [ -n "$response" ]; then
    export UFW_ALLOW_PORTS=$UFW_ALLOW_PORTS,$response
  else
    export UFW_ALLOW_PORTS=${response:-$UFW_ALLOW_PORTS}
  fi

  response=$(prompt_with_default "Networks/hosts to allow SSH (e.g. 1.1.1.1,2.2.2.0/24)" "${EXISTING_UFW_ALLOW_SSH}")
  if [ "$response" != "${EXISTING_UFW_ALLOW_SSH}" ] && [ -n "$response" ]; then
    export UFW_ALLOW_SSH=$UFW_ALLOW_SSH,$response
  else
    export UFW_ALLOW_SSH=${response:-$UFW_ALLOW_SSH}
  fi

  echo ""
  echo "=========================================="
  echo "  OAuth2 Configuration"
  echo "=========================================="
  echo "Configure Google OAuth2 Service as shown in:"
  echo "https://jacker.jacar.es/first-steps/prepare/#step-2-configure-google-oauth2-service"
  echo ""

  export OAUTH_COOKIE_LIFETIME=$OAUTH_COOKIE_LIFETIME

  response=$(prompt_with_default "OAuth Client ID" "${EXISTING_OAUTH_CLIENT_ID}")
  export OAUTH_CLIENT_ID=$response

  response=$(prompt_with_default "OAuth Client Secret" "${EXISTING_OAUTH_CLIENT_SECRET}")
  export OAUTH_CLIENT_SECRET=$response

  # Generate new OAuth secret or keep existing
  if [ -n "${OAUTH_SECRET}" ] && [ "$has_existing" = true ]; then
    export OAUTH_SECRET=$OAUTH_SECRET
  else
    export OAUTH_SECRET=`openssl rand -hex 16`
  fi

  # Validate OAuth whitelist emails
  while true; do
    response=$(prompt_with_default "OAuth whitelist emails (comma separated)" "${EXISTING_OAUTH_WHITELIST}")
    if [ -n "$response" ] && validate_email_list "$response"; then
      export OAUTH_WHITELIST=$response
      break
    fi
    echo "ERROR: Invalid email format. Please try again."
  done

  echo ""
  echo "=========================================="
  echo "  SSL Certificate Configuration"
  echo "=========================================="

  # Validate Let's Encrypt email
  while true; do
    response=$(prompt_with_default "Let's Encrypt Email" "${EXISTING_LETSENCRYPT_EMAIL}")
    if [ -n "$response" ] && validate_email "$response"; then
      export LETSENCRYPT_EMAIL=$response
      break
    fi
    echo "ERROR: Invalid email format. Please try again."
  done

  echo ""
  echo "=========================================="
  echo "  Database Configuration (PostgreSQL)"
  echo "=========================================="

  export POSTGRES_DB=${POSTGRES_DB:-crowdsec_db}
  export POSTGRES_USER=${POSTGRES_USER:-crowdsec}

  # Keep existing PostgreSQL password if it exists
  if [ -n "${POSTGRES_PASSWORD}" ] && [ "$has_existing" = true ]; then
    export POSTGRES_PASSWORD=$POSTGRES_PASSWORD
    echo "✓ Keeping existing PostgreSQL credentials"
  else
    export POSTGRES_PASSWORD=`openssl rand -hex 24`
    echo "✓ Generated new PostgreSQL password"
  fi

  echo "PostgreSQL Database: $POSTGRES_DB"
  echo "PostgreSQL User: $POSTGRES_USER"

  echo ""
  echo "=========================================="
  echo "  Security Configuration (CrowdSec)"
  echo "=========================================="
  echo "Generating secure API keys for CrowdSec..."

  export CROWDSEC_API_PORT=$CROWDSEC_API_PORT

  # Keep existing API keys if they exist, otherwise generate new ones
  if [ -n "${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}" ] && [ "$has_existing" = true ]; then
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$CROWDSEC_TRAEFIK_BOUNCER_API_KEY
    export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$CROWDSEC_IPTABLES_BOUNCER_API_KEY
    export CROWDSEC_API_LOCAL_PASSWORD=$CROWDSEC_API_LOCAL_PASSWORD
    echo "✓ Keeping existing CrowdSec credentials"
  else
    export CROWDSEC_TRAEFIK_BOUNCER_API_KEY=`openssl rand -hex 64`
    export CROWDSEC_IPTABLES_BOUNCER_API_KEY=`openssl rand -hex 64`
    export CROWDSEC_API_LOCAL_PASSWORD=`openssl rand -hex 36`
    echo "✓ Generated new CrowdSec credentials"
  fi

  echo ""
  echo "=========================================="
  echo "  Alerting Configuration (Optional)"
  echo "=========================================="
  echo "Configure alerting for Alertmanager (optional - skip if not needed)"
  echo ""

  if confirm_action "Do you want to configure email/telegram alerts?" "N"; then
    # SMTP Configuration
    echo ""
    echo "Email (SMTP) Configuration:"
    export SMTP_HOST=$(prompt_with_default "SMTP Host (e.g. smtp.gmail.com)" "${SMTP_HOST}")
    export SMTP_PORT=$(prompt_with_default "SMTP Port" "${SMTP_PORT:-587}")
    export SMTP_FROM=$(prompt_with_default "From Email Address" "${SMTP_FROM}")
    export SMTP_USERNAME=$(prompt_with_default "SMTP Username" "${SMTP_USERNAME}")
    export SMTP_PASSWORD=$(prompt_with_default "SMTP Password" "${SMTP_PASSWORD}")
    export ALERT_EMAIL_TO=$(prompt_with_default "Alert To Email" "${ALERT_EMAIL_TO}")

    echo ""
    if confirm_action "Do you want to configure Telegram alerts?" "N"; then
      echo "Telegram Configuration:"
      export TELEGRAM_BOT_TOKEN=$(prompt_with_default "Telegram Bot Token" "${TELEGRAM_BOT_TOKEN}")
      export TELEGRAM_CHAT_ID=$(prompt_with_default "Telegram Chat ID" "${TELEGRAM_CHAT_ID}")
    else
      export TELEGRAM_BOT_TOKEN=""
      export TELEGRAM_CHAT_ID=""
    fi
  else
    export SMTP_HOST=""
    export SMTP_PORT="587"
    export SMTP_FROM=""
    export SMTP_USERNAME=""
    export SMTP_PASSWORD=""
    export ALERT_EMAIL_TO=""
    export TELEGRAM_BOT_TOKEN=""
    export TELEGRAM_CHAT_ID=""
    echo "Skipping alerting configuration"
  fi

  echo ""
  echo "=========================================="
  echo "  Finalizing Configuration"
  echo "=========================================="

  # Create .env file
  envsubst < .env.template > .env
  echo "✓ .env file created"

  # Configure Traefik's logrotate
  envsubst < assets/templates/traefik.logrotate.template > assets/templates/traefik
  sudo mv assets/templates/traefik /etc/logrotate.d/
  sudo chown root:root /etc/logrotate.d/traefik
  sudo chmod 644 /etc/logrotate.d/traefik
  sudo logrotate /etc/logrotate.conf

  # Configure Crowdsec to use PostgreSQL database
  mkdir -p data/crowdsec/config/parsers/s02-enrich
  mkdir -p data/crowdsec/data
  envsubst < assets/templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
  echo "✓ CrowdSec directories created"

  # Configure Alertmanager
  mkdir -p data/alertmanager
  envsubst < assets/templates/alertmanager.yml.template > data/alertmanager/alertmanager.yml
  echo "✓ Alertmanager configuration created"

  # Configure Loki
  mkdir -p data/loki/data/rules
  cp assets/templates/loki-config.yml.template data/loki/loki-config.yml
  echo "✓ Loki configuration created (with rules directory)"

  # Configure Grafana
  mkdir -p data/grafana/data
  chmod 755 data/grafana/data
  echo "✓ Grafana data directory created"

  # Configure Traefik Forward OAuth Secret
  mkdir -p secrets
  envsubst < assets/templates/traefik_forward_oauth.template > secrets/traefik_forward_oauth

  # Configure systemd services
  envsubst < assets/templates/jacker-compose-reload.service.template > assets/templates/jacker-compose-reload.service
  envsubst < assets/templates/jacker-compose-reload.timer.template > assets/templates/jacker-compose-reload.timer
  envsubst < assets/templates/jacker-compose.service.template > assets/templates/jacker-compose.service

  # Change Permissions
  touch data/traefik/acme.json
  chmod 600 data/traefik/acme.json
  chmod +x assets/*.sh
}

execute_assets ()
{
  ./assets/01-tune_system.sh
  ./assets/02-install_docker-multiplatform.sh
  ./assets/03-setup_ufw.sh
  ./assets/04-install_assets.sh
  ./assets/05-install_firewall-bouncer.sh
}

first_round()
{
  detect_os
  curl_check
  gpg_check
  detect_apt_version

  echo ""
  echo "=========================================="
  echo "  Jacker Installation"
  echo "=========================================="
  echo ""

  local reinstall_mode=false
  if [ -f ".env" ]; then
    echo "Existing .env file detected."
    echo ""
    echo "Choose an option:"
    echo "  1) Reinstall (reconfigure, keep existing values as defaults)"
    echo "  2) Fresh install (backup .env and start from scratch)"
    echo "  3) Cancel"
    echo ""
    read -r -p "Select option [1-3]: " response
    case $response in
      1)
        echo "Starting reinstall mode..."
        echo "Your existing configuration will be used as defaults."
        reinstall_mode=true
        ;;
      2)
        timestamp=$(date +%Y%m%d-%H%M%S)
        echo "Backing up existing .env to .env.bak.$timestamp..."
        mv .env .env.bak.$timestamp
        echo "Starting fresh installation..."
        ;;
      *)
        echo "Installation cancelled."
        exit 0
        ;;
    esac
    echo ""
  fi

  create_env_files
  execute_assets

  echo ""
  echo "=========================================="
  echo "  Configuration Summary"
  echo "=========================================="
  echo "Hostname: $HOSTNAME"
  echo "Domain: $DOMAINNAME"
  echo "FQDN: $PUBLIC_FQDN"
  echo "Timezone: $TZ"
  echo "Let's Encrypt Email: $LETSENCRYPT_EMAIL"
  echo ""
  echo "Configuration saved to .env"
  echo ""

  # Execute second round after reboot
  SCRIPT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )/$(basename "$0")

  # Remove any existing jacker setup entries to prevent duplicates
  if [ -f ~/.bashrc ]; then
    grep -v "jacker.*setup\.sh" ~/.bashrc > ~/.bashrc.tmp 2>/dev/null || cp ~/.bashrc ~/.bashrc.tmp
    mv ~/.bashrc.tmp ~/.bashrc
  fi

  # Add the script path to bashrc for post-reboot continuation
  echo "$SCRIPT_PATH" >> ~/.bashrc
  touch .FIRST_ROUND

  echo "=========================================="
  echo "System needs to be restarted to apply changes."
  echo "You can safely say N and do it manually after saving other work."
  echo "Jacker Setup will continue when you login back."
  echo "=========================================="
  echo ""

  if confirm_action "Do you want to reboot your system NOW?" "N"; then
    sudo reboot
  else
    echo ""
    echo "Please reboot manually when ready:"
    echo "  sudo reboot"
    echo ""
    echo "After reboot, the setup will continue automatically."
    exit 0
  fi
}

second_round ()
{
  echo "Jacker Setup will continue now ..."

  source .env
  export CROWDSEC_IPTABLES_BOUNCER_API_KEY=$CROWDSEC_IPTABLES_BOUNCER_API_KEY
  envsubst < assets/templates/crowdsec-firewall-bouncer.yaml.template > assets/templates/crowdsec-firewall-bouncer.yaml
  sudo mkdir -p /etc/crowdsec/bouncers
  sudo mv assets/templates/crowdsec-firewall-bouncer.yaml /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local

  echo "Setting up Jacker Stack"

  # Check Redis memory overcommit setting
  current_overcommit=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "0")
  if [ "$current_overcommit" != "1" ]; then
    echo ""
    echo "⚠️  WARNING: Redis memory overcommit is not enabled"
    echo "    This may cause Redis save/replication failures under low memory"
    echo "    To fix, run on this host:"
    echo "      sudo sysctl vm.overcommit_memory=1"
    echo "      echo 'vm.overcommit_memory = 1' | sudo tee -a /etc/sysctl.conf"
    echo ""
    sleep 3
  fi

  docker compose up -d &> /dev/null

  echo "Waiting for PostgreSQL to be ready..."
  for i in {1..30}; do
    if docker compose exec -T postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB &> /dev/null; then
      echo "✓ PostgreSQL is ready"
      break
    fi
    if [ $i -eq 30 ]; then
      echo "❌ PostgreSQL failed to start in time"
      exit 1
    fi
    sleep 2
  done

  # Ensure crowdsec_db database exists (in case POSTGRES_DB was set to something else)
  echo "Ensuring crowdsec_db database exists..."
  docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -tc "SELECT 1 FROM pg_database WHERE datname='crowdsec_db'" | grep -q 1 || \
  docker compose exec -T postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "CREATE DATABASE crowdsec_db OWNER $POSTGRES_USER;" &> /dev/null

  if [ $? -eq 0 ]; then
    echo "✓ crowdsec_db database verified/created"
  else
    echo "⚠️  Note: crowdsec_db may already exist or there was a connection issue"
  fi

  echo "Waiting for services to stabilize..."
  sleep 10

  echo "Crowdsec: Registering traefik-bouncer"
  cscli bouncers add traefik-bouncer --key $CROWDSEC_TRAEFIK_BOUNCER_API_KEY &> /dev/null
  echo "Crowdsec: Registering iptables-bouncer"
  cscli bouncers add iptables-bouncer --key $CROWDSEC_IPTABLES_BOUNCER_API_KEY &> /dev/null
  echo "Crowdsec: Setting local api password"
  cscli machines add $HOSTNAME -p $CROWDSEC_API_LOCAL_PASSWORD --force &> /dev/null
  
  # cscli completion
  echo "Crowdsec: Installing cscli bash completion"
  cscli completion bash | sudo tee /etc/bash_completion.d/cscli &> /dev/null

  sudo cp assets/templates/crowdsec-custom-whitelists.yaml data/crowdsec/config/parsers/s02-enrich/custom-whitelists.yaml
  sudo cp assets/templates/crowdsec-acquis.yaml data/crowdsec/config/acquis.yaml
  sudo systemctl enable crowdsec-firewall-bouncer.service 
  sudo systemctl restart crowdsec-firewall-bouncer.service 
  docker compose down &> /dev/null
  docker image prune -a -f &> /dev/null

  SCRIPT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )/$(basename "$0")
  sed -i -e "\|$SCRIPT_PATH|d" ~/.bashrc
  rm .FIRST_ROUND

  sudo mv assets/templates/jacker-compose-reload.service assets/templates/jacker-compose-reload.timer assets/templates/jacker-compose.service /etc/systemd/system
  sudo systemctl daemon-reload
  sudo systemctl enable --now jacker-compose.service jacker-compose-reload.timer

  echo "done ..."
}

main ()
{
  if [ ! -f ".FIRST_ROUND" ]; then
    first_round
  else
    second_round
  fi
}

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
main
