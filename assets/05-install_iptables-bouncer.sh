#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

# Install Crowdsec Iptables Bouncer
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash

sudo apt-get update &> /dev/null
sudo apt-get install crowdsec-firewall-bouncer-iptables -y &> /dev/null
