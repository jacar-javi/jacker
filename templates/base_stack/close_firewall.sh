#!/usr/bin/env bash
cd "$(dirname "$0")"        # Change dir to this script's path
source ../../.env			# Load Jacker's Environment Variables
source .env					# Load Stack Environment Variables

# UFW close rules
# sudo ufw delete allow 
# sudo ufw delete allow from 

echo Finished $(basename "$0")