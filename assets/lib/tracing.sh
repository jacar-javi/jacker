#!/usr/bin/env bash
#
# Tracing Management Library for Jacker
# Functions for configuring distributed tracing (Jaeger, OpenTelemetry)
#

# Enable Jaeger tracing for Traefik
enable_jaeger_tracing() {
    info "Enabling Jaeger tracing for Traefik..."

    # Check if Jaeger service is running
    if ! docker ps --filter "name=jaeger" --filter "status=running" | grep -q jaeger; then
        warning "Jaeger container is not running"
        if confirm_action "Start Jaeger service now?"; then
            docker compose up -d jaeger
            sleep 5
        else
            error "Cannot enable tracing without Jaeger service"
            return 1
        fi
    fi

    # Traefik config is already set up with OTLP HTTP endpoint
    success "Jaeger tracing is enabled in Traefik configuration"
    info "Traces will be sent to: http://jaeger:4318/v1/traces"
    info "Jaeger UI available at: https://jaeger.\${PUBLIC_FQDN}"
    info "Restart Traefik to apply: ./jacker restart traefik"
}

# Disable tracing for Traefik
disable_tracing() {
    warning "Disabling tracing requires commenting out tracing section in traefik.yml"
    info "To manually disable:"
    echo "  1. Edit config/traefik/traefik.yml"
    echo "  2. Comment out the 'tracing:' section"
    echo "  3. Restart Traefik: ./jacker restart traefik"
}

# Show tracing status
show_tracing_status() {
    section "Tracing Status"

    # Check Jaeger service
    subsection "Jaeger Service"
    if docker ps --filter "name=jaeger" --filter "status=running" | grep -q jaeger; then
        success "Jaeger is running"

        # Get Jaeger container info
        local jaeger_info
        jaeger_info=$(docker ps --filter "name=jaeger" --format "table {{.Status}}\t{{.Ports}}" | tail -n 1)
        echo "Status: $jaeger_info"
    else
        warning "Jaeger is not running"
    fi

    # Check Traefik configuration
    subsection "Traefik Configuration"
    if docker exec traefik cat /etc/traefik/traefik.yml 2>/dev/null | grep -A 5 "^tracing:" | grep -q "otlp:"; then
        success "Tracing is enabled in Traefik"
        local endpoint
        endpoint=$(docker exec traefik cat /etc/traefik/traefik.yml | grep -A 10 "^tracing:" | grep "endpoint:" | awk '{print $2}')
        echo "OTLP Endpoint: $endpoint"
    else
        warning "Tracing is not configured in Traefik"
    fi

    # Check Jaeger UI access
    subsection "Jaeger UI"
    if [[ -f "$JACKER_ROOT/.env" ]]; then
        source "$JACKER_ROOT/.env"
        echo "URL: https://jaeger.$PUBLIC_FQDN"
    fi
}

# Configure tracing system
configure_tracing() {
    local system="${1:-}"

    if [[ -z "$system" ]]; then
        # Interactive selection
        echo ""
        echo "${CYAN}Select Tracing System:${NC}"
        echo "  1) Jaeger (OTLP HTTP - Recommended)"
        echo "  2) OpenTelemetry Collector (Advanced)"
        echo "  3) Disable Tracing"
        echo "  4) Show Current Status"
        echo ""
        read -rp "Choice [1-4]: " choice

        case "$choice" in
            1)
                system="jaeger"
                ;;
            2)
                system="otel-collector"
                ;;
            3)
                disable_tracing
                return 0
                ;;
            4)
                show_tracing_status
                return 0
                ;;
            *)
                error "Invalid choice"
                return 1
                ;;
        esac
    fi

    case "$system" in
        jaeger)
            enable_jaeger_tracing
            ;;
        otel-collector)
            info "OpenTelemetry Collector support"
            echo ""
            echo "To use an external OpenTelemetry Collector:"
            echo "  1. Edit config/traefik/traefik.yml"
            echo "  2. Update tracing.otlp.http.endpoint to your collector URL"
            echo "  3. Restart Traefik: ./jacker restart traefik"
            echo ""
            echo "Default Jaeger configuration uses OTLP which is compatible"
            echo "with OpenTelemetry Collector as an intermediary."
            ;;
        status)
            show_tracing_status
            ;;
        *)
            error "Unknown tracing system: $system"
            echo "Available systems: jaeger, otel-collector"
            return 1
            ;;
    esac
}

# Export functions
export -f enable_jaeger_tracing
export -f disable_tracing
export -f show_tracing_status
export -f configure_tracing
