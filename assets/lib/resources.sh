#!/usr/bin/env bash
#
# resources.sh - System Resource Detection and Optimal Allocation Library
# Part of Jacker Infrastructure Performance Tuning System
#
# This library provides functions for:
# - Detecting system resources (CPU, RAM, disk, load)
# - Calculating performance scores and system tiers
# - Computing optimal resource allocations per service
# - Generating docker-compose.override.yml with calculated limits
# - Validating and displaying resource allocation summaries
#

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Global Variables and Configuration
# ============================================================================

# System resource variables (populated by detection functions)
declare -g CPU_CORES=0
declare -g CPU_THREADS=0
declare -g CPU_FREQ=""
declare -g CPU_ARCH=""
declare -g TOTAL_RAM_GB=0
declare -g AVAILABLE_RAM_GB=0
declare -g SWAP_GB=0
declare -g TOTAL_DISK_GB=0
declare -g AVAILABLE_DISK_GB=0
declare -g DISK_TYPE=""
declare -g LOAD_1MIN=0
declare -g LOAD_5MIN=0
declare -g LOAD_15MIN=0

# Performance scoring variables
declare -g PERFORMANCE_SCORE=0
declare -g SYSTEM_TIER=""
declare -g HOST_RESERVE_PCT=30

# Resource allocation arrays (associative arrays)
declare -gA SERVICE_CPU_LIMITS
declare -gA SERVICE_MEM_LIMITS
declare -gA SERVICE_CPU_RESERVES
declare -gA SERVICE_MEM_RESERVES
declare -gA SERVICE_ENABLED

# Service categories and base resource requirements
# Format: service_name => category:priority:base_cpu:base_mem
declare -gA SERVICE_PROFILES=(
    # Critical services (must run)
    ["traefik"]="critical:1:2.0:1024"
    ["postgres"]="critical:2:2.0:2048"
    ["redis"]="critical:3:1.0:1024"
    ["socket-proxy"]="critical:4:0.25:128"

    # High priority (essential for monitoring)
    ["prometheus"]="high:5:2.0:2048"
    ["grafana"]="high:6:1.0:1024"
    ["loki"]="high:7:2.0:2048"
    ["promtail"]="high:8:0.5:512"

    # Medium priority (security & monitoring)
    ["crowdsec"]="medium:9:1.0:512"
    ["alertmanager"]="medium:10:0.5:512"
    ["node-exporter"]="medium:11:0.5:256"
    ["blackbox-exporter"]="medium:12:0.5:256"
    ["cadvisor"]="medium:13:1.0:512"

    # Low priority (utilities)
    ["oauth2-proxy"]="low:14:0.5:256"
    ["postgres-exporter"]="low:15:0.25:128"
    ["redis-exporter"]="low:16:0.25:128"
    ["pushgateway"]="low:17:0.5:256"

    # Optional services (can be disabled on low-resource systems)
    ["jaeger"]="optional:18:1.0:1024"
    ["vscode"]="optional:19:2.0:2048"
    ["portainer"]="optional:20:0.5:512"
    ["homepage"]="optional:21:0.25:256"
    ["redis-commander"]="optional:22:0.25:256"
)

# System tier definitions
# Format: tier_name => min_score:max_score:reserve_pct:description
declare -gA TIER_DEFINITIONS=(
    ["minimal"]="0:30:50:Minimal resources - critical services only"
    ["basic"]="31:50:40:Basic resources - essential services"
    ["standard"]="51:70:30:Standard resources - full stack"
    ["performance"]="71:85:25:Performance resources - generous limits"
    ["high-performance"]="86:100:20:High-performance resources - maximum limits"
)

# ============================================================================
# System Resource Detection Functions
# ============================================================================

# Detect CPU resources
# Outputs: CPU_CORES, CPU_THREADS, CPU_FREQ, CPU_ARCH
detect_cpu_resources() {
    verbose "Detecting CPU resources..."

    # Detect CPU cores (physical cores)
    if [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c "^physical id" /proc/cpuinfo | sort -u | wc -l)
        # If physical id is not present, fall back to core count
        if [ "$CPU_CORES" -eq 0 ]; then
            CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
        fi
    else
        CPU_CORES=$(nproc 2>/dev/null || echo "1")
    fi

    # Detect CPU threads (logical processors)
    CPU_THREADS=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")

    # Detect CPU frequency
    if [ -f /proc/cpuinfo ]; then
        CPU_FREQ=$(grep "^cpu MHz" /proc/cpuinfo | head -1 | awk '{printf "%.1f GHz", $4/1000}')
    fi
    [ -z "$CPU_FREQ" ] && CPU_FREQ="Unknown"

    # Detect CPU architecture
    CPU_ARCH=$(uname -m 2>/dev/null || echo "unknown")

    verbose "CPU: ${CPU_CORES} cores, ${CPU_THREADS} threads, ${CPU_FREQ}, ${CPU_ARCH}"

    return 0
}

