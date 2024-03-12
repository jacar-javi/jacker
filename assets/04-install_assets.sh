#!/usr/bin/env bash
source ../.env

sudo chmod +x cscli
sudo cp cscli /usr/local/sbin/

echo Finished $(basename "$0")
