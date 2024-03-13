#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../../.env
source ../.env

# Remove Data
#=================================
# sudo rm data/acme.json

echo Finished $(basename "$0")