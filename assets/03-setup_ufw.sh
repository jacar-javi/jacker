#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

# Install ufw (if not installed)
sudo apt-get install ufw -y

# Reset and configure basic ufw rules
sudo ufw --force disable
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

for i in ${UFW_ALLOW_FROM//,/ }
do
    sudo ufw allow from $i
done

for i in ${UFW_ALLOW_PORTS//,/ }
do
    sudo ufw allow $i
done

for i in ${UFW_ALLOW_SSH//,/ }
do
    sudo ufw allow from $i to any port 22
done

# Find all occurrences of "open_firewall.sh" in stacks and execute them
if [ -d "../stacks" ]; then
    find "../stacks" -type f -name "open_firewall.sh" -exec chmod +x {} \; -exec {} \;
fi

sudo ufw --force enable

echo Finished $(basename "$0")