# Detect memory resources
# Outputs: TOTAL_RAM_GB, AVAILABLE_RAM_GB, SWAP_GB
detect_memory_resources() {
    verbose "Detecting memory resources..."

    if [ -f /proc/meminfo ]; then
        # Total RAM in GB
        local total_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.2f\", $total_kb/1024/1024}")

        # Available RAM in GB (includes buffers/cache)
        local available_kb=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}')
        if [ -n "$available_kb" ]; then
            AVAILABLE_RAM_GB=$(awk "BEGIN {printf \"%.2f\", $available_kb/1024/1024}")
        else
            # Fallback: MemFree + Buffers + Cached
            local free_kb=$(grep "^MemFree:" /proc/meminfo | awk '{print $2}')
            local buffers_kb=$(grep "^Buffers:" /proc/meminfo | awk '{print $2}')
            local cached_kb=$(grep "^Cached:" /proc/meminfo | awk '{print $2}')
            available_kb=$((free_kb + buffers_kb + cached_kb))
            AVAILABLE_RAM_GB=$(awk "BEGIN {printf \"%.2f\", $available_kb/1024/1024}")
        fi

        # Swap in GB
        local swap_kb=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}')
        SWAP_GB=$(awk "BEGIN {printf \"%.2f\", $swap_kb/1024/1024}")
    else
        warning "Cannot read /proc/meminfo - using defaults"
        TOTAL_RAM_GB=4.0
        AVAILABLE_RAM_GB=2.0
        SWAP_GB=0.0
    fi

    verbose "RAM: ${TOTAL_RAM_GB}GB total, ${AVAILABLE_RAM_GB}GB available, ${SWAP_GB}GB swap"

    return 0
}

