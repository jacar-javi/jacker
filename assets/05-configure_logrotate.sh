#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

export DOCKERDIR=$DOCKERDIR

envsubst < logrotate/traefik.template > logrotate/traefik
sudo mv logrotate/traefik /etc/logrotate.d/
sudo chown root.root /etc/logrotate.d/traefik
sudo chmod 644 /etc/logrotate.d/traefik

echo Finished $(basename "$0")