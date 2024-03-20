#!/usr/bin/env bash
cd "$(dirname "$0")"        # Change dir to this script's path
source ../../.env			# Load Jacker's Environment Variables
source .env					# Load Stack Environment Variables


for var in "$@"
        do
                argstopass="$argstopass $var"
        done

docker compose --env-file ../../.env --env-file .env $argstopass
