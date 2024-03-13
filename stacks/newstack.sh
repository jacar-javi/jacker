#!/usr/bin/env bash
cd "$(dirname "$0")"
source .env

for var in "$@"
        do
                argstopass="$argstopass $var"
        done

cp -r ../templates/base_stack ./$argstopass

echo Finished $(basename "$0")