# Detect disk resources
# Outputs: TOTAL_DISK_GB, AVAILABLE_DISK_GB, DISK_TYPE
detect_disk_resources() {
    verbose "Detecting disk resources..."

    # Get disk space for root filesystem
    local root_path="/"
    if [ -n "${JACKER_ROOT:-}" ]; then
        root_path="${JACKER_ROOT}"
    fi

    # Total and available disk space in GB
    local disk_info=$(df -BG "$root_path" 2>/dev/null | tail -1)
    if [ -n "$disk_info" ]; then
        TOTAL_DISK_GB=$(echo "$disk_info" | awk '{gsub(/G/, "", $2); print $2}')
        AVAILABLE_DISK_GB=$(echo "$disk_info" | awk '{gsub(/G/, "", $4); print $4}')
    else
        warning "Cannot get disk space - using defaults"
        TOTAL_DISK_GB=100
        AVAILABLE_DISK_GB=50
    fi

    # Detect disk type (SSD vs HDD)
    local disk_device=$(df "$root_path" 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
    disk_device=$(basename "$disk_device" 2>/dev/null)

    if [ -n "$disk_device" ] && [ -f "/sys/block/${disk_device}/queue/rotational" ]; then
        local rotational=$(cat "/sys/block/${disk_device}/queue/rotational" 2>/dev/null)
        if [ "$rotational" = "0" ]; then
            DISK_TYPE="SSD"
        else
            DISK_TYPE="HDD"
        fi
    else
        DISK_TYPE="Unknown"
    fi

    verbose "Disk: ${TOTAL_DISK_GB}GB total, ${AVAILABLE_DISK_GB}GB available, Type: ${DISK_TYPE}"

    return 0
}

# Detect system load
# Outputs: LOAD_1MIN, LOAD_5MIN, LOAD_15MIN
detect_system_load() {
    verbose "Detecting system load..."

    if [ -f /proc/loadavg ]; then
        read -r LOAD_1MIN LOAD_5MIN LOAD_15MIN _ _ < /proc/loadavg
    else
        warning "Cannot read /proc/loadavg - using defaults"
        LOAD_1MIN=0.0
        LOAD_5MIN=0.0
        LOAD_15MIN=0.0
    fi

    verbose "Load average: ${LOAD_1MIN} (1min), ${LOAD_5MIN} (5min), ${LOAD_15MIN} (15min)"

    return 0
}

# Detect all system resources at once
detect_all_resources() {
    section "Detecting System Resources"

    detect_cpu_resources
    detect_memory_resources
    detect_disk_resources
    detect_system_load

    success "Resource detection complete"
    return 0
}

# ============================================================================
# Performance Score Calculation
# ============================================================================

# Calculate CPU score (0-30 points)
calculate_cpu_score() {
    local score=0

    # Base score on logical CPU threads
    if [ "$CPU_THREADS" -ge 16 ]; then
        score=30
    elif [ "$CPU_THREADS" -ge 12 ]; then
        score=28
    elif [ "$CPU_THREADS" -ge 8 ]; then
        score=25
    elif [ "$CPU_THREADS" -ge 6 ]; then
        score=20
    elif [ "$CPU_THREADS" -ge 4 ]; then
        score=15
    elif [ "$CPU_THREADS" -ge 2 ]; then
        score=10
    else
        score=5
    fi

    echo "$score"
}

# Calculate RAM score (0-30 points)
calculate_ram_score() {
    local score=0
    local ram_gb=$(printf "%.0f" "$TOTAL_RAM_GB")

    if [ "$ram_gb" -ge 32 ]; then
        score=30
    elif [ "$ram_gb" -ge 16 ]; then
        score=28
    elif [ "$ram_gb" -ge 12 ]; then
        score=25
    elif [ "$ram_gb" -ge 8 ]; then
        score=20
    elif [ "$ram_gb" -ge 6 ]; then
        score=15
    elif [ "$ram_gb" -ge 4 ]; then
        score=10
    else
        score=5
    fi

    echo "$score"
}

# Calculate disk score (0-20 points)
calculate_disk_score() {
    local score=0

    # Base score on disk size
    if [ "$TOTAL_DISK_GB" -ge 500 ]; then
        score=15
    elif [ "$TOTAL_DISK_GB" -ge 200 ]; then
        score=12
    elif [ "$TOTAL_DISK_GB" -ge 100 ]; then
        score=10
    elif [ "$TOTAL_DISK_GB" -ge 50 ]; then
        score=7
    else
        score=5
    fi

    # Bonus for SSD
    if [ "$DISK_TYPE" = "SSD" ]; then
        score=$((score + 5))
    fi

    # Cap at 20
    [ "$score" -gt 20 ] && score=20

    echo "$score"
}

# Calculate network score (0-10 points)
calculate_network_score() {
    local score=8  # Default score (assume decent network)

    # Check for network interfaces
    local interface_count=$(ip link show 2>/dev/null | grep -c "^[0-9]:" || echo "1")

    if [ "$interface_count" -ge 3 ]; then
        score=10
    elif [ "$interface_count" -ge 2 ]; then
        score=8
    else
        score=6
    fi

    echo "$score"
}

# Calculate health score (0-10 points) based on load average
calculate_health_score() {
    local score=10

    # Penalize high load average
    local load_ratio=$(awk "BEGIN {printf \"%.2f\", $LOAD_1MIN / $CPU_THREADS}")
    local load_pct=$(awk "BEGIN {printf \"%.0f\", $load_ratio * 100}")

    if [ "$load_pct" -ge 90 ]; then
        score=2
    elif [ "$load_pct" -ge 80 ]; then
        score=4
    elif [ "$load_pct" -ge 70 ]; then
        score=6
    elif [ "$load_pct" -ge 60 ]; then
        score=8
    else
        score=10
    fi

    echo "$score"
}

# Calculate overall performance score (0-100)
# Score breakdown:
# - CPU: 30 points
# - RAM: 30 points
# - Disk: 20 points
# - Network: 10 points
# - Health: 10 points
calculate_performance_score() {
    verbose "Calculating performance score..."

    local cpu_score=$(calculate_cpu_score)
    local ram_score=$(calculate_ram_score)
    local disk_score=$(calculate_disk_score)
    local network_score=$(calculate_network_score)
    local health_score=$(calculate_health_score)

    PERFORMANCE_SCORE=$((cpu_score + ram_score + disk_score + network_score + health_score))

    # Determine system tier based on score
    if [ "$PERFORMANCE_SCORE" -ge 86 ]; then
        SYSTEM_TIER="high-performance"
        HOST_RESERVE_PCT=20
    elif [ "$PERFORMANCE_SCORE" -ge 71 ]; then
        SYSTEM_TIER="performance"
        HOST_RESERVE_PCT=25
    elif [ "$PERFORMANCE_SCORE" -ge 51 ]; then
        SYSTEM_TIER="standard"
        HOST_RESERVE_PCT=30
    elif [ "$PERFORMANCE_SCORE" -ge 31 ]; then
        SYSTEM_TIER="basic"
        HOST_RESERVE_PCT=40
    else
        SYSTEM_TIER="minimal"
        HOST_RESERVE_PCT=50
    fi

    verbose "Performance score: ${PERFORMANCE_SCORE}/100 (Tier: ${SYSTEM_TIER})"
    verbose "Score breakdown: CPU=${cpu_score}, RAM=${ram_score}, Disk=${disk_score}, Network=${network_score}, Health=${health_score}"

    return 0
}

# ============================================================================
# Resource Allocation Calculation
# ============================================================================

# Determine which services to enable based on tier
determine_enabled_services() {
    verbose "Determining enabled services for tier: ${SYSTEM_TIER}..."

    # Reset enabled services
    for service in "${!SERVICE_PROFILES[@]}"; do
        SERVICE_ENABLED[$service]=1
    done

    case "$SYSTEM_TIER" in
        minimal)
            # Only critical services
            for service in "${!SERVICE_PROFILES[@]}"; do
                local category=$(echo "${SERVICE_PROFILES[$service]}" | cut -d: -f1)
                if [ "$category" != "critical" ]; then
                    SERVICE_ENABLED[$service]=0
                fi
            done
            ;;
        basic)
            # Critical + high priority + essential medium
            for service in "${!SERVICE_PROFILES[@]}"; do
                local category=$(echo "${SERVICE_PROFILES[$service]}" | cut -d: -f1)
                if [ "$category" = "optional" ]; then
                    SERVICE_ENABLED[$service]=0
                fi
                # Disable heavy services
                if [ "$service" = "jaeger" ] || [ "$service" = "vscode" ] || [ "$service" = "loki" ]; then
                    SERVICE_ENABLED[$service]=0
                fi
            done
            ;;
        standard)
            # All except heavy optional services
            for service in "${!SERVICE_PROFILES[@]}"; do
                if [ "$service" = "vscode" ]; then
                    SERVICE_ENABLED[$service]=0
                fi
            done
            ;;
        performance|high-performance)
            # All services enabled
            ;;
    esac

    # Count enabled services
    local enabled_count=0
    for service in "${!SERVICE_ENABLED[@]}"; do
        if [ "${SERVICE_ENABLED[$service]}" -eq 1 ]; then
            enabled_count=$((enabled_count + 1))
        fi
    done

    verbose "Enabled services: ${enabled_count}/${#SERVICE_PROFILES[@]}"

    return 0
}

