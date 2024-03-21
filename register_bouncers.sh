#!/bin/bash
source .env

cscli bouncers add traefik-bouncer --key $CROWDSEC_TRAEFIK_BOUNCER_API_KEY
cscli bouncers add iptables-bouncer --key $CROWDSEC_IPTABLES_BOUNCER_API_KEY

