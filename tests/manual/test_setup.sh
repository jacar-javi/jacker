#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/services.sh"

# Simulate quick setup
export HOSTNAME="test-host"
export DOMAINNAME="test.local"
export PUBLIC_FQDN="${HOSTNAME}.${DOMAINNAME}"
export POSTGRES_PASSWORD="test_password"
export CROWDSEC_TRAEFIK_BOUNCER_API_KEY="test_key"

# Create .env file
cat > .env <<ENV
HOSTNAME=${HOSTNAME}
DOMAINNAME=${DOMAINNAME}
PUBLIC_FQDN=${PUBLIC_FQDN}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
CROWDSEC_TRAEFIK_BOUNCER_API_KEY=${CROWDSEC_TRAEFIK_BOUNCER_API_KEY}
ENV

# Create required directories
mkdir -p data/traefik
mkdir -p data/crowdsec/config
mkdir -p secrets

# Create acme.json
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json

echo "Setup complete"