# Calculate resource multipliers based on tier
get_tier_multiplier() {
    local resource_type="$1"  # cpu or memory
    local multiplier="1.0"

    case "$SYSTEM_TIER" in
        minimal)
            [ "$resource_type" = "cpu" ] && multiplier="0.5"
            [ "$resource_type" = "memory" ] && multiplier="0.6"
            ;;
        basic)
            [ "$resource_type" = "cpu" ] && multiplier="0.75"
            [ "$resource_type" = "memory" ] && multiplier="0.8"
            ;;
        standard)
            multiplier="1.0"
            ;;
        performance)
            [ "$resource_type" = "cpu" ] && multiplier="1.25"
            [ "$resource_type" = "memory" ] && multiplier="1.2"
            ;;
        high-performance)
            [ "$resource_type" = "cpu" ] && multiplier="1.5"
            [ "$resource_type" = "memory" ] && multiplier="1.5"
            ;;
    esac

    echo "$multiplier"
}

# Calculate optimal resource allocations for all services
calculate_resource_allocations() {
    section "Calculating Resource Allocations"

    # First, determine which services to enable
    determine_enabled_services

    # Calculate available resources after host reserve
    local available_cpu=$(awk "BEGIN {printf \"%.2f\", $CPU_THREADS * (100 - $HOST_RESERVE_PCT) / 100}")
    local available_mem_mb=$(awk "BEGIN {printf \"%.0f\", $TOTAL_RAM_GB * 1024 * (100 - $HOST_RESERVE_PCT) / 100}")

    info "Available resources: ${available_cpu} CPUs, ${available_mem_mb}MB RAM"

    # Get tier multipliers
    local cpu_multiplier=$(get_tier_multiplier "cpu")
    local mem_multiplier=$(get_tier_multiplier "memory")

    verbose "Tier multipliers: CPU=${cpu_multiplier}x, Memory=${mem_multiplier}x"

    # Calculate total base requirements for enabled services
    local total_base_cpu=0
    local total_base_mem=0

    for service in "${!SERVICE_PROFILES[@]}"; do
        if [ "${SERVICE_ENABLED[$service]}" -eq 1 ]; then
            local profile="${SERVICE_PROFILES[$service]}"
            local base_cpu=$(echo "$profile" | cut -d: -f3)
            local base_mem=$(echo "$profile" | cut -d: -f4)
            total_base_cpu=$(awk "BEGIN {printf \"%.2f\", $total_base_cpu + $base_cpu}")
            total_base_mem=$((total_base_mem + base_mem))
        fi
    done

    verbose "Total base requirements: ${total_base_cpu} CPUs, ${total_base_mem}MB RAM"

    # Calculate scaling factors if we need to fit within available resources
    local cpu_scale=1.0
    local mem_scale=1.0

    local total_target_cpu=$(awk "BEGIN {printf \"%.2f\", $total_base_cpu * $cpu_multiplier}")
    local total_target_mem=$(awk "BEGIN {printf \"%.0f\", $total_base_mem * $mem_multiplier}")

    # Check if we need to scale down
    if (( $(awk "BEGIN {print ($total_target_cpu > $available_cpu)}") )); then
        cpu_scale=$(awk "BEGIN {printf \"%.2f\", $available_cpu / $total_target_cpu}")
        warning "CPU over-allocation detected, scaling down by ${cpu_scale}x"
    fi

    if [ "$total_target_mem" -gt "$available_mem_mb" ]; then
        mem_scale=$(awk "BEGIN {printf \"%.2f\", $available_mem_mb / $total_target_mem}")
        warning "Memory over-allocation detected, scaling down by ${mem_scale}x"
    fi

    # Calculate final allocations for each service
    for service in "${!SERVICE_PROFILES[@]}"; do
        if [ "${SERVICE_ENABLED[$service]}" -eq 0 ]; then
            continue
        fi

        local profile="${SERVICE_PROFILES[$service]}"
        local base_cpu=$(echo "$profile" | cut -d: -f3)
        local base_mem=$(echo "$profile" | cut -d: -f4)

        # Apply tier multiplier and scaling
        local cpu_limit=$(awk "BEGIN {printf \"%.2f\", $base_cpu * $cpu_multiplier * $cpu_scale}")
        local mem_limit=$(awk "BEGIN {printf \"%.0f\", $base_mem * $mem_multiplier * $mem_scale}")

        # Calculate reservations (25% of limits for critical, 20% for others)
        local category=$(echo "$profile" | cut -d: -f1)
        local reserve_pct=20
        [ "$category" = "critical" ] && reserve_pct=25

        local cpu_reserve=$(awk "BEGIN {printf \"%.2f\", $cpu_limit * $reserve_pct / 100}")
        local mem_reserve=$(awk "BEGIN {printf \"%.0f\", $mem_limit * $reserve_pct / 100}")

        # Ensure minimums
        cpu_reserve=$(awk "BEGIN {print ($cpu_reserve < 0.1) ? 0.1 : $cpu_reserve}")
        mem_reserve=$(awk "BEGIN {print ($mem_reserve < 64) ? 64 : $mem_reserve}")

        # Store allocations
        SERVICE_CPU_LIMITS[$service]="$cpu_limit"
        SERVICE_MEM_LIMITS[$service]="$mem_limit"
        SERVICE_CPU_RESERVES[$service]="$cpu_reserve"
        SERVICE_MEM_RESERVES[$service]="$mem_reserve"

        verbose "  ${service}: CPU=${cpu_limit} (reserve ${cpu_reserve}), RAM=${mem_limit}M (reserve ${mem_reserve}M)"
    done

    success "Resource allocation calculation complete"
    return 0
}

