#!/usr/bin/env bash
LAST_PWD=`pwd`
cd "$(dirname "$0")"

read -r -p "All existing data will be removed. Do you want to continue? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    docker compose down & > /dev/null
    docker image prune -a -f & > /dev/null
    sudo rm -rf data/crowdsec || true
    sudo rm -rf data/grafana/data/* || true
    sudo rm -rf data/mysql || true
    sudo rm -rf data/portainer || true
    sudo rm -rf data/traefik/acme.json || true
    sudo rm -rf secrets/traefik_forward_oauth || true
    sudo rm -rf logs || true
    sudo rm -rf .env || true
 ;;
  *)
    exit -1
  ;;
esac

cd $LAST_PWD
