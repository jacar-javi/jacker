#!/usr/bin/env bash
source .env

docker compose pull
docker compose up -d

echo Reboot your system!!
