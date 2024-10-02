#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

echo "Setting up UFW"

# Install ufw (if not installed)
sudo apt-get install ufw -y &> /dev/null

# Reset and configure basic ufw rules
sudo ufw --force disable &> /dev/null
sudo ufw --force reset &> /dev/null
sudo ufw default deny incoming &> /dev/null
sudo ufw default allow outgoing &> /dev/null

# Install ufw-docker https://github.com/chaifeng/ufw-docker
# sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker &> /dev/null
# sudo chmod +x /usr/local/bin/ufw-docker

for i in ${UFW_ALLOW_FROM//,/ }
do
    sudo ufw allow from $i &> /dev/null
done

for i in ${UFW_ALLOW_PORTS//,/ }
do
    sudo ufw allow $i &> /dev/null
done

for i in ${UFW_ALLOW_SSH//,/ }
do
    sudo ufw allow from $i to any port 22 &> /dev/null
done

sudo ufw --force enable
sudo ufw status verbose

echo "done ..".
