#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <name-of-new-stack>"
    exit -1;
fi

cp -r ../templates/base_stack ./$1

echo Succesfully created $1 from base_stack template
