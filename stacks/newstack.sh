#!/usr/bin/env bash
cd "$(dirname "$0")"
source ../.env

if [ "$#" -neq 1 ]; then
    echo "Usage: $0 <name-of-new-stack>"
    exit -1;
fi

cp -r ../templates/base_stack ./$1

echo $(basename "$0") succesfully created $1 from Jacker's base_stack template
