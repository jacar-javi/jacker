#!/usr/bin/env bash
#
# Script: rotate-secrets.sh
# Description: Rotate security-sensitive secrets in Jacker
# Usage: ./rotate-secrets.sh [--all|--oauth|--crowdsec|--mysql]
# Options:
#   --all       Rotate all secrets
#   --oauth     Rotate OAuth secret only
#   --crowdsec  Rotate CrowdSec API keys only
#   --mysql     Rotate MySQL passwords only
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}ERROR: .env file not found${NC}"
    exit 1
fi

# Determine what to rotate
ROTATE_MODE="${1:---all}"

echo -e "${BLUE}=== Jacker Secrets Rotation Utility ===${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will rotate security-sensitive secrets!${NC}"
echo -e "${YELLOW}Services will be restarted after rotation.${NC}"
echo ""

# Backup current .env
BACKUP_ENV=".env.pre-rotation-$(date +%Y%m%d-%H%M%S)"
echo "Backing up current .env to $BACKUP_ENV..."
cp .env "$BACKUP_ENV"

# shellcheck source=/dev/null
source .env

# Generate new secrets
generate_oauth_secret() {
    echo "Generating new OAuth secret..."
    NEW_OAUTH_SECRET=$(openssl rand -hex 16)

    # Update .env
    sed -i "s/OAUTH_SECRET=.*/OAUTH_SECRET=$NEW_OAUTH_SECRET/" .env

    # Update secrets file
    if [ -f secrets/traefik_forward_oauth ]; then
        sed -i "s/secret=.*/secret=$NEW_OAUTH_SECRET/" secrets/traefik_forward_oauth
    fi

    echo -e "${GREEN}✓ OAuth secret rotated${NC}"
}

generate_crowdsec_keys() {
    echo "Generating new CrowdSec API keys..."
    NEW_TRAEFIK_BOUNCER_KEY=$(openssl rand -hex 64)
    NEW_IPTABLES_BOUNCER_KEY=$(openssl rand -hex 64)
    NEW_CROWDSEC_PASSWORD=$(openssl rand -hex 36)

    # Update .env
    sed -i "s/CROWDSEC_TRAEFIK_BOUNCER_API_KEY=.*/CROWDSEC_TRAEFIK_BOUNCER_API_KEY=$NEW_TRAEFIK_BOUNCER_KEY/" .env
    sed -i "s/CROWDSEC_IPTABLES_BOUNCER_API_KEY=.*/CROWDSEC_IPTABLES_BOUNCER_API_KEY=$NEW_IPTABLES_BOUNCER_KEY/" .env
    sed -i "s/CROWDSEC_API_LOCAL_PASSWORD=.*/CROWDSEC_API_LOCAL_PASSWORD=$NEW_CROWDSEC_PASSWORD/" .env

    echo -e "${GREEN}✓ CrowdSec API keys rotated${NC}"
}

generate_mysql_passwords() {
    echo "Generating new MySQL passwords..."
    NEW_MYSQL_ROOT_PASSWORD=$(openssl rand -hex 24)
    NEW_MYSQL_PASSWORD=$(openssl rand -hex 24)

    # Update .env
    sed -i "s/MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=$NEW_MYSQL_ROOT_PASSWORD/" .env
    sed -i "s/MYSQL_PASSWORD=.*/MYSQL_PASSWORD=$NEW_MYSQL_PASSWORD/" .env

    echo -e "${GREEN}✓ MySQL passwords rotated${NC}"
}

# Perform rotation based on mode
case $ROTATE_MODE in
    --all)
        echo "Rotating all secrets..."
        echo ""
        generate_oauth_secret
        generate_crowdsec_keys
        generate_mysql_passwords
        ;;
    --oauth)
        echo "Rotating OAuth secret only..."
        echo ""
        generate_oauth_secret
        ;;
    --crowdsec)
        echo "Rotating CrowdSec API keys only..."
        echo ""
        generate_crowdsec_keys
        ;;
    --mysql)
        echo "Rotating MySQL passwords only..."
        echo ""
        generate_mysql_passwords
        ;;
    *)
        echo -e "${RED}ERROR: Invalid option: $ROTATE_MODE${NC}"
        echo ""
        echo "Usage: $0 [--all|--oauth|--crowdsec|--mysql]"
        exit 1
        ;;
esac

echo ""
echo -e "${BLUE}=== Applying Changes ===${NC}"
echo ""

# Reload environment
# shellcheck source=/dev/null
source .env