# ============================================================================
# Docker Compose Override Generation
# ============================================================================

# Generate docker-compose.override.yml with calculated resource limits
generate_resource_override() {
    local override_file="${1:-docker-compose.override.yml}"

    section "Generating Resource Override File"

    info "Creating: ${override_file}"

    # Start YAML file
    cat > "$override_file" <<EOF
# docker-compose.override.yml
# Auto-generated resource limits based on system capabilities
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
#
# System Information:
#   Performance Score: ${PERFORMANCE_SCORE}/100
#   System Tier: ${SYSTEM_TIER}
#   CPU: ${CPU_THREADS} threads (${CPU_CORES} cores)
#   RAM: ${TOTAL_RAM_GB}GB total
#   Disk: ${TOTAL_DISK_GB}GB (${DISK_TYPE})
#   Host Reserve: ${HOST_RESERVE_PCT}%
#
# DO NOT EDIT THIS FILE MANUALLY - it will be regenerated
# To recalculate: run './jacker tune' or './jacker setup'

services:
EOF

    # Generate service entries
    local service_count=0
    for service in $(printf '%s\n' "${!SERVICE_PROFILES[@]}" | sort); do
        # Skip disabled services
        if [ "${SERVICE_ENABLED[$service]:-0}" -eq 0 ]; then
            # Add comment for disabled service
            cat >> "$override_file" <<EOF

  # ${service}: disabled for ${SYSTEM_TIER} tier
  ${service}:
    deploy:
      replicas: 0
EOF
            continue
        fi

        # Get allocations
        local cpu_limit="${SERVICE_CPU_LIMITS[$service]}"
        local mem_limit="${SERVICE_MEM_LIMITS[$service]}"
        local cpu_reserve="${SERVICE_CPU_RESERVES[$service]}"
        local mem_reserve="${SERVICE_MEM_RESERVES[$service]}"

        # Add service entry
        cat >> "$override_file" <<EOF

  ${service}:
    deploy:
      resources:
        limits:
          cpus: '${cpu_limit}'
          memory: ${mem_limit}M
        reservations:
          cpus: '${cpu_reserve}'
          memory: ${mem_reserve}M
EOF

        service_count=$((service_count + 1))
    done

    success "Generated override file with ${service_count} service configurations"

    return 0
}

