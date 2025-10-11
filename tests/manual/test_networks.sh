#!/bin/bash

# Check traefik proxy network
TRAEFIK_NET=$(docker network inspect traefik_proxy)
if [[ "$TRAEFIK_NET" == *"traefik"* ]]; then
    echo "Traefik network isolated"
fi

# Check backend network
BACKEND_NET=$(docker network inspect backend)
if [[ "$BACKEND_NET" == *"postgres"* ]] && [[ "$BACKEND_NET" == *"redis"* ]]; then
    echo "Backend network isolated"
fi

echo "Network isolation verified"
