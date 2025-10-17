#!/bin/bash

# Jacker Infrastructure - System Information & Performance Score
# This script displays system information and calculates a performance score

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Performance score variables
CPU_SCORE=0
RAM_SCORE=0
DISK_SCORE=0
NETWORK_SCORE=0
HEALTH_SCORE=0

# Helper function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper function to convert to GB
bytes_to_gb() {
    if command_exists bc; then
        echo "scale=1; $1 / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0"
    else
        echo $(( $1 / 1024 / 1024 / 1024 ))
    fi
}

# Helper function to convert KB to GB
kb_to_gb() {
    if command_exists bc; then
        echo "scale=1; $1 / 1024 / 1024" | bc 2>/dev/null || echo "0"
    else
        # Use bash arithmetic for basic conversion
        local gb=$(( $1 / 1024 / 1024 ))
        local decimal=$(( ($1 * 10 / 1024 / 1024) % 10 ))
        echo "${gb}.${decimal}"
    fi
}

# Get CPU Information
get_cpu_info() {
    if [ -f /proc/cpuinfo ]; then
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
        [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 "Hardware" /proc/cpuinfo | cut -d: -f2 | xargs)
        [ -z "$CPU_MODEL" ] && CPU_MODEL="Unknown"

        CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)

        # Try to get threads per core
        CPU_THREADS=$CPU_CORES
        if command_exists lscpu; then
            THREADS_PER_CORE=$(lscpu | grep "Thread(s) per core" | awk '{print $NF}')
            if [ -n "$THREADS_PER_CORE" ]; then
                CPU_THREADS=$((CPU_CORES * THREADS_PER_CORE / $(lscpu | grep "Core(s) per socket" | awk '{print $NF}' || echo 1)))
            fi
        fi

        CPU_FREQ=$(grep -m1 "cpu MHz" /proc/cpuinfo | awk '{print $4}')
        if [ -n "$CPU_FREQ" ]; then
            if command_exists bc; then
                CPU_FREQ=$(echo "scale=2; $CPU_FREQ / 1000" | bc 2>/dev/null || echo "Unknown")
            else
                # Convert MHz to GHz using bash arithmetic
                CPU_FREQ_INT=$(echo "$CPU_FREQ" | cut -d. -f1)
                CPU_FREQ=$(awk "BEGIN {printf \"%.2f\", $CPU_FREQ / 1000}")
            fi
            CPU_FREQ="${CPU_FREQ} GHz"
        else
            CPU_FREQ="Unknown"
        fi

        # Get cache size
        CPU_CACHE=$(grep -m1 "cache size" /proc/cpuinfo | awk '{print $4, $5}')
        [ -z "$CPU_CACHE" ] && CPU_CACHE="Unknown"
    else
        CPU_MODEL="Unknown"
        CPU_CORES=1
        CPU_THREADS=1
        CPU_FREQ="Unknown"
        CPU_CACHE="Unknown"
    fi

    # Calculate CPU Score
    if [ "$CPU_CORES" -le 2 ]; then
        CPU_SCORE=5
    elif [ "$CPU_CORES" -le 4 ]; then
        CPU_SCORE=15
    elif [ "$CPU_CORES" -le 8 ]; then
        CPU_SCORE=25
    else
        CPU_SCORE=30
    fi
}