# ============================================================================
# Validation and Safety Checks
# ============================================================================

# Validate resource allocation doesn't exceed available resources
validate_resource_allocation() {
    verbose "Validating resource allocation..."

    # Calculate total allocated resources
    local total_cpu=0
    local total_mem=0

    for service in "${!SERVICE_PROFILES[@]}"; do
        if [ "${SERVICE_ENABLED[$service]:-0}" -eq 1 ]; then
            local cpu="${SERVICE_CPU_LIMITS[$service]}"
            local mem="${SERVICE_MEM_LIMITS[$service]}"
            total_cpu=$(awk "BEGIN {printf \"%.2f\", $total_cpu + $cpu}")
            total_mem=$((total_mem + mem))
        fi
    done

    # Calculate available after host reserve
    local available_cpu=$(awk "BEGIN {printf \"%.2f\", $CPU_THREADS * (100 - $HOST_RESERVE_PCT) / 100}")
    local available_mem=$(awk "BEGIN {printf \"%.0f\", $TOTAL_RAM_GB * 1024 * (100 - $HOST_RESERVE_PCT) / 100}")

    # Check CPU (handle division by zero)
    local cpu_usage_pct=0
    if (( $(awk "BEGIN {print ($available_cpu > 0)}") )); then
        cpu_usage_pct=$(awk "BEGIN {printf \"%.0f\", ($total_cpu / $available_cpu) * 100}")
        if [ "$cpu_usage_pct" -gt 100 ] 2>/dev/null; then
            error "CPU over-allocation: ${total_cpu} CPUs allocated, ${available_cpu} available"
            return 1
        elif [ "$cpu_usage_pct" -gt 90 ] 2>/dev/null; then
            warning "CPU allocation high: ${cpu_usage_pct}% of available CPUs"
        fi
    fi

    # Check Memory (handle division by zero)
    local mem_usage_pct=0
    if [ "$available_mem" -gt 0 ] 2>/dev/null; then
        mem_usage_pct=$(awk "BEGIN {printf \"%.0f\", ($total_mem / $available_mem) * 100}")
        if [ "$mem_usage_pct" -gt 100 ] 2>/dev/null; then
            error "Memory over-allocation: ${total_mem}MB allocated, ${available_mem}MB available"
            return 1
        elif [ "$mem_usage_pct" -gt 90 ] 2>/dev/null; then
            warning "Memory allocation high: ${mem_usage_pct}% of available RAM"
        fi
    fi

    verbose "Validation passed: CPU=${cpu_usage_pct}%, RAM=${mem_usage_pct}%"

    return 0
}

