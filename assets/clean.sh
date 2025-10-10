#!/usr/bin/env bash
#
# Script: clean.sh
# Description: Remove all Jacker data and configuration
# Usage: ./clean.sh
# WARNING: This will delete all data!
#

set -euo pipefail

# Change to Jacker root directory (parent of assets/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

read -r -p "All existing data will be removed. Do you want to continue? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    echo "Stopping containers..."
    docker compose down &> /dev/null || true

    echo "Pruning images..."
    docker image prune -a -f &> /dev/null || true

    echo "Removing data directories..."
    sudo rm -rf data/crowdsec || true
    sudo rm -rf data/grafana/data/* || true
    sudo rm -rf data/mysql || true
    sudo rm -rf data/portainer || true
    sudo rm -rf data/traefik/acme.json || true
    sudo rm -rf secrets/traefik_forward_oauth || true
    sudo rm -rf logs || true
    sudo rm -rf .env || true
    sudo rm -rf .FIRST_ROUND || true

    echo "Cleaning bashrc..."
    SCRIPT_PATH=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd )/setup.sh
    sed -i -e "\|$SCRIPT_PATH|d" ~/.bashrc || true

    echo "Clean completed successfully."
 ;;
  *)
    echo "Clean cancelled."
    exit 1
  ;;
esac

cd "$LAST_PWD"