# Update OAuth secrets file if OAuth was rotated
if [ "$ROTATE_MODE" = "--all" ] || [ "$ROTATE_MODE" = "--oauth" ]; then
    echo "Updating OAuth configuration..."
    envsubst < assets/templates/traefik_forward_oauth.template > secrets/traefik_forward_oauth
    echo -e "${GREEN}✓ OAuth configuration updated${NC}"
fi

# Update CrowdSec configuration if CrowdSec keys were rotated
if [ "$ROTATE_MODE" = "--all" ] || [ "$ROTATE_MODE" = "--crowdsec" ]; then
    echo "Updating CrowdSec configuration..."

    # Update iptables bouncer config
    envsubst < assets/templates/crowdsec-firewall-bouncer.yaml.template > assets/templates/crowdsec-firewall-bouncer.yaml
    sudo mkdir -p /etc/crowdsec/bouncers
    sudo mv assets/templates/crowdsec-firewall-bouncer.yaml /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local

    echo -e "${GREEN}✓ CrowdSec configuration updated${NC}"
fi

echo ""
echo -e "${BLUE}=== Restarting Services ===${NC}"
echo ""

# Restart affected services
if [ "$ROTATE_MODE" = "--all" ]; then
    echo "Stopping all services..."
    docker compose down

    echo "Starting all services..."
    docker compose up -d

    # Re-register bouncers
    echo "Waiting for CrowdSec to start..."
    sleep 10

    echo "Re-registering CrowdSec bouncers..."
    cscli bouncers delete traefik-bouncer &>/dev/null || true
    cscli bouncers delete iptables-bouncer &>/dev/null || true
    cscli bouncers add traefik-bouncer --key "$CROWDSEC_TRAEFIK_BOUNCER_API_KEY" &>/dev/null
    cscli bouncers add iptables-bouncer --key "$CROWDSEC_IPTABLES_BOUNCER_API_KEY" &>/dev/null
    cscli machines add "$HOSTNAME" -p "$CROWDSEC_API_LOCAL_PASSWORD" --force &>/dev/null

    sudo systemctl restart crowdsec-firewall-bouncer.service

elif [ "$ROTATE_MODE" = "--oauth" ]; then
    echo "Restarting OAuth service..."
    docker compose restart oauth

elif [ "$ROTATE_MODE" = "--crowdsec" ]; then
    echo "Restarting CrowdSec services..."
    docker compose restart crowdsec traefik-bouncer

    echo "Waiting for CrowdSec to start..."
    sleep 10

    echo "Re-registering CrowdSec bouncers..."
    cscli bouncers delete traefik-bouncer &>/dev/null || true
    cscli bouncers delete iptables-bouncer &>/dev/null || true
    cscli bouncers add traefik-bouncer --key "$CROWDSEC_TRAEFIK_BOUNCER_API_KEY" &>/dev/null
    cscli bouncers add iptables-bouncer --key "$CROWDSEC_IPTABLES_BOUNCER_API_KEY" &>/dev/null
    cscli machines add "$HOSTNAME" -p "$CROWDSEC_API_LOCAL_PASSWORD" --force &>/dev/null

    sudo systemctl restart crowdsec-firewall-bouncer.service

elif [ "$ROTATE_MODE" = "--mysql" ]; then
    echo -e "${YELLOW}WARNING: MySQL password rotation requires manual intervention!${NC}"
    echo ""
    echo "To complete MySQL password rotation:"
    echo "1. Connect to MariaDB container:"
    echo "   docker compose exec mariadb mysql -u root -p"
    echo "2. Change root password:"
    echo "   ALTER USER 'root'@'%' IDENTIFIED BY 'new_password';"
    echo "   ALTER USER 'root'@'localhost' IDENTIFIED BY 'new_password';"
    echo "3. Change application user password:"
    echo "   ALTER USER '$MYSQL_USER'@'%' IDENTIFIED BY 'new_password';"
    echo "4. Restart services:"
    echo "   docker compose restart"
fi

echo ""
echo -e "${GREEN}=== Secrets Rotation Complete ===${NC}"
echo ""
echo "Rotated secrets have been saved to .env"
echo "Previous configuration backed up to: $BACKUP_ENV"
echo ""
echo "Next steps:"
echo "1. Verify services are running: docker compose ps"
echo "2. Check health: ./health-check.sh"
echo "3. Test authentication and access"
echo ""

if [ "$ROTATE_MODE" = "--mysql" ]; then
    echo -e "${YELLOW}Don't forget to complete MySQL password rotation manually!${NC}"
    echo ""
fi

echo "To revert to previous secrets (if needed):"
echo "  cp $BACKUP_ENV .env"
echo "  docker compose down && docker compose up -d"
echo ""