# ============================================================================
# Summary Display Functions
# ============================================================================

# Show colorized resource summary
show_resource_summary() {
    section "Resource Allocation Summary"

    # System tier with color
    local tier_color="$GREEN"
    case "$SYSTEM_TIER" in
        minimal) tier_color="$RED" ;;
        basic) tier_color="$YELLOW" ;;
        standard) tier_color="$BLUE" ;;
        performance) tier_color="$GREEN" ;;
        high-performance) tier_color="$MAGENTA" ;;
    esac

    echo ""
    print_color "$tier_color" "┌─────────────────────────────────────────────────────────┐"
    print_color "$tier_color" "│  System Tier: $(printf '%-43s' "${SYSTEM_TIER^^}") │"
    print_color "$tier_color" "│  Performance Score: $(printf '%-35s' "${PERFORMANCE_SCORE}/100") │"
    print_color "$tier_color" "└─────────────────────────────────────────────────────────┘"
    echo ""

    # System resources
    subsection "System Resources"
    printf "  %-20s: %d threads (%d cores) @ %s [%s]\n" "CPU" "$CPU_THREADS" "$CPU_CORES" "$CPU_FREQ" "$CPU_ARCH"
    printf "  %-20s: %.2fGB total / %.2fGB available\n" "RAM" "$TOTAL_RAM_GB" "$AVAILABLE_RAM_GB"
    printf "  %-20s: %dGB total / %dGB available [%s]\n" "Disk" "$TOTAL_DISK_GB" "$AVAILABLE_DISK_GB" "$DISK_TYPE"
    printf "  %-20s: %.2f / %.2f / %.2f\n" "Load Average" "$LOAD_1MIN" "$LOAD_5MIN" "$LOAD_15MIN"
    printf "  %-20s: %d%% reserved for host OS\n" "Host Reserve" "$HOST_RESERVE_PCT"
    echo ""

    # Service allocation summary by category
    subsection "Service Allocation by Category"

    for category in "critical" "high" "medium" "low" "optional"; do
        local category_services=()
        local enabled_count=0
        local disabled_count=0

        for service in "${!SERVICE_PROFILES[@]}"; do
            local svc_category=$(echo "${SERVICE_PROFILES[$service]}" | cut -d: -f1)
            if [ "$svc_category" = "$category" ]; then
                category_services+=("$service")
                if [ "${SERVICE_ENABLED[$service]:-0}" -eq 1 ]; then
                    enabled_count=$((enabled_count + 1))
                else
                    disabled_count=$((disabled_count + 1))
                fi
            fi
        done

        if [ ${#category_services[@]} -eq 0 ]; then
            continue
        fi

        # Category header with color
        local cat_color="$WHITE"
        case "$category" in
            critical) cat_color="$RED" ;;
            high) cat_color="$YELLOW" ;;
            medium) cat_color="$BLUE" ;;
            low) cat_color="$CYAN" ;;
            optional) cat_color="$MAGENTA" ;;
        esac

        echo ""
        print_color "$cat_color" "  ${category^^} (${enabled_count} enabled, ${disabled_count} disabled)"
        print_color "$cat_color" "  $(printf '%.0s─' {1..55})"

        # Sort and display services
        for service in $(printf '%s\n' "${category_services[@]}" | sort); do
            if [ "${SERVICE_ENABLED[$service]:-0}" -eq 1 ]; then
                local cpu="${SERVICE_CPU_LIMITS[$service]}"
                local mem="${SERVICE_MEM_LIMITS[$service]}"
                printf "    ${GREEN}%-20s${NC}: CPU %-6s RAM %6sM\n" "$service" "${cpu}" "${mem}"
            else
                printf "    ${RED}%-20s${NC}: DISABLED\n" "$service"
            fi
        done
    done

    echo ""

    # Total allocation
    local total_cpu=0
    local total_mem=0
    local enabled_count=0

    for service in "${!SERVICE_PROFILES[@]}"; do
        if [ "${SERVICE_ENABLED[$service]:-0}" -eq 1 ]; then
            enabled_count=$((enabled_count + 1))
            local cpu="${SERVICE_CPU_LIMITS[$service]}"
            local mem="${SERVICE_MEM_LIMITS[$service]}"
            total_cpu=$(awk "BEGIN {printf \"%.2f\", $total_cpu + $cpu}")
            total_mem=$((total_mem + mem))
        fi
    done

    local available_cpu=$(awk "BEGIN {printf \"%.2f\", $CPU_THREADS * (100 - $HOST_RESERVE_PCT) / 100}")
    local available_mem=$(awk "BEGIN {printf \"%.0f\", $TOTAL_RAM_GB * 1024 * (100 - $HOST_RESERVE_PCT) / 100}")

    local cpu_pct=0
    local mem_pct=0
    if (( $(awk "BEGIN {print ($available_cpu > 0)}") )); then
        cpu_pct=$(awk "BEGIN {printf \"%.0f\", ($total_cpu / $available_cpu) * 100}")
    fi
    if [ "$available_mem" -gt 0 ] 2>/dev/null; then
        mem_pct=$(awk "BEGIN {printf \"%.0f\", ($total_mem / $available_mem) * 100}")
    fi

    subsection "Total Allocation"
    printf "  %-20s: %d enabled / %d total\n" "Services" "$enabled_count" "${#SERVICE_PROFILES[@]}"
    printf "  %-20s: %.2f / %.2f CPUs (${cpu_pct}%%)\n" "CPU Allocated" "$total_cpu" "$available_cpu"
    printf "  %-20s: %dM / %dM RAM (${mem_pct}%%)\n" "RAM Allocated" "$total_mem" "$available_mem"
    echo ""

    # Warnings
    if [ "$cpu_pct" -gt 90 ] || [ "$mem_pct" -gt 90 ]; then
        warning "Resource utilization is high - monitor system performance"
    fi

    if [ "$SYSTEM_TIER" = "minimal" ] || [ "$SYSTEM_TIER" = "basic" ]; then
        warning "System tier is low - consider upgrading hardware for full functionality"
        info "Some services have been disabled to fit within available resources"
    fi

    return 0
}

