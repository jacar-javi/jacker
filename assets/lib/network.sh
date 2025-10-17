#!/usr/bin/env bash
#
# network.sh - Network detection and validation functions for Jacker
# Handles IP/DNS detection, validation, and network-related operations
#

# Source common functions if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${JACKER_VERSION:-}" ]; then
    # shellcheck source=./common.sh
    source "${SCRIPT_DIR}/common.sh"
fi

# ============================================================================
# IP Detection Functions
# ============================================================================

# Detect public IPv4 address
# Tries multiple reliable services to ensure robustness
# Returns: IPv4 address or empty string if all methods fail
detect_public_ip() {
    local ip=""
    local services=(
        "ifconfig.me"
        "icanhazip.com"
        "api.ipify.org"
        "ipinfo.io/ip"
        "checkip.amazonaws.com"
    )

    verbose "Detecting public IPv4 address..."

    # Try each service
    for service in "${services[@]}"; do
        verbose "Trying service: $service"
        ip=$(curl -4 -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]')

        # Validate IP format
        if [[ -n "$ip" ]] && validate_ip "$ip" &>/dev/null; then
            verbose "Detected IPv4: $ip (from $service)"
            echo "$ip"
            return 0
        fi
    done

    # Fallback: Try dig method
    if command -v dig &>/dev/null; then
        verbose "Trying dig method..."
        ip=$(dig +short myip.opendns.com @resolver1.opendns.com 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

        if [[ -n "$ip" ]] && validate_ip "$ip" &>/dev/null; then
            verbose "Detected IPv4: $ip (from dig)"
            echo "$ip"
            return 0
        fi
    fi

    verbose "Failed to detect public IPv4 address"
    return 1
}

# Detect public IPv6 address
# Returns: IPv6 address or empty string if not available/detection fails
detect_public_ipv6() {
    local ipv6=""
    local services=(
        "ifconfig.co"
        "icanhazip.com"
        "api6.ipify.org"
        "ipv6.icanhazip.com"
    )

    verbose "Detecting public IPv6 address..."

    # Try each service with IPv6
    for service in "${services[@]}"; do
        verbose "Trying service: $service"
        ipv6=$(curl -6 -s --connect-timeout 5 --max-time 10 "$service" 2>/dev/null | tr -d '[:space:]')

        # Validate IPv6 format
        if [[ -n "$ipv6" ]] && validate_ipv6 "$ipv6" &>/dev/null; then
            verbose "Detected IPv6: $ipv6 (from $service)"
            echo "$ipv6"
            return 0
        fi
    done

    # Fallback: Try dig method
    if command -v dig &>/dev/null; then
        verbose "Trying dig method for IPv6..."
        ipv6=$(dig +short AAAA myip.opendns.com @resolver1.opendns.com 2>/dev/null | grep ':' | head -1)

        if [[ -n "$ipv6" ]] && validate_ipv6 "$ipv6" &>/dev/null; then
            verbose "Detected IPv6: $ipv6 (from dig)"
            echo "$ipv6"
            return 0
        fi
    fi

    verbose "IPv6 not available or detection failed"
    return 1
}

# Get local private IP address
# Returns: Local IPv4 address or empty string
get_local_ip() {
    local ip=""

    # Try ip command (Linux)
    if command -v ip &>/dev/null; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi

    # Fallback: Try hostname command
    if [[ -z "$ip" ]] && command -v hostname &>/dev/null; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    # Fallback: Try ifconfig (legacy)
    if [[ -z "$ip" ]] && command -v ifconfig &>/dev/null; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1)
    fi

    if [[ -n "$ip" ]]; then
        verbose "Local IP: $ip"
        echo "$ip"
        return 0
    fi

    return 1
}

# ============================================================================
# DNS Resolution Functions
# ============================================================================

