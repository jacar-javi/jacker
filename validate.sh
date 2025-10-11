#!/bin/bash
source "${LIB_DIR}/common.sh"

REQUIRED_VARS=("HOSTNAME" "DOMAINNAME" "POSTGRES_PASSWORD")
MISSING=()

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${var}=" .env; then
        MISSING+=("$var")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "Missing: ${MISSING[*]}"
    exit 1
else
    echo "All variables present"
fi
