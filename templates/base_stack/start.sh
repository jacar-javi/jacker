#!/usr/bin/env bash
source ../../.env				# Load Jacker's Environment Variables
source .env					# Load Stack Environment Variables


# Set Permissions
#=================================
# sudo chmod 600 data/acme.json


# Add UFW rules needed by stack
#=================================

# sudo ufw allow $VAR


# Copy Assets
#=================================

# sudo cp assets/cscli /usr/local/sbin/



# Start Stack
#=================================

#./dc.sh up -d

echo Finished $(basename "$0")
