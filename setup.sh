#!/usr/bin/env bash
cd "$(dirname "$0")"

# Check for .env file
if [ ! -f ".env" ]; then
  echo "You need to create the .env file (cp .env.sample .env) and configure it"
  exit -1
fi

source .env

# Change Permissions
chmod 600 data/traefik/acme.json
chmod +x assets/*.sh

cd assets

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

read -r -p "Do you want to run 05-configure_logrotate.sh? [y/N] " response
case $response in
  [yY][eE][sS]|[yY])
    ./05-configure_logrotate.sh
  ;;
esac

# Configure Crowdsec to work with Mysql
export MYSQL_DATABASE=$MYSQL_DATABASE
export MYSQL_USER=$MYSQL_USER
export MYSQL_PASSWORD=$MYSQL_PASSWORD
mkdir -p ../data/crowdsec/config
envsubst < crowdsec/config.yaml.local.template > ../data/crowdsec/config/config.yaml.local

echo Reboot your system!!
