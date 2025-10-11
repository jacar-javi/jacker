#!/bin/bash

if is_container_running "traefik"; then
    echo "traefik: healthy"
fi

if is_container_running "postgres"; then
    echo "postgres: healthy"
fi

echo "Health check complete"
