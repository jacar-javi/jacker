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

# Find all occurrences of "open_firewall.sh" in stacks and execute them
if [ -d "../stacks" ]; then
    find "../stacks" -type f -name "open_firewall.sh" -exec chmod +x {} \; -exec {} \;
fi

sudo ufw --force enable
sudo ufw status verbose

echo "done ..".