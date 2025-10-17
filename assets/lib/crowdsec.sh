#!/usr/bin/env bash
#
# crowdsec.sh - CrowdSec management and whitelist functions for Jacker
# Handles CrowdSec configuration, whitelist management, and security operations
#

# Source common functions if not already loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${JACKER_VERSION:-}" ]; then
    # shellcheck source=./common.sh
    source "${SCRIPT_DIR}/common.sh"
fi

# Source network functions
if [ -z "$(type -t detect_public_ip 2>/dev/null)" ]; then
    # shellcheck source=./network.sh
    source "${SCRIPT_DIR}/network.sh"
fi

# ============================================================================
# CrowdSec Configuration Paths
# ============================================================================

# Get CrowdSec whitelist directory
get_crowdsec_whitelist_dir() {
    local jacker_root="${1:-$(get_jacker_root)}"
    echo "${jacker_root}/config/crowdsec/parsers/s02-enrich"
}

# Get CrowdSec whitelist file path
get_crowdsec_whitelist_file() {
    local jacker_root="${1:-$(get_jacker_root)}"
    echo "$(get_crowdsec_whitelist_dir "$jacker_root")/jacker-whitelist.yaml"
}

# ============================================================================
# Whitelist File Management
# ============================================================================

# Initialize CrowdSec whitelist file if it doesn't exist
# Creates the directory structure and base whitelist file
init_crowdsec_whitelist() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_dir
    local whitelist_file

    whitelist_dir=$(get_crowdsec_whitelist_dir "$jacker_root")
    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    verbose "Initializing CrowdSec whitelist: $whitelist_file"

    # Create directory if it doesn't exist
    if ! ensure_dir "$whitelist_dir"; then
        error "Failed to create whitelist directory: $whitelist_dir"
        return 1
    fi

    # Create base whitelist file if it doesn't exist
    if [[ ! -f "$whitelist_file" ]]; then
        cat > "$whitelist_file" <<'EOF'
# ====================================================================
# Jacker Admin Whitelist Configuration
# ====================================================================
# This file whitelists admin IPs and DNS names to prevent CrowdSec
# from blocking legitimate admin access.
#
# Documentation: https://docs.crowdsec.net/docs/whitelist/create/
#
# After modifying this file, restart CrowdSec:
#   docker compose restart crowdsec
# ====================================================================

name: jacker/admin-whitelist
description: "Whitelist for Jacker admin IPs and DNS names"

whitelist:
  reason: "Jacker admin access"

  # Individual IP addresses
  ip: []

  # CIDR ranges (e.g., 192.168.1.0/24)
  cidr: []

  # Expression-based rules for advanced filtering
  expression: []
EOF
        success "Created CrowdSec whitelist file: $whitelist_file"
    else
        verbose "Whitelist file already exists: $whitelist_file"
    fi

    return 0
}

# Backup current whitelist file
backup_crowdsec_whitelist() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_file
    local backup_file

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        verbose "No whitelist file to backup"
        return 0
    fi

    backup_file="${whitelist_file}.backup-$(date +%Y%m%d-%H%M%S)"

    if cp "$whitelist_file" "$backup_file"; then
        success "Backed up whitelist: $backup_file"
        return 0
    else
        error "Failed to backup whitelist"
        return 1
    fi
}

# ============================================================================
# Whitelist Entry Management
# ============================================================================