# Get Memory Information
get_memory_info() {
    if [ -f /proc/meminfo ]; then
        MEM_TOTAL_KB=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        MEM_AVAILABLE_KB=$(grep "MemAvailable" /proc/meminfo | awk '{print $2}')
        [ -z "$MEM_AVAILABLE_KB" ] && MEM_AVAILABLE_KB=$(grep "MemFree" /proc/meminfo | awk '{print $2}')
        SWAP_TOTAL_KB=$(grep "SwapTotal" /proc/meminfo | awk '{print $2}')

        # Ensure we have valid numbers
        [ -z "$MEM_TOTAL_KB" ] && MEM_TOTAL_KB=0
        [ -z "$MEM_AVAILABLE_KB" ] && MEM_AVAILABLE_KB=0
        [ -z "$SWAP_TOTAL_KB" ] && SWAP_TOTAL_KB=0

        MEM_TOTAL_GB=$(kb_to_gb $MEM_TOTAL_KB)
        MEM_AVAILABLE_GB=$(kb_to_gb $MEM_AVAILABLE_KB)
        SWAP_TOTAL_GB=$(kb_to_gb $SWAP_TOTAL_KB)

        # Handle division by zero
        if [ "$MEM_TOTAL_KB" -gt 0 ]; then
            if command_exists bc; then
                MEM_PERCENT=$(echo "scale=0; $MEM_AVAILABLE_KB * 100 / $MEM_TOTAL_KB" | bc 2>/dev/null || echo "0")
            else
                MEM_PERCENT=$(( MEM_AVAILABLE_KB * 100 / MEM_TOTAL_KB ))
            fi
        else
            MEM_PERCENT=0
        fi
    else
        MEM_TOTAL_GB="Unknown"
        MEM_AVAILABLE_GB="Unknown"
        SWAP_TOTAL_GB="Unknown"
        MEM_PERCENT=0
    fi

    # Calculate RAM Score
    MEM_TOTAL_NUM=$(echo "$MEM_TOTAL_GB" | sed 's/[^0-9]//g')
    [ -z "$MEM_TOTAL_NUM" ] && MEM_TOTAL_NUM=0

    if [ "$MEM_TOTAL_NUM" -lt 2 ] 2>/dev/null; then
        RAM_SCORE=5
    elif [ "$MEM_TOTAL_NUM" -lt 4 ] 2>/dev/null; then
        RAM_SCORE=10
    elif [ "$MEM_TOTAL_NUM" -lt 8 ] 2>/dev/null; then
        RAM_SCORE=15
    elif [ "$MEM_TOTAL_NUM" -lt 16 ] 2>/dev/null; then
        RAM_SCORE=20
    elif [ "$MEM_TOTAL_NUM" -lt 32 ] 2>/dev/null; then
        RAM_SCORE=25
    else
        RAM_SCORE=30
    fi
}

# Get Disk Information
get_disk_info() {
    if command_exists df; then
        DISK_INFO=$(df -h / 2>/dev/null | tail -1)
        DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')
        DISK_AVAILABLE=$(echo "$DISK_INFO" | awk '{print $4}')
        DISK_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')

        # Try to detect SSD
        DISK_TYPE="Unknown"
        ROOT_DEV=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's/\/dev\///')
        if [ -f "/sys/block/${ROOT_DEV}/queue/rotational" ]; then
            ROTATIONAL=$(cat "/sys/block/${ROOT_DEV}/queue/rotational" 2>/dev/null)
            [ "$ROTATIONAL" = "0" ] && DISK_TYPE="SSD" || DISK_TYPE="HDD"
        fi
    else
        DISK_TOTAL="Unknown"
        DISK_AVAILABLE="Unknown"
        DISK_PERCENT="0"
        DISK_TYPE="Unknown"
    fi

    # Calculate Disk Score (convert to GB for comparison)
    DISK_TOTAL_NUM=$(echo "$DISK_TOTAL" | sed 's/[^0-9.]//g')
    DISK_UNIT=$(echo "$DISK_TOTAL" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')

    if [ "$DISK_UNIT" = "T" ] || [ "$DISK_UNIT" = "TB" ]; then
        if command_exists bc; then
            DISK_TOTAL_GB=$(echo "scale=0; $DISK_TOTAL_NUM * 1024" | bc 2>/dev/null || echo "1000")
        else
            DISK_TOTAL_INT=$(echo "$DISK_TOTAL_NUM" | cut -d. -f1)
            DISK_TOTAL_GB=$(( DISK_TOTAL_INT * 1024 ))
        fi
    else
        DISK_TOTAL_GB=$(echo "$DISK_TOTAL_NUM" | cut -d. -f1)
    fi

    if [ "$DISK_TOTAL_GB" -lt 50 ] 2>/dev/null; then
        DISK_SCORE=5
    elif [ "$DISK_TOTAL_GB" -lt 100 ] 2>/dev/null; then
        DISK_SCORE=8
    elif [ "$DISK_TOTAL_GB" -lt 250 ] 2>/dev/null; then
        DISK_SCORE=12
    elif [ "$DISK_TOTAL_GB" -lt 500 ] 2>/dev/null; then
        DISK_SCORE=16
    else
        DISK_SCORE=20
    fi
}

