#!/usr/bin/env bash
#
# Script: setup-authentik.sh
# Description: Setup Authentik identity provider for Jacker
# Usage: ./setup-authentik.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Authentik Setup for Jacker ===${NC}\n"

# Check if we're in the jacker directory
if [ ! -f "docker-compose.yml" ] || [ ! -f ".env" ]; then
    echo -e "${RED}ERROR: This script must be run from the jacker root directory${NC}"
    echo "Make sure docker-compose.yml and .env exist in the current directory"
    exit 1
fi

# Source .env file
if [ -f .env ]; then
    set -a
# shellcheck source=/dev/null
    source .env
    set +a
else
    echo -e "${RED}ERROR: .env file not found${NC}"
    exit 1
fi

echo -e "${YELLOW}This script will configure Authentik as your authentication provider.${NC}\n"
echo "Authentik provides:"
echo "  • Self-hosted identity provider (no external dependencies)"
echo "  • Single Sign-On (SSO) with SAML, OAuth2, OpenID Connect"
echo "  • LDAP integration"
echo "  • Multi-factor authentication (MFA)"
echo "  • User management and groups"
echo "  • Social login (Google, GitHub, etc.)"
echo ""

read -r -p "Do you want to continue? [y/N] " response
case $response in
    [yY][eE][sS]|[yY])
        echo ""
        ;;
    *)
        echo "Setup cancelled."
        exit 0
        ;;
esac

# Check if AUTH_PROVIDER is already set to authentik
if [ "${AUTH_PROVIDER:-}" = "authentik" ]; then
    echo -e "${YELLOW}AUTH_PROVIDER is already set to 'authentik'${NC}"
else
    echo -e "${BLUE}Setting AUTH_PROVIDER to 'authentik'...${NC}"
    if grep -q "^AUTH_PROVIDER=" .env; then
        sed -i 's/^AUTH_PROVIDER=.*/AUTH_PROVIDER=authentik/' .env
    else
        echo "AUTH_PROVIDER=authentik" >> .env
    fi
    echo -e "${GREEN}✓ AUTH_PROVIDER updated${NC}"
fi

# Generate Authentik secret key if not set
if [ -z "${AUTHENTIK_SECRET_KEY:-}" ]; then
    echo -e "${BLUE}Generating Authentik secret key...${NC}"
    AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')

    if grep -q "^AUTHENTIK_SECRET_KEY=" .env; then
        sed -i "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY|" .env
    else
        echo "AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY" >> .env
    fi
    echo -e "${GREEN}✓ Authentik secret key generated${NC}"
else
    echo -e "${GREEN}✓ Authentik secret key already configured${NC}"
fi

# Generate Authentik PostgreSQL password if not set
if [ -z "${AUTHENTIK_POSTGRES_PASSWORD:-}" ]; then
    echo -e "${BLUE}Generating Authentik PostgreSQL password...${NC}"
    AUTHENTIK_POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

    if grep -q "^AUTHENTIK_POSTGRES_PASSWORD=" .env; then
        sed -i "s|^AUTHENTIK_POSTGRES_PASSWORD=.*|AUTHENTIK_POSTGRES_PASSWORD=$AUTHENTIK_POSTGRES_PASSWORD|" .env
    else
        echo "AUTHENTIK_POSTGRES_PASSWORD=$AUTHENTIK_POSTGRES_PASSWORD" >> .env
    fi
    echo -e "${GREEN}✓ Authentik PostgreSQL password generated${NC}"
else
    echo -e "${GREEN}✓ Authentik PostgreSQL password already configured${NC}"
fi

# Create Authentik data directories
echo -e "${BLUE}Creating Authentik data directories...${NC}"
mkdir -p "${DATADIR}/authentik/"{media,custom-templates,certs,postgres,blueprints}
echo -e "${GREEN}✓ Authentik directories created${NC}"

# Check if authentik.yml is included in docker-compose.yml
if ! grep -q "compose/authentik.yml" docker-compose.yml; then
    echo -e "${BLUE}Adding Authentik to docker-compose.yml...${NC}"

    # Find the line with "compose/oauth.yml" and add authentik.yml after it
    if grep -q "compose/oauth.yml" docker-compose.yml; then
        # Add after oauth.yml (commented out when using authentik)
        sed -i '/compose\/oauth.yml/a\  - compose/authentik.yml' docker-compose.yml
        echo -e "${GREEN}✓ Authentik added to docker-compose.yml${NC}"
    else
        echo -e "${YELLOW}⚠ Could not find oauth.yml in docker-compose.yml${NC}"
        echo -e "${YELLOW}Please manually add '  - compose/authentik.yml' to the include section${NC}"
    fi
else
    echo -e "${GREEN}✓ Authentik already in docker-compose.yml${NC}"
fi

# Comment out OAuth in docker-compose.yml when using Authentik
echo -e "${BLUE}Updating docker-compose.yml to use Authentik...${NC}"
if grep -q "^  - compose/oauth.yml" docker-compose.yml; then
    sed -i 's|^  - compose/oauth.yml|  # - compose/oauth.yml  # Using Authentik instead|' docker-compose.yml
    echo -e "${GREEN}✓ OAuth disabled (using Authentik instead)${NC}"
fi

echo ""
echo -e "${GREEN}=== Authentik Configuration Complete ===${NC}\n"
echo -e "${BLUE}Next Steps:${NC}\n"
echo "1. Start Authentik services:"
echo "   ${YELLOW}docker compose up -d authentik-postgres authentik-server authentik-worker${NC}"
echo ""
echo "2. Wait for services to be healthy (30-60 seconds):"
echo "   ${YELLOW}docker compose ps${NC}"
echo ""
echo "3. Access Authentik at:"
echo "   ${YELLOW}https://auth.${DOMAINNAME}${NC}"
echo ""
echo "4. Complete initial setup:"
echo "   • Create an admin account"
echo "   • Set up your email (optional)"
echo "   • Configure authentication flows"
echo ""
echo "5. Create an Application and Provider:"
echo "   a) Go to Applications > Providers > Create"
echo "   b) Choose 'Proxy Provider'"
echo "   c) Set Authorization flow to 'default-provider-authorization-implicit-consent'"
echo "   d) Set External host to your service URL (e.g., https://portainer.${DOMAINNAME})"
echo "   e) Create the provider"
echo "   f) Go to Applications > Applications > Create"
echo "   g) Set Name and Slug"
echo "   h) Select the provider you just created"
echo "   i) Create the application"
echo ""
echo "6. Update your services to use Authentik authentication:"
echo "   • Change middleware from 'chain-oauth@file' to 'chain-authentik@file'"
echo "   • Example: traefik.http.routers.SERVICE-rtr.middlewares=chain-authentik@file"
echo ""
echo "7. Restart Traefik to apply changes:"
echo "   ${YELLOW}docker compose restart traefik${NC}"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  • Authentik Docs: https://docs.goauthentik.io"
echo "  • Traefik Integration: https://docs.goauthentik.io/docs/providers/proxy/traefik"
echo ""
echo -e "${YELLOW}Note: Keep Google OAuth configuration in .env for easy rollback if needed${NC}"
echo ""