# Add IP address to CrowdSec whitelist
# Args: $1 - IP address or CIDR
#       $2 - Optional: Reason/description
#       $3 - Optional: Jacker root directory
crowdsec_whitelist_ip() {
    local entry="$1"
    local reason="${2:-Admin IP}"
    local jacker_root="${3:-$(get_jacker_root)}"
    local whitelist_file
    local entry_type="ip"

    if [[ -z "$entry" ]]; then
        error "IP address or CIDR required"
        return 1
    fi

    # Validate entry
    if validate_cidr "$entry" &>/dev/null; then
        entry_type="cidr"
        verbose "Adding CIDR to whitelist: $entry"
    elif validate_ip "$entry" &>/dev/null; then
        entry_type="ip"
        verbose "Adding IP to whitelist: $entry"
    else
        error "Invalid IP address or CIDR format: $entry"
        return 1
    fi

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    # Initialize whitelist if needed
    if [[ ! -f "$whitelist_file" ]]; then
        init_crowdsec_whitelist "$jacker_root" || return 1
    fi

    # Check if entry already exists
    if grep -qE "^  - ['\"]?${entry}['\"]?" "$whitelist_file" 2>/dev/null; then
        info "Entry already in whitelist: $entry"
        return 0
    fi

    # Backup current whitelist
    backup_crowdsec_whitelist "$jacker_root"

    # Add entry to appropriate section
    if [[ "$entry_type" == "cidr" ]]; then
        # Add to CIDR section
        if grep -q "^  cidr: \[\]" "$whitelist_file"; then
            # Convert empty array to list and add entry
            sed -i "s/^  cidr: \[\]/  cidr:\n    - \"${entry}\"  # ${reason}/" "$whitelist_file"
        else
            # Add to existing CIDR list
            sed -i "/^  cidr:/a\    - \"${entry}\"  # ${reason}" "$whitelist_file"
        fi
    else
        # Add to IP section
        if grep -q "^  ip: \[\]" "$whitelist_file"; then
            # Convert empty array to list and add entry
            sed -i "s/^  ip: \[\]/  ip:\n    - \"${entry}\"  # ${reason}/" "$whitelist_file"
        else
            # Add to existing IP list
            sed -i "/^  ip:/a\    - \"${entry}\"  # ${reason}" "$whitelist_file"
        fi
    fi

    success "Added to whitelist: $entry ($reason)"
    return 0
}

# Add DNS name to CrowdSec whitelist (as expression)
# Args: $1 - DNS hostname
#       $2 - Optional: Reason/description
#       $3 - Optional: Jacker root directory
crowdsec_whitelist_dns() {
    local dns="$1"
    local reason="${2:-Admin DNS}"
    local jacker_root="${3:-$(get_jacker_root)}"
    local whitelist_file

    if [[ -z "$dns" ]]; then
        error "DNS hostname required"
        return 1
    fi

    # Validate DNS
    if ! validate_hostname "$dns" && ! validate_dns_name "$dns"; then
        error "Invalid DNS hostname format: $dns"
        return 1
    fi

    verbose "Adding DNS to whitelist: $dns"

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    # Initialize whitelist if needed
    if [[ ! -f "$whitelist_file" ]]; then
        init_crowdsec_whitelist "$jacker_root" || return 1
    fi

    # Resolve DNS to IPs and add them
    info "Resolving DNS: $dns"
    local ips
    ips=$(resolve_dns_all_ips "$dns" 2>/dev/null)

    if [[ -z "$ips" ]]; then
        warning "Could not resolve DNS: $dns"
        info "Adding DNS as expression-based rule instead"

        # Add as expression for reverse DNS matching
        local expression="evt.Meta.reverse_dns == \"${dns}\""

        # Backup current whitelist
        backup_crowdsec_whitelist "$jacker_root"

        # Add expression
        if grep -q "^  expression: \[\]" "$whitelist_file"; then
            sed -i "s/^  expression: \[\]/  expression:\n    - \"${expression}\"  # ${reason}/" "$whitelist_file"
        else
            sed -i "/^  expression:/a\    - \"${expression}\"  # ${reason}" "$whitelist_file"
        fi

        success "Added DNS expression to whitelist: $dns"
        return 0
    fi

    # Add each resolved IP
    local ip_count=0
    while IFS= read -r ip; do
        if [[ -n "$ip" ]]; then
            crowdsec_whitelist_ip "$ip" "${reason} (resolved from ${dns})" "$jacker_root"
            ((ip_count++))
        fi
    done <<< "$ips"

    success "Added $ip_count IP(s) from DNS: $dns"
    return 0
}

# Remove entry from CrowdSec whitelist
# Args: $1 - Entry to remove (IP, CIDR, or expression)
#       $2 - Optional: Jacker root directory
crowdsec_remove_from_whitelist() {
    local entry="$1"
    local jacker_root="${2:-$(get_jacker_root)}"
    local whitelist_file

    if [[ -z "$entry" ]]; then
        error "Entry required"
        return 1
    fi

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        error "Whitelist file not found: $whitelist_file"
        return 1
    fi

    verbose "Removing from whitelist: $entry"

    # Check if entry exists
    if ! grep -qE "^  - ['\"]?${entry}['\"]?" "$whitelist_file" 2>/dev/null; then
        warning "Entry not found in whitelist: $entry"
        return 1
    fi

    # Backup current whitelist
    backup_crowdsec_whitelist "$jacker_root"

    # Remove entry (and the comment on the same line)
    sed -i "/^  - ['\"]${entry}['\"]/d" "$whitelist_file"
    sed -i "/^  - ${entry}$/d" "$whitelist_file"

    success "Removed from whitelist: $entry"
    return 0
}