# Get Network Information
get_network_info() {
    NETWORK_INTERFACES=""
    INTERFACE_COUNT=0

    if command_exists ip; then
        while IFS= read -r line; do
            IFACE=$(echo "$line" | awk '{print $1}')
            IP=$(echo "$line" | awk '{print $2}')
            [ "$IFACE" != "lo" ] && NETWORK_INTERFACES="${NETWORK_INTERFACES}   ${IFACE}: ${IP}\n" && INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
        done < <(ip -4 addr show | grep -E "inet " | awk '{print $NF, $2}' | sed 's/\/.*//')
    elif command_exists ifconfig; then
        while IFS= read -r iface; do
            [ "$iface" != "lo" ] && IP=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | sed 's/addr://')
            [ -n "$IP" ] && NETWORK_INTERFACES="${NETWORK_INTERFACES}   ${iface}: ${IP}\n" && INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
        done < <(ifconfig -s 2>/dev/null | tail -n +2 | awk '{print $1}')
    fi

    [ -z "$NETWORK_INTERFACES" ] && NETWORK_INTERFACES="   No network interfaces detected"

    # Calculate Network Score
    if [ "$INTERFACE_COUNT" -eq 0 ]; then
        NETWORK_SCORE=0
    elif [ "$INTERFACE_COUNT" -eq 1 ]; then
        NETWORK_SCORE=5
    else
        NETWORK_SCORE=8
    fi
}

