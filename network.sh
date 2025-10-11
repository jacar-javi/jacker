#!/bin/bash
source "${LIB_DIR}/common.sh"

echo "LOCAL_IPS: ${LOCAL_IPS}"
echo "DOCKER_DEFAULT_SUBNET: ${DOCKER_DEFAULT_SUBNET}"
echo "TRAEFIK_PROXY_SUBNET: ${TRAEFIK_PROXY_SUBNET}"

# Validate subnets
if [[ "$DOCKER_DEFAULT_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo "Docker subnet valid"
fi

if [[ "$TRAEFIK_PROXY_SUBNET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    echo "Traefik subnet valid"
fi
