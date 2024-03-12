#!/usr/bin/env bash
source ../.env

# Server Tweaks for huge number of files
echo Tweaking System

echo vm.swappiness=10 | sudo tee -a /etc/sysctl.conf
echo vm.vfs_cache_pressure=50 | sudo tee -a /etc/sysctl.conf
echo fs.inotify.max_user_watches=262144 | sudo tee -a /etc/sysctl.conf

echo Updating system
sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y && sudo apt-get autoremove -y

echo Finished $(basename "$0")

echo Reboot system !