# ============================================================================
# Main Orchestration Function
# ============================================================================

# Apply resource tuning - main entry point
# This orchestrates the entire resource tuning process
apply_resource_tuning() {
    local override_file="${1:-docker-compose.override.yml}"
    local skip_override="${2:-false}"

    section "Jacker Resource Tuning System"

    info "Starting automatic resource tuning..."
    echo ""

    # Step 1: Detect system resources
    detect_all_resources || {
        error "Failed to detect system resources"
        return 1
    }

    echo ""

    # Step 2: Calculate performance score
    calculate_performance_score || {
        error "Failed to calculate performance score"
        return 1
    }

    echo ""

    # Step 3: Calculate optimal allocations
    calculate_resource_allocations || {
        error "Failed to calculate resource allocations"
        return 1
    }

    echo ""

    # Step 4: Validate allocations
    validate_resource_allocation || {
        error "Resource allocation validation failed"
        return 1
    }

    echo ""

    # Step 5: Generate override file (if not skipped)
    if [ "$skip_override" != "true" ]; then
        generate_resource_override "$override_file" || {
            error "Failed to generate resource override file"
            return 1
        }
        echo ""
    fi

    # Step 6: Show summary
    show_resource_summary

    echo ""
    success "Resource tuning complete!"

    if [ "$skip_override" != "true" ]; then
        info "Override file created: ${override_file}"
        info "To apply changes: docker compose up -d"
    fi

    return 0
}

# Export all functions
export -f detect_cpu_resources detect_memory_resources detect_disk_resources detect_system_load
export -f detect_all_resources
export -f calculate_cpu_score calculate_ram_score calculate_disk_score calculate_network_score calculate_health_score
export -f calculate_performance_score
export -f determine_enabled_services get_tier_multiplier calculate_resource_allocations
export -f generate_resource_override
export -f validate_resource_allocation
export -f show_resource_summary
export -f apply_resource_tuning
