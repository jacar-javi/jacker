#!/usr/bin/env bash
cd "$(dirname "$0")"        # Change dir to this script's path
source ../../.env			# Load Jacker's Environment Variables
source .env					# Load Stack Environment Variables



# Delete UFW rules needed by stack
#=================================

# ./close_firewall.sh


# Remove Assets
#=================================

# sudo rm /usr/local/sbin/


# Stop Stack
#=================================

#./dc.sh down

echo Finished $(basename "$0")
