#!/bin/bash
source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/services.sh"

# Check if service is down
if ! is_container_running "traefik"; then
    warning "Service down, attempting recovery..."
    docker compose up -d traefik
fi

# Verify recovery
if is_container_running "traefik"; then
    success "Service recovered"
else
    error "Recovery failed"
    exit 1
fi
