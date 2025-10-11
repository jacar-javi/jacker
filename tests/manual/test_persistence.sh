#!/bin/bash
source "${LIB_DIR}/common.sh"

# Load initial config
load_env ".env"

# Save initial values
INITIAL_HOSTNAME="$HOSTNAME"
INITIAL_DOMAIN="$DOMAINNAME"
INITIAL_PASSWORD="$POSTGRES_PASSWORD"

# Modify values
export HOSTNAME="modified-host"
export DOMAINNAME="modified.local"
export POSTGRES_PASSWORD="modified_password"

# Save modified values
set_env_var "HOSTNAME" "$HOSTNAME" ".env"
set_env_var "DOMAINNAME" "$DOMAINNAME" ".env"
set_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD" ".env"

# Reload and verify
unset HOSTNAME DOMAINNAME POSTGRES_PASSWORD
load_env ".env"

if [[ "$HOSTNAME" == "modified-host" ]] && \
   [[ "$DOMAINNAME" == "modified.local" ]] && \
   [[ "$POSTGRES_PASSWORD" == "modified_password" ]]; then
    echo "Persistence verified"
else
    echo "Persistence failed"
    exit 1
fi
