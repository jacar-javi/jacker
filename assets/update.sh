#!/usr/bin/env bash
#
# Script: update.sh
# Description: Update all Jacker Docker images and containers
# Usage: ./update.sh
# Requirements: .env file must exist
#

set -euo pipefail

cd "$(dirname "$0")"

# Check for .env file
if [ ! -f .env ]; then
    echo "ERROR: You need to create the .env file first"
    echo "Run: cp .env.sample .env && vim .env"
    exit 1
fi

source .env

echo "Pulling latest images..."
docker compose pull         # Get latest version of all images

echo "Recreating containers with new images..."
docker compose up -d        # Recreate containers with new images

# TODO: Execute update script in all stacks

echo "Cleaning up unused images..."
docker image prune -a -f    # Remove all unused images

echo ""
echo "Update completed successfully!"
echo "IMPORTANT: Reboot your system to ensure all changes take effect."
echo ""
read -r -p "Do you want to reboot now? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    sudo reboot
  ;;
  *)
    echo "Remember to reboot later."
  ;;
esac