# ============================================================================
# Whitelist Display and Query
# ============================================================================

# Show current whitelist
# Args: $1 - Optional: Jacker root directory
crowdsec_show_whitelist() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_file

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        warning "No whitelist file found"
        info "Initialize whitelist with: jacker whitelist init"
        return 1
    fi

    echo ""
    info "CrowdSec Whitelist Configuration"
    echo "=================================="
    echo ""

    # Extract and display IPs
    echo "IP Addresses:"
    if grep -A 100 "^  ip:" "$whitelist_file" | grep -E "^    -" | head -20; then
        echo ""
    else
        echo "  (none)"
        echo ""
    fi

    # Extract and display CIDRs
    echo "CIDR Ranges:"
    if grep -A 100 "^  cidr:" "$whitelist_file" | grep -E "^    -" | head -20; then
        echo ""
    else
        echo "  (none)"
        echo ""
    fi

    # Extract and display expressions
    echo "Expression Rules:"
    if grep -A 100 "^  expression:" "$whitelist_file" | grep -E "^    -" | head -20; then
        echo ""
    else
        echo "  (none)"
        echo ""
    fi

    echo "File: $whitelist_file"
    echo ""

    return 0
}

# Check if an IP is whitelisted
# Args: $1 - IP address to check
#       $2 - Optional: Jacker root directory
# Returns: 0 if whitelisted, 1 if not
crowdsec_is_whitelisted() {
    local ip="$1"
    local jacker_root="${2:-$(get_jacker_root)}"
    local whitelist_file

    if [[ -z "$ip" ]]; then
        error "IP address required"
        return 1
    fi

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        return 1
    fi

    # Check if IP is directly listed
    if grep -qE "^  - ['\"]?${ip}['\"]?" "$whitelist_file" 2>/dev/null; then
        return 0
    fi

    # TODO: Check if IP is within any CIDR range (would require CIDR calculation)
    # For now, just check exact matches

    return 1
}

# ============================================================================
# CrowdSec Service Management
# ============================================================================

# Restart CrowdSec service to apply whitelist changes
# Args: $1 - Optional: Jacker root directory
crowdsec_restart() {
    local jacker_root="${1:-$(get_jacker_root)}"

    info "Restarting CrowdSec to apply whitelist changes..."

    cd "$jacker_root" || return 1

    if docker compose restart crowdsec; then
        success "CrowdSec restarted successfully"

        # Wait for CrowdSec to be healthy
        info "Waiting for CrowdSec to be healthy..."
        sleep 5

        if wait_for_healthy "crowdsec" 60 2 2>/dev/null; then
            success "CrowdSec is healthy"
        else
            warning "CrowdSec may not be fully ready yet"
        fi

        return 0
    else
        error "Failed to restart CrowdSec"
        return 1
    fi
}

# Reload CrowdSec configuration without restart (if possible)
# Args: $1 - Optional: Jacker root directory
crowdsec_reload() {
    local jacker_root="${1:-$(get_jacker_root)}"

    info "Reloading CrowdSec configuration..."

    cd "$jacker_root" || return 1

    # Send HUP signal to reload (if container supports it)
    if docker compose exec crowdsec kill -HUP 1 2>/dev/null; then
        success "CrowdSec configuration reloaded"
        return 0
    else
        warning "Could not reload CrowdSec, performing restart instead"
        crowdsec_restart "$jacker_root"
        return $?
    fi
}

# ============================================================================
# CrowdSec CLI Integration
# ============================================================================

# Execute cscli command in CrowdSec container
# Args: $@ - cscli command and arguments
crowdsec_cli() {
    local jacker_root
    jacker_root=$(get_jacker_root)

    cd "$jacker_root" || return 1

    if ! is_container_running "crowdsec"; then
        error "CrowdSec container is not running"
        return 1
    fi

    verbose "Executing cscli: $*"
    docker compose exec -T crowdsec cscli "$@"
}

# List CrowdSec decisions (bans)
crowdsec_list_decisions() {
    info "Current CrowdSec decisions (active bans):"
    echo ""
    crowdsec_cli decisions list
}