# Get System Information
get_system_info() {
    if [ -f /etc/os-release ]; then
        OS_NAME=$(grep "^PRETTY_NAME" /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        OS_NAME="Unknown Linux"
    fi

    KERNEL=$(uname -r 2>/dev/null || echo "Unknown")

    # Get uptime
    if [ -f /proc/uptime ]; then
        UPTIME_SECONDS=$(cut -d. -f1 /proc/uptime)
        UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
        UPTIME_HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
        UPTIME_MINS=$(((UPTIME_SECONDS % 3600) / 60))

        if [ "$UPTIME_DAYS" -gt 0 ]; then
            UPTIME="${UPTIME_DAYS} days, ${UPTIME_HOURS} hours"
        elif [ "$UPTIME_HOURS" -gt 0 ]; then
            UPTIME="${UPTIME_HOURS} hours, ${UPTIME_MINS} mins"
        else
            UPTIME="${UPTIME_MINS} mins"
        fi
    else
        UPTIME="Unknown"
    fi

    # Get load average
    if [ -f /proc/loadavg ]; then
        LOAD_AVG=$(cut -d' ' -f1-3 /proc/loadavg)
        LOAD_1MIN=$(echo "$LOAD_AVG" | awk '{print $1}')
    else
        LOAD_AVG="Unknown"
        LOAD_1MIN="0"
    fi

    # Calculate Health Score
    LOAD_NUM=$(echo "$LOAD_1MIN" | cut -d. -f1)
    [ -z "$LOAD_NUM" ] && LOAD_NUM=0

    if [ "$LOAD_NUM" -lt "$CPU_CORES" ] 2>/dev/null; then
        HEALTH_SCORE=10
    elif [ "$LOAD_NUM" -lt $((CPU_CORES * 2)) ] 2>/dev/null; then
        HEALTH_SCORE=7
    else
        HEALTH_SCORE=3
    fi
}

# Get Docker Information
get_docker_info() {
    DOCKER_VERSION="Not installed"
    DOCKER_CONTAINERS="N/A"

    if command_exists docker; then
        DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        DOCKER_RUNNING=$(docker ps -q 2>/dev/null | wc -l)
        DOCKER_TOTAL=$(docker ps -a -q 2>/dev/null | wc -l)
        DOCKER_CONTAINERS="${DOCKER_RUNNING}/${DOCKER_TOTAL} running"
    fi
}

# Calculate total score
calculate_score() {
    TOTAL_SCORE=$((CPU_SCORE + RAM_SCORE + DISK_SCORE + NETWORK_SCORE + HEALTH_SCORE))

    # Determine rating and color
    if [ "$TOTAL_SCORE" -le 30 ]; then
        SCORE_COLOR=$RED
        SCORE_RATING="Poor Performance Server"
    elif [ "$TOTAL_SCORE" -le 60 ]; then
        SCORE_COLOR=$YELLOW
        SCORE_RATING="Moderate Performance Server"
    elif [ "$TOTAL_SCORE" -le 85 ]; then
        SCORE_COLOR=$GREEN
        SCORE_RATING="Good Performance Server"
    else
        SCORE_COLOR=$CYAN
        SCORE_RATING="Excellent Performance Server"
    fi
}

# Create score bar
create_score_bar() {
    BAR_LENGTH=30
    FILLED=$((TOTAL_SCORE * BAR_LENGTH / 100))
    EMPTY=$((BAR_LENGTH - FILLED))

    SCORE_BAR="["
    for ((i=0; i<FILLED; i++)); do
        SCORE_BAR="${SCORE_BAR}█"
    done
    for ((i=0; i<EMPTY; i++)); do
        SCORE_BAR="${SCORE_BAR}░"
    done
    SCORE_BAR="${SCORE_BAR}]"
}

# Display information
display_info() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}          JACKER INFRASTRUCTURE - SYSTEM INFO             ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}🖥️  CPU Information:${NC}"
    echo -e "   Model: ${CPU_MODEL}"
    echo -e "   Cores: ${CPU_CORES} cores, ${CPU_THREADS} threads"
    echo -e "   Frequency: ${CPU_FREQ}"
    echo -e "   Cache: ${CPU_CACHE}"
    echo ""

    echo -e "${MAGENTA}💾 Memory Information:${NC}"
    echo -e "   Total RAM: ${MEM_TOTAL_GB} GB"
    echo -e "   Available: ${MEM_AVAILABLE_GB} GB (${MEM_PERCENT}%)"
    echo -e "   Swap: ${SWAP_TOTAL_GB} GB"
    echo ""

    echo -e "${YELLOW}💿 Disk Information:${NC}"
    echo -e "   Total: ${DISK_TOTAL}"
    echo -e "   Available: ${DISK_AVAILABLE} (${DISK_PERCENT}% used)"
    echo -e "   Type: ${DISK_TYPE}"
    echo ""

    echo -e "${GREEN}🌐 Network Information:${NC}"
    echo -e "${NETWORK_INTERFACES}"
    echo ""

    echo -e "${CYAN}🐧 System Information:${NC}"
    echo -e "   OS: ${OS_NAME}"
    echo -e "   Kernel: ${KERNEL}"
    echo -e "   Uptime: ${UPTIME}"
    echo -e "   Load: ${LOAD_AVG}"
    echo ""

    echo -e "${BLUE}🐳 Docker Information:${NC}"
    echo -e "   Version: ${DOCKER_VERSION}"
    echo -e "   Containers: ${DOCKER_CONTAINERS}"
    echo ""

    echo -e "${BOLD}📊 PERFORMANCE SCORE: ${SCORE_COLOR}${TOTAL_SCORE}/100${NC}"
    echo -e "    ${SCORE_COLOR}${SCORE_BAR}${NC} ${SCORE_RATING}"
    echo ""

    # Show score breakdown (optional, for debugging)
    # echo -e "${NC}Score Breakdown: CPU=${CPU_SCORE}, RAM=${RAM_SCORE}, Disk=${DISK_SCORE}, Network=${NETWORK_SCORE}, Health=${HEALTH_SCORE}${NC}"
}

# Main execution
main() {
    get_cpu_info
    get_memory_info
    get_disk_info
    get_network_info
    get_system_info
    get_docker_info
    calculate_score
    create_score_bar
    display_info
}

# Run main function
main
