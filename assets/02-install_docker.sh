#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

echo "Installing Docker"

# Add Docker's official GPG key:
sudo apt-get update &> /dev/null
sudo apt-get install ca-certificates curl -y &> /dev/null
sudo install -m 0755 -d /etc/apt/keyrings &> /dev/null
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &> /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc &> /dev/null

# Add the repository to Apt sources:
sudo truncate -s 0 /etc/apt/sources.list.d/docker.list
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update &> /dev/null
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y &> /dev/null

# Add current user to docker group
sudo usermod -aG docker $USER

# Configure docker to run on boot
sudo systemctl enable docker.service &> /dev/null
sudo systemctl enable containerd.service &> /dev/null

echo "done ..."