# Detect hostname from IP address (reverse DNS lookup)
# Args: $1 - IP address
# Returns: Hostname or empty string
detect_hostname_from_ip() {
    local ip="$1"
    local hostname=""

    if [[ -z "$ip" ]]; then
        error "IP address required for reverse DNS lookup"
        return 1
    fi

    verbose "Performing reverse DNS lookup for: $ip"

    # Try dig first
    if command -v dig &>/dev/null; then
        hostname=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//' | head -1)
    fi

    # Fallback: Try host command
    if [[ -z "$hostname" ]] && command -v host &>/dev/null; then
        hostname=$(host "$ip" 2>/dev/null | grep "domain name pointer" | awk '{print $5}' | sed 's/\.$//' | head -1)
    fi

    # Fallback: Try nslookup
    if [[ -z "$hostname" ]] && command -v nslookup &>/dev/null; then
        hostname=$(nslookup "$ip" 2>/dev/null | grep -E 'name\s*=' | awk '{print $NF}' | sed 's/\.$//' | head -1)
    fi

    if [[ -n "$hostname" ]]; then
        verbose "Reverse DNS result: $hostname"
        echo "$hostname"
        return 0
    fi

    verbose "No reverse DNS record found for: $ip"
    return 1
}

# Resolve DNS name to IP address
# Args: $1 - DNS hostname
#       $2 - Optional: record type (A, AAAA, default: A)
# Returns: IP address or empty string
resolve_dns_to_ip() {
    local dns="$1"
    local record_type="${2:-A}"
    local ip=""

    if [[ -z "$dns" ]]; then
        error "DNS hostname required"
        return 1
    fi

    verbose "Resolving DNS: $dns (type: $record_type)"

    # Try dig first
    if command -v dig &>/dev/null; then
        if [[ "$record_type" == "AAAA" ]]; then
            ip=$(dig +short AAAA "$dns" 2>/dev/null | grep ':' | head -1)
        else
            ip=$(dig +short A "$dns" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
    fi

    # Fallback: Try host command
    if [[ -z "$ip" ]] && command -v host &>/dev/null; then
        if [[ "$record_type" == "AAAA" ]]; then
            ip=$(host -t AAAA "$dns" 2>/dev/null | grep "has IPv6 address" | awk '{print $5}' | head -1)
        else
            ip=$(host -t A "$dns" 2>/dev/null | grep "has address" | awk '{print $4}' | head -1)
        fi
    fi

    # Fallback: Try nslookup
    if [[ -z "$ip" ]] && command -v nslookup &>/dev/null; then
        if [[ "$record_type" == "AAAA" ]]; then
            ip=$(nslookup -type=AAAA "$dns" 2>/dev/null | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' | grep ':' | head -1)
        else
            ip=$(nslookup "$dns" 2>/dev/null | grep -A1 "^Name:" | grep "Address:" | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        fi
    fi

    if [[ -n "$ip" ]]; then
        verbose "DNS resolved: $dns -> $ip"
        echo "$ip"
        return 0
    fi

    verbose "Failed to resolve DNS: $dns"
    return 1
}

# Resolve all IPs for a DNS name (both A and AAAA records)
# Args: $1 - DNS hostname
# Returns: List of IPs (one per line)
resolve_dns_all_ips() {
    local dns="$1"
    local ips=()

    if [[ -z "$dns" ]]; then
        error "DNS hostname required"
        return 1
    fi

    verbose "Resolving all IPs for: $dns"

    # Get IPv4 addresses
    if command -v dig &>/dev/null; then
        while IFS= read -r ip; do
            [[ -n "$ip" ]] && ips+=("$ip")
        done < <(dig +short A "$dns" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

        # Get IPv6 addresses
        while IFS= read -r ip; do
            [[ -n "$ip" ]] && ips+=("$ip")
        done < <(dig +short AAAA "$dns" 2>/dev/null | grep ':')
    fi

    if [[ ${#ips[@]} -gt 0 ]]; then
        printf '%s\n' "${ips[@]}"
        return 0
    fi

    return 1
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate IPv4 address format
# Args: $1 - IP address to validate
# Returns: 0 if valid, 1 if invalid
validate_ip() {
    local ip="$1"

    # Check basic format
    if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        verbose "Invalid IPv4 format: $ip"
        return 1
    fi

    # Check each octet
    local IFS='.'
    local -a octets
    read -ra octets <<< "$ip"

    for octet in "${octets[@]}"; do
        # Check for leading zeros (except single 0)
        if [[ "$octet" =~ ^0[0-9]+ ]]; then
            verbose "Invalid IPv4 (leading zero): $ip"
            return 1
        fi

        # Check range
        if [[ $octet -lt 0 ]] || [[ $octet -gt 255 ]]; then
            verbose "Invalid IPv4 (octet out of range): $ip"
            return 1
        fi
    done

    return 0
}

# Validate IPv6 address format
# Args: $1 - IPv6 address to validate
# Returns: 0 if valid, 1 if invalid
validate_ipv6() {
    local ipv6="$1"

    # Basic IPv6 format check (simplified)
    if [[ "$ipv6" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ipv6" =~ ^::([0-9a-fA-F]{0,4}:){0,6}[0-9a-fA-F]{0,4}$ ]] || \
       [[ "$ipv6" =~ ^([0-9a-fA-F]{0,4}:){1,6}:$ ]] || \
       [[ "$ipv6" == "::" ]]; then
        return 0
    fi

    verbose "Invalid IPv6 format: $ipv6"
    return 1
}

# Validate CIDR notation (IPv4 or IPv6)
# Args: $1 - CIDR (e.g., 192.168.1.0/24 or 2001:db8::/32)
# Returns: 0 if valid, 1 if invalid
validate_cidr() {
    local cidr="$1"

    # Split IP and prefix
    local ip="${cidr%/*}"
    local prefix="${cidr#*/}"

    # Check if CIDR notation is used
    if [[ "$ip" == "$prefix" ]]; then
        verbose "Invalid CIDR (missing prefix): $cidr"
        return 1
    fi

    # Validate prefix is a number
    if [[ ! "$prefix" =~ ^[0-9]+$ ]]; then
        verbose "Invalid CIDR (prefix not numeric): $cidr"
        return 1
    fi

    # Check if IPv4 or IPv6
    if [[ "$ip" =~ \. ]]; then
        # IPv4
        if ! validate_ip "$ip"; then
            return 1
        fi

        if [[ $prefix -lt 0 ]] || [[ $prefix -gt 32 ]]; then
            verbose "Invalid CIDR (IPv4 prefix out of range): $cidr"
            return 1
        fi
    else
        # IPv6
        if ! validate_ipv6 "$ip"; then
            return 1
        fi

        if [[ $prefix -lt 0 ]] || [[ $prefix -gt 128 ]]; then
            verbose "Invalid CIDR (IPv6 prefix out of range): $cidr"
            return 1
        fi
    fi

    return 0
}

# Validate hostname format (RFC 1123)
# Args: $1 - Hostname to validate
# Returns: 0 if valid, 1 if invalid
validate_hostname() {
    local hostname="$1"

    # Check length
    if [[ ${#hostname} -gt 253 ]]; then
        verbose "Invalid hostname (too long): $hostname"
        return 1
    fi

    # Check format: alphanumeric and hyphens, no hyphen at start/end
    # Can have multiple labels separated by dots
    if [[ "$hostname" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        return 0
    fi

    verbose "Invalid hostname format: $hostname"
    return 1
}

# Validate DNS name (hostname or FQDN)
# Args: $1 - DNS name to validate
# Returns: 0 if valid, 1 if invalid
validate_dns_name() {
    local dns="$1"

    # DNS name can be a hostname or FQDN
    # Must end with a TLD for FQDN
    if validate_hostname "$dns"; then
        return 0
    fi

    # Check if it's a valid FQDN (must have at least one dot and valid TLD)
    if [[ "$dns" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 0
    fi

    verbose "Invalid DNS name: $dns"
    return 1
}

# Check if IP is private/local
# Args: $1 - IP address
# Returns: 0 if private, 1 if public
is_private_ip() {
    local ip="$1"

    # Validate IP first
    if ! validate_ip "$ip" &>/dev/null; then
        return 1
    fi

    # Extract first two octets
    local first_octet="${ip%%.*}"
    local remaining="${ip#*.}"
    local second_octet="${remaining%%.*}"

    # Check private ranges
    # 10.0.0.0/8
    if [[ $first_octet -eq 10 ]]; then
        return 0
    fi

    # 172.16.0.0/12
    if [[ $first_octet -eq 172 ]] && [[ $second_octet -ge 16 ]] && [[ $second_octet -le 31 ]]; then
        return 0
    fi

    # 192.168.0.0/16
    if [[ $first_octet -eq 192 ]] && [[ $second_octet -eq 168 ]]; then
        return 0
    fi

    # 127.0.0.0/8 (loopback)
    if [[ $first_octet -eq 127 ]]; then
        return 0
    fi

    # Public IP
    return 1
}

# ============================================================================
# Network Testing Functions
# ============================================================================

# Check if a host:port is reachable
# Args: $1 - Host (IP or hostname)
#       $2 - Port
#       $3 - Optional: Timeout in seconds (default: 5)
# Returns: 0 if reachable, 1 if not
test_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    if [[ -z "$host" ]] || [[ -z "$port" ]]; then
        error "Host and port required"
        return 1
    fi

    verbose "Testing connectivity to $host:$port (timeout: ${timeout}s)"

    # Try nc (netcat)
    if command -v nc &>/dev/null; then
        if nc -z -w "$timeout" "$host" "$port" &>/dev/null; then
            verbose "Port $host:$port is reachable (nc)"
            return 0
        fi
    fi

    # Try timeout + bash tcp
    if command -v timeout &>/dev/null; then
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" &>/dev/null; then
            verbose "Port $host:$port is reachable (bash tcp)"
            return 0
        fi
    fi

    # Try telnet
    if command -v telnet &>/dev/null; then
        if echo "quit" | timeout "$timeout" telnet "$host" "$port" &>/dev/null; then
            verbose "Port $host:$port is reachable (telnet)"
            return 0
        fi
    fi

    verbose "Port $host:$port is not reachable"
    return 1
}

# Check if host responds to ping
# Args: $1 - Host (IP or hostname)
#       $2 - Optional: Count (default: 1)
# Returns: 0 if reachable, 1 if not
test_ping() {
    local host="$1"
    local count="${2:-1}"

    if [[ -z "$host" ]]; then
        error "Host required"
        return 1
    fi

    verbose "Pinging $host (count: $count)"

    if ping -c "$count" -W 5 "$host" &>/dev/null; then
        verbose "Host $host is reachable (ping)"
        return 0
    fi

    verbose "Host $host is not reachable (ping)"
    return 1
}

# ============================================================================
# Utility Functions
# ============================================================================

# Get network interface information
# Returns: List of network interfaces with IPs
get_network_interfaces() {
    verbose "Getting network interfaces..."

    if command -v ip &>/dev/null; then
        ip -brief addr show | grep -v "^lo " | awk '{print $1 " - " $3}'
    elif command -v ifconfig &>/dev/null; then
        ifconfig | grep -E "^[a-z]|inet " | grep -v "127.0.0.1" | sed 's/://g' | awk '/^[a-z]/{iface=$1} /inet /{print iface " - " $2}'
    else
        error "No network interface command available (ip or ifconfig)"
        return 1
    fi
}

# Detect if running in cloud environment
# Returns: Cloud provider name or "local"
detect_cloud_provider() {
    local provider="local"

    # AWS
    if curl -s --connect-timeout 1 --max-time 2 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
        provider="aws"
    fi

    # GCP
    if curl -s --connect-timeout 1 --max-time 2 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/ &>/dev/null; then
        provider="gcp"
    fi

    # Azure
    if curl -s --connect-timeout 1 --max-time 2 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 &>/dev/null; then
        provider="azure"
    fi

    # DigitalOcean
    if curl -s --connect-timeout 1 --max-time 2 http://169.254.169.254/metadata/v1/ &>/dev/null; then
        provider="digitalocean"
    fi

    echo "$provider"
}

# Get geolocation info for IP
# Args: $1 - IP address (optional, defaults to current public IP)
# Returns: JSON with location info
get_ip_geolocation() {
    local ip="${1:-}"
    local response=""

    # If no IP provided, get current public IP
    if [[ -z "$ip" ]]; then
        ip=$(detect_public_ip)
    fi

    if [[ -z "$ip" ]]; then
        error "No IP address provided or detected"
        return 1
    fi

    verbose "Getting geolocation for: $ip"

    # Use ipinfo.io API
    response=$(curl -s --connect-timeout 5 --max-time 10 "https://ipinfo.io/${ip}/json" 2>/dev/null)

    if [[ -n "$response" ]]; then
        echo "$response"
        return 0
    fi

    return 1
}

# ============================================================================
# Export Functions
# ============================================================================

export -f detect_public_ip detect_public_ipv6 get_local_ip
export -f detect_hostname_from_ip resolve_dns_to_ip resolve_dns_all_ips
export -f validate_ip validate_ipv6 validate_cidr validate_hostname validate_dns_name
export -f is_private_ip test_port test_ping
export -f get_network_interfaces detect_cloud_provider get_ip_geolocation
