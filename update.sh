#!/usr/bin/env bash
cd "$(dirname "$0")"
[ -f .env ] || echo "You need to create the .env file (cp .env.sample .env) and configure it"; exit
source .env

docker compose pull         # Get latest version of all images
docker compose up -d        # Recreate containers with new images

# TODO: Execute update script in all stacks

docker image prune -a -f    # Remove al unused images

echo Reboot your system!!
