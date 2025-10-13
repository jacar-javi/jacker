#!/usr/bin/env bash
#
# Bash completion script for Jacker CLI
#
# Installation:
#   1. Source this file in your .bashrc or .bash_profile:
#      source /path/to/jacker-completion.bash
#   2. Or copy it to your bash completion directory:
#      sudo cp jacker-completion.bash /etc/bash_completion.d/jacker
#

_jacker_services() {
    # Get list of services from docker-compose
    if [[ -f docker-compose.yml ]]; then
        docker compose config --services 2>/dev/null
    fi
}

_jacker_completion() {
    local cur prev words cword
    _init_completion || return

    local commands="init start stop restart status logs shell health fix backup restore update clean config secrets security info version help"

    local config_subcommands="show set validate oauth domain ssl authentik"
    local secrets_subcommands="list rotate generate verify"
    local security_subcommands="status crowdsec firewall scan"
    local fix_components="all loki traefik crowdsec postgres permissions network"

    # Handle command completion
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
        return 0
    fi

    # Get the main command
    local cmd="${words[1]}"

    # Handle subcommand and option completion based on the main command
    case "${cmd}" in
        start|stop|restart|shell|logs)
            # These commands accept service names
            if [[ "${cur}" == -* ]]; then
                case "${cmd}" in
                    start)
                        COMPREPLY=( $(compgen -W "--attach --help" -- "${cur}") )
                        ;;
                    stop)
                        COMPREPLY=( $(compgen -W "--volumes --help" -- "${cur}") )
                        ;;
                    restart)
                        COMPREPLY=( $(compgen -W "--help" -- "${cur}") )
                        ;;
                    logs)
                        COMPREPLY=( $(compgen -W "-f --follow --tail --since --help" -- "${cur}") )
                        ;;
                    shell)
                        COMPREPLY=( $(compgen -W "--bash --user --help" -- "${cur}") )
                        ;;
                esac
            else
                # Complete with service names
                local services=$(_jacker_services)
                COMPREPLY=( $(compgen -W "${services}" -- "${cur}") )
            fi
            ;;

        status)
            COMPREPLY=( $(compgen -W "--watch --json --help" -- "${cur}") )
            ;;

        health)
            COMPREPLY=( $(compgen -W "--verbose --json --help" -- "${cur}") )
            ;;

        fix)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${fix_components}" -- "${cur}") )
            else
                COMPREPLY=( $(compgen -W "--force --help" -- "${cur}") )
            fi
            ;;

        backup)
            COMPREPLY=( $(compgen -W "--location --with-volumes --help" -- "${cur}") )
            ;;

        restore)
            if [[ "${cur}" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force --help" -- "${cur}") )
            else
                # Complete with backup files
                COMPREPLY=( $(compgen -f -X '!*.tar.gz' -- "${cur}") )
            fi
            ;;

        update)
            COMPREPLY=( $(compgen -W "--check-only --skip-pull --help" -- "${cur}") )
            ;;

        clean)
            COMPREPLY=( $(compgen -W "--force --deep --help" -- "${cur}") )
            ;;

        config)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${config_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    oauth)
                        COMPREPLY=( $(compgen -W "--disable --help" -- "${cur}") )
                        ;;
                    ssl)
                        COMPREPLY=( $(compgen -W "--staging --force --help" -- "${cur}") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        secrets)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${secrets_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    rotate)
                        COMPREPLY=( $(compgen -W "all postgres redis oauth --help" -- "${cur}") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        security)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "${security_subcommands} help" -- "${cur}") )
            else
                case "${words[2]}" in
                    crowdsec)
                        COMPREPLY=( $(compgen -W "status bouncer decisions --help" -- "${cur}") )
                        ;;
                    firewall)
                        COMPREPLY=( $(compgen -W "status update reset --help" -- "${cur}") )
                        ;;
                    scan)
                        COMPREPLY=( $(compgen -W "--full --quick --help" -- "${cur}") )
                        ;;
                    *)
                        COMPREPLY=( $(compgen -W "--help" -- "${cur}") )
                        ;;
                esac
            fi
            ;;

        info)
            COMPREPLY=( $(compgen -W "--json --help" -- "${cur}") )
            ;;

        init)
            COMPREPLY=( $(compgen -W "--auto --force --help" -- "${cur}") )
            ;;

        *)
            # Global options available for all commands
            COMPREPLY=( $(compgen -W "-v --verbose -q --quiet --dry-run --help" -- "${cur}") )
            ;;
    esac
}

# Register the completion function for the jacker command
complete -F _jacker_completion jacker

# Also register for common aliases
complete -F _jacker_completion ./jacker