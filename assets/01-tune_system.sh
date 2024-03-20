#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

echo "Tweaking System to handle huge number of files"

if ! grep -q "fs.inotify.max_user_watches=" /etc/sysctl.conf; then
    echo fs.inotify.max_user_watches=262144 | sudo tee -a /etc/sysctl.conf
fi
if ! grep -q "vm.vfs_cache_pressure=" /etc/sysctl.conf; then
    echo vm.vfs_cache_pressure=50 | sudo tee -a /etc/sysctl.conf
fi
if ! grep -q "vm.swappiness=" /etc/sysctl.conf; then
    echo vm.swappiness=10 | sudo tee -a /etc/sysctl.conf
fi


echo "Updating system"

sudo apt-get update &> /dev/null
sudo apt-get upgrade -y &> /dev/null
sudo apt-get dist-upgrade -y &> /dev/null
sudo apt-get autoremove -y &> /dev/null

echo "done .."
