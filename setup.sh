#!/usr/bin/env bash
cd "$(dirname "$0")"
[ -f .env ] || echo "You need to create the .env file (cp env.orig .env) and configure it"; exit
source .env

chmod 600 data/traefik/acme.json
cd assets
chmod +x *.sh

read -r -p "Do you want to run 01-tune_system.sh? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    ./01-tune_system.sh
  ;;
esac

read -r -p "Do you want to run 02-install_docker.sh? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    ./02-install_docker.sh
  ;;
esac

read -r -p "Do you want to run 03-setup_ufw.sh? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    ./03-setup_ufw.sh
  ;;
esac

read -r -p "Do you want to run 04-install_assets.sh? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    ./04-install_assets.sh
  ;;
esac

echo Reboot your system!!
