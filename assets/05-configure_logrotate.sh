#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

sudo envsubst < $DOCKER_DIR/assets/logrotate/traefik > /etc/logrotate.d/traefik

echo Finished $(basename "$0")