# Check if an IP is currently banned
# Args: $1 - IP address
# Returns: 0 if banned, 1 if not banned
crowdsec_is_banned() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        error "IP address required"
        return 1
    fi

    if crowdsec_cli decisions list -i "$ip" 2>/dev/null | grep -q "$ip"; then
        return 0
    fi

    return 1
}

# Unban an IP address
# Args: $1 - IP address
crowdsec_unban() {
    local ip="$1"

    if [[ -z "$ip" ]]; then
        error "IP address required"
        return 1
    fi

    info "Unbanning IP: $ip"

    if crowdsec_cli decisions delete -i "$ip"; then
        success "Unbanned IP: $ip"
        return 0
    else
        error "Failed to unban IP: $ip"
        return 1
    fi
}

# ============================================================================
# Whitelist Management Helpers
# ============================================================================

# Add current public IP to whitelist
# Args: $1 - Optional: Reason
#       $2 - Optional: Jacker root directory
crowdsec_whitelist_current_ip() {
    local reason="${1:-Current public IP}"
    local jacker_root="${2:-$(get_jacker_root)}"
    local public_ip

    info "Detecting current public IP..."
    public_ip=$(detect_public_ip)

    if [[ -z "$public_ip" ]]; then
        error "Could not detect public IP"
        return 1
    fi

    info "Detected public IP: $public_ip"
    crowdsec_whitelist_ip "$public_ip" "$reason" "$jacker_root"
}

# Import whitelist entries from file
# Args: $1 - File containing IPs/CIDRs (one per line)
#       $2 - Optional: Reason
#       $3 - Optional: Jacker root directory
crowdsec_import_whitelist() {
    local import_file="$1"
    local reason="${2:-Imported entry}"
    local jacker_root="${3:-$(get_jacker_root)}"
    local count=0

    if [[ ! -f "$import_file" ]]; then
        error "Import file not found: $import_file"
        return 1
    fi

    info "Importing whitelist entries from: $import_file"

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        line=$(echo "$line" | xargs)

        # Try to add as IP/CIDR
        if validate_ip "$line" &>/dev/null || validate_cidr "$line" &>/dev/null; then
            if crowdsec_whitelist_ip "$line" "$reason" "$jacker_root"; then
                ((count++))
            fi
        # Try to add as DNS
        elif validate_hostname "$line" &>/dev/null || validate_dns_name "$line" &>/dev/null; then
            if crowdsec_whitelist_dns "$line" "$reason" "$jacker_root"; then
                ((count++))
            fi
        else
            warning "Skipping invalid entry: $line"
        fi
    done < "$import_file"

    success "Imported $count entries from: $import_file"
    return 0
}

# Export whitelist entries to file
# Args: $1 - Output file path
#       $2 - Optional: Jacker root directory
crowdsec_export_whitelist() {
    local output_file="$1"
    local jacker_root="${2:-$(get_jacker_root)}"
    local whitelist_file

    if [[ -z "$output_file" ]]; then
        error "Output file path required"
        return 1
    fi

    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        error "Whitelist file not found: $whitelist_file"
        return 1
    fi

    info "Exporting whitelist to: $output_file"

    # Extract all IPs, CIDRs, and expressions
    {
        echo "# CrowdSec Whitelist Export - $(date)"
        echo "# Generated from: $whitelist_file"
        echo ""
        grep -A 100 "^  ip:" "$whitelist_file" | grep -E "^    -" | sed 's/^    - "\(.*\)".*/\1/'
        grep -A 100 "^  cidr:" "$whitelist_file" | grep -E "^    -" | sed 's/^    - "\(.*\)".*/\1/'
    } > "$output_file"

    success "Exported whitelist to: $output_file"
    return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f get_crowdsec_whitelist_dir get_crowdsec_whitelist_file
export -f init_crowdsec_whitelist backup_crowdsec_whitelist
export -f crowdsec_whitelist_ip crowdsec_whitelist_dns crowdsec_remove_from_whitelist
export -f crowdsec_show_whitelist crowdsec_is_whitelisted
export -f crowdsec_restart crowdsec_reload
export -f crowdsec_cli crowdsec_list_decisions crowdsec_is_banned crowdsec_unban
export -f crowdsec_whitelist_current_ip crowdsec_import_whitelist crowdsec_export_whitelist
