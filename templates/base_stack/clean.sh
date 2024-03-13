#!/usr/bin/env bash
cd "$(dirname "$0")"        # Change dir to this script's path
source ../../.env			# Load Jacker's Environment Variables
source .env					# Load Stack Environment Variables


# Remove Data
#=================================
# sudo rm data/acme.json

echo Finished $(basename "$0")