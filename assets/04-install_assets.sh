#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

sudo chmod +x cscli
sudo cp cscli /usr/local/sbin/
