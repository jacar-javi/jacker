#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

# Install Crowdsec Firewall Bouncer
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash

sudo apt-get update &> /dev/null
sudo apt install crowdsec-firewall-bouncer-iptables &> /dev/null
