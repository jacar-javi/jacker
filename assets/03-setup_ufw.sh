#!/usr/bin/env bash
source ../.env

# Install ufw
sudo apt-get install ufw -y

# Configure ufw
sudo ufw --force disable
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

for i in ${UFW_ALLOW_FROM//,/ }
do
    sudo ufw allow from $i
done

sudo ufw allow http
sudo ufw allow https
sudo ufw --force enable

echo Finished $(basename "$0")
