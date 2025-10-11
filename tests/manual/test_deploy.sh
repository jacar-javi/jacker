#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/system.sh"
source "${LIB_DIR}/services.sh"

# Create configuration
info "Creating configuration..."
ensure_dir "data/traefik"
ensure_dir "data/postgres"
ensure_dir "data/redis"
ensure_dir "data/crowdsec/config"
ensure_dir "secrets"

# Setup services
setup_traefik
setup_postgresql
setup_redis
setup_crowdsec

# Create networks
create_networks

# Start services
start_services

# Check health
check_services_health

echo "Deployment complete"
