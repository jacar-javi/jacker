#!/usr/bin/env bash
#
# Bash completion script for Jacker CLI
# Updated for Jacker v3.0.0 - 21 services, comprehensive command set
#
# This file is automatically installed by 'jacker init'
# Manual installation:
#   source /path/to/jacker/assets/jacker-completion.bash
#

_jacker_services() {
    # Get list of all 21 Jacker services from docker-compose
    if [[ -f docker-compose.yml ]]; then
        docker compose config --services 2>/dev/null
    else
        # Fallback: hardcoded list of all services
        echo "traefik socket-proxy postgres redis oauth crowdsec grafana prometheus loki promtail alertmanager jaeger homepage portainer vscode authentik node-exporter cadvisor postgres-exporter redis-exporter redis-commander pushgateway"
    fi
}

_jacker_completion() {
    local cur prev words cword
    _init_completion || return

    # All main commands (updated for current project)
    local commands="init start stop restart status logs shell health fix backup restore update clean wipe-data config secrets security alerts info version help"

    # Subcommands for each command
    local config_subcommands="show set validate oauth domain ssl authentik tracing"
    local secrets_subcommands="list rotate generate verify"
    local security_subcommands="status crowdsec firewall scan"
    local alerts_subcommands="test telegram email slack config"
    local fix_components="all loki traefik crowdsec postgres permissions network"

    # Handle command completion (jacker <TAB>)
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
        return 0
    fi

    # Get the main command
    local cmd="${words[1]}"

    # Handle subcommand and option completion based on the main command
    case "${cmd}" in
        # Commands that accept service names
        start|stop|restart|shell|logs)
            if [[ "${cur}" == -* ]]; then
                case "${cmd}" in
                    start)
                        COMPREPLY=( $(compgen -W "--attach --help -h" -- "${cur}") )
                        ;;
                    stop)
                        COMPREPLY=( $(compgen -W "--volumes -v --help -h" -- "${cur}") )
                        ;;
                    restart)
                        COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
                        ;;
                    logs)
                        COMPREPLY=( $(compgen -W "-f --follow --tail --since --help -h" -- "${cur}") )
                        ;;
                    shell)
                        COMPREPLY=( $(compgen -W "--bash --user --help -h" -- "${cur}") )
                        ;;
                esac
            else
                # Complete with service names
                local services=$(_jacker_services)
                COMPREPLY=( $(compgen -W "${services}" -- "${cur}") )
            fi
            ;;

        # Commands with simple options
        init)
            COMPREPLY=( $(compgen -W "--auto --force --help -h" -- "${cur}") )
            ;;

        status|ps)
            COMPREPLY=( $(compgen -W "--watch -w --json --help -h" -- "${cur}") )
            ;;

        health|check)
            COMPREPLY=( $(compgen -W "--verbose -v --json --help -h" -- "${cur}") )
            ;;

        # Fix command - offer components
        fix|repair)
            if [[ $cword -eq 2 ]] && [[ "${cur}" != -* ]]; then
                COMPREPLY=( $(compgen -W "${fix_components}" -- "${cur}") )
            else
                COMPREPLY=( $(compgen -W "--force -f --help -h" -- "${cur}") )
            fi
            ;;

        backup|bak)
            COMPREPLY=( $(compgen -W "--location -l --with-volumes --help -h" -- "${cur}") )
            ;;

        restore)
            if [[ "${cur}" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force -f --help -h" -- "${cur}") )
            else
                # Complete with .tar.gz backup files
                COMPREPLY=( $(compgen -f -X '!*.tar.gz' -- "${cur}") )
            fi
            ;;

        update|upgrade)
            COMPREPLY=( $(compgen -W "--check-only -c --skip-pull --help -h" -- "${cur}") )
            ;;

        clean|cleanup)
            COMPREPLY=( $(compgen -W "--force -f --deep --help -h" -- "${cur}") )
            ;;

        wipe-data)
            COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
            ;;

        # Config command with subcommands
        config|configure|cfg)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${config_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    oauth)
                        COMPREPLY=( $(compgen -W "--disable --help -h" -- "${cur}") )
                        ;;
                    ssl)
                        COMPREPLY=( $(compgen -W "--staging --force --help -h" -- "${cur}") )
                        ;;
                    tracing)
                        COMPREPLY=( $(compgen -W "status enable disable jaeger opentelemetry --help -h" -- "${cur}") )
                        ;;
                    set)
                        # Common environment variables
                        if [[ $cword -eq 3 ]]; then
                            COMPREPLY=( $(compgen -W "TZ DOMAINNAME PUBLIC_FQDN PUID PGID" -- "${cur}") )
                        fi
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        # Secrets command with subcommands
        secrets|secret)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${secrets_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    rotate)
                        # Offer all secret names
                        COMPREPLY=( $(compgen -W "all postgres redis oauth crowdsec authentik grafana --help -h" -- "${cur}") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        # Security command with subcommands
        security|sec)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${security_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    crowdsec)
                        COMPREPLY=( $(compgen -W "status bouncer decisions metrics collections --help -h" -- "${cur}") )
                        ;;
                    firewall)
                        COMPREPLY=( $(compgen -W "status update reset rules --help -h" -- "${cur}") )
                        ;;
                    scan)
                        COMPREPLY=( $(compgen -W "--full --quick --help -h" -- "${cur}") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        # Alerts command with subcommands (new)
        alerts|alert)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${alerts_subcommands} help" -- "${cur}") )
            else
                COMPREPLY=( $(compgen -W "--help -h" -- "${cur}") )
            fi
            ;;

        # Info command
        info|information)
            COMPREPLY=( $(compgen -W "--json --help -h" -- "${cur}") )
            ;;

        # Version and help
        version|help)
            COMPREPLY=()
            ;;

        *)
            # Global options available for all commands
            COMPREPLY=( $(compgen -W "-v --verbose -q --quiet --dry-run --help -h" -- "${cur}") )
            ;;
    esac
}

# Register the completion function for the jacker command
complete -F _jacker_completion jacker

# Also register for common aliases and direct script invocation
complete -F _jacker_completion ./jacker
complete -F _jacker_completion /usr/local/bin/jacker
