#!/usr/bin/env bash
#
# whitelist.sh - Interactive whitelist wizard for Jacker
# Provides user-friendly interface for configuring CrowdSec whitelisting
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

# Source CrowdSec functions
if [ -z "$(type -t crowdsec_whitelist_ip 2>/dev/null)" ]; then
    # shellcheck source=./crowdsec.sh
    source "${SCRIPT_DIR}/crowdsec.sh"
fi

# ============================================================================
# Interactive Whitelist Configuration Wizard
# ============================================================================

# Main interactive whitelist configuration wizard
# Called during Jacker initialization to configure admin access whitelist
# Args: $1 - Optional: Jacker root directory
#       $2 - Optional: Auto mode (true/false)
configure_admin_whitelist() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local auto_mode="${2:-false}"
    local changes_made=false

    section "Admin IP/DNS Whitelisting"

    echo "To prevent CrowdSec from blocking your admin access,"
    echo "you should whitelist your IP address or DNS name."
    echo ""
    echo "This ensures that even if you trigger security rules,"
    echo "you won't be locked out of your Jacker infrastructure."
    echo ""

    # Initialize whitelist file
    init_crowdsec_whitelist "$jacker_root" || {
        error "Failed to initialize whitelist"
        return 1
    }

    # ========================================================================
    # Auto-detect and whitelist current public IP
    # ========================================================================
    subsection "Current Public IP Detection"

    local detected_ip
    detected_ip=$(detect_public_ip 2>/dev/null)

    if [[ -n "$detected_ip" ]]; then
        success "Detected public IP: $detected_ip"

        # Check if already whitelisted
        if crowdsec_is_whitelisted "$detected_ip" "$jacker_root" 2>/dev/null; then
            info "This IP is already whitelisted"
        else
            # Auto mode or prompt user
            if [[ "$auto_mode" == "true" ]]; then
                info "Auto mode: Adding IP to whitelist"
                if crowdsec_whitelist_ip "$detected_ip" "Admin IP (auto-detected)" "$jacker_root"; then
                    changes_made=true
                fi
            else
                echo ""
                if confirm_action "Whitelist this IP address?" "Y"; then
                    if crowdsec_whitelist_ip "$detected_ip" "Admin IP (auto-detected)" "$jacker_root"; then
                        changes_made=true
                    fi
                fi
            fi
        fi
    else
        warning "Could not auto-detect public IP"
        info "You can add your IP manually below"
    fi

    # Skip interactive prompts in auto mode
    if [[ "$auto_mode" == "true" ]]; then
        info "Auto mode: Skipping additional whitelist configuration"

        if [[ "$changes_made" == "true" ]]; then
            crowdsec_restart "$jacker_root"
        fi

        return 0
    fi

    # ========================================================================
    # Optional: Add Dynamic DNS name
    # ========================================================================
    echo ""
    subsection "Dynamic DNS Whitelisting"

    echo "If you use a dynamic DNS service (e.g., DynDNS, No-IP, Duck DNS),"
    echo "you can whitelist your DNS hostname. This is useful if your IP"
    echo "changes frequently but your DNS name stays the same."
    echo ""

    if confirm_action "Do you want to whitelist a DNS name?" "N"; then
        echo ""
        local dns_name
        dns_name=$(prompt_with_default "Enter DNS hostname (e.g., home.dyndns.org)" "")

        if [[ -n "$dns_name" ]]; then
            if validate_hostname "$dns_name" || validate_dns_name "$dns_name"; then
                if crowdsec_whitelist_dns "$dns_name" "Admin DNS (dynamic)" "$jacker_root"; then
                    changes_made=true
                fi
            else
                error "Invalid DNS name format: $dns_name"
            fi
        fi
    fi

    # ========================================================================
    # Optional: Add additional manual IPs
    # ========================================================================
    echo ""
    subsection "Additional IP Addresses"

    echo "You can add additional IP addresses or CIDR ranges to the whitelist."
    echo "This is useful for:"
    echo "  - Office/VPN static IPs"
    echo "  - Team member IPs"
    echo "  - Monitoring service IPs"
    echo "  - Backup admin IPs"
    echo ""

    if confirm_action "Add additional IP addresses or CIDR ranges?" "N"; then
        while true; do
            echo ""
            local manual_entry
            manual_entry=$(prompt_with_default "Enter IP or CIDR (or 'done' to finish)" "done")

            # Check if user wants to finish
            if [[ "$manual_entry" == "done" ]] || [[ -z "$manual_entry" ]]; then
                break
            fi

            # Validate and add entry
            if validate_ip "$manual_entry" || validate_cidr "$manual_entry"; then
                local entry_reason
                entry_reason=$(prompt_with_default "Enter description/reason" "Manual entry")

                if crowdsec_whitelist_ip "$manual_entry" "$entry_reason" "$jacker_root"; then
                    changes_made=true
                fi
            else
                error "Invalid IP or CIDR format: $manual_entry"
                echo "Examples:"
                echo "  - Single IP: 203.0.113.42"
                echo "  - CIDR range: 198.51.100.0/24"
            fi
        done
    fi

    # ========================================================================
    # Optional: Import from file
    # ========================================================================
    echo ""
    subsection "Import Whitelist from File"

    echo "You can import multiple IPs/CIDRs from a text file"
    echo "(one entry per line, comments starting with # are ignored)"
    echo ""

    if confirm_action "Import whitelist entries from a file?" "N"; then
        echo ""
        local import_file
        import_file=$(prompt_with_default "Enter file path" "")

        if [[ -n "$import_file" ]] && [[ -f "$import_file" ]]; then
            if crowdsec_import_whitelist "$import_file" "Imported entry" "$jacker_root"; then
                changes_made=true
            fi
        elif [[ -n "$import_file" ]]; then
            error "File not found: $import_file"
        fi
    fi

    # ========================================================================
    # Show final whitelist
    # ========================================================================
    echo ""
    subsection "Current Whitelist Configuration"

    crowdsec_show_whitelist "$jacker_root"

    # ========================================================================
    # Apply changes
    # ========================================================================
    if [[ "$changes_made" == "true" ]]; then
        echo ""
        info "Whitelist configuration has been updated"

        if confirm_action "Restart CrowdSec to apply changes now?" "Y"; then
            crowdsec_restart "$jacker_root"
        else
            warning "Changes will take effect after CrowdSec restart"
            info "To apply changes later, run: jacker whitelist reload"
        fi
    else
        info "No changes were made to the whitelist"
    fi

    echo ""
    success "Admin whitelist configuration complete"
    echo ""
    info "You can manage the whitelist anytime with:"
    echo "  jacker whitelist add <ip>     - Add IP/CIDR to whitelist"
    echo "  jacker whitelist remove <ip>  - Remove from whitelist"
    echo "  jacker whitelist list         - Show current whitelist"
    echo "  jacker whitelist reload       - Reload CrowdSec configuration"
    echo ""

    return 0
}

# ============================================================================
# Quick Whitelist Functions
# ============================================================================

# Quick add IP to whitelist (non-interactive)
# Args: $1 - IP or CIDR
#       $2 - Optional: Reason
#       $3 - Optional: Auto-restart CrowdSec (true/false, default: false)
quick_whitelist_add() {
    local entry="$1"
    local reason="${2:-Quick add}"
    local auto_restart="${3:-false}"
    local jacker_root
    jacker_root=$(get_jacker_root)

    if [[ -z "$entry" ]]; then
        error "IP address or CIDR required"
        echo "Usage: quick_whitelist_add <ip|cidr> [reason] [auto-restart]"
        return 1
    fi

    # Initialize whitelist if needed
    init_crowdsec_whitelist "$jacker_root" || return 1

    # Add entry
    if crowdsec_whitelist_ip "$entry" "$reason" "$jacker_root"; then
        if [[ "$auto_restart" == "true" ]]; then
            crowdsec_restart "$jacker_root"
        else
            info "Restart CrowdSec to apply changes: jacker whitelist reload"
        fi
        return 0
    else
        return 1
    fi
}

# Quick remove IP from whitelist (non-interactive)
# Args: $1 - IP or CIDR
#       $2 - Optional: Auto-restart CrowdSec (true/false, default: false)
quick_whitelist_remove() {
    local entry="$1"
    local auto_restart="${2:-false}"
    local jacker_root
    jacker_root=$(get_jacker_root)

    if [[ -z "$entry" ]]; then
        error "IP address or CIDR required"
        echo "Usage: quick_whitelist_remove <ip|cidr> [auto-restart]"
        return 1
    fi

    # Remove entry
    if crowdsec_remove_from_whitelist "$entry" "$jacker_root"; then
        if [[ "$auto_restart" == "true" ]]; then
            crowdsec_restart "$jacker_root"
        else
            info "Restart CrowdSec to apply changes: jacker whitelist reload"
        fi
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Whitelist Validation and Testing
# ============================================================================

# Validate whitelist configuration file
# Args: $1 - Optional: Jacker root directory
# Returns: 0 if valid, 1 if invalid
validate_whitelist_config() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_file
    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        error "Whitelist file not found: $whitelist_file"
        return 1
    fi

    info "Validating whitelist configuration..."

    # Check YAML syntax (if yamllint is available)
    if command -v yamllint &>/dev/null; then
        if yamllint -d relaxed "$whitelist_file" &>/dev/null; then
            success "YAML syntax is valid"
        else
            error "YAML syntax errors found"
            yamllint -d relaxed "$whitelist_file"
            return 1
        fi
    else
        verbose "yamllint not available, skipping YAML validation"
    fi

    # Check for required fields
    if ! grep -q "^name:" "$whitelist_file"; then
        error "Missing 'name' field in whitelist"
        return 1
    fi

    if ! grep -q "^whitelist:" "$whitelist_file"; then
        error "Missing 'whitelist' section"
        return 1
    fi

    # Validate IP entries
    local invalid_count=0
    while IFS= read -r line; do
        # Extract IP from line (remove quotes, comments, etc.)
        local ip
        ip=$(echo "$line" | sed 's/^.*- "\(.*\)".*$/\1/' | sed 's/#.*//' | xargs)

        if [[ -n "$ip" ]]; then
            if ! validate_ip "$ip" &>/dev/null && ! validate_cidr "$ip" &>/dev/null; then
                warning "Invalid IP/CIDR entry: $ip"
                ((invalid_count++))
            fi
        fi
    done < <(grep -A 100 "^  ip:\|^  cidr:" "$whitelist_file" | grep "^    -")

    if [[ $invalid_count -gt 0 ]]; then
        error "Found $invalid_count invalid IP/CIDR entries"
        return 1
    fi

    success "Whitelist configuration is valid"
    return 0
}

# Test if current IP would be whitelisted
# Returns: 0 if whitelisted, 1 if not
test_current_ip_whitelist() {
    local jacker_root
    jacker_root=$(get_jacker_root)

    local current_ip
    current_ip=$(detect_public_ip 2>/dev/null)

    if [[ -z "$current_ip" ]]; then
        error "Could not detect current public IP"
        return 1
    fi

    info "Current public IP: $current_ip"

    if crowdsec_is_whitelisted "$current_ip" "$jacker_root"; then
        success "Your current IP is whitelisted"
        return 0
    else
        warning "Your current IP is NOT whitelisted"
        echo ""
        echo "Add it with: jacker whitelist add $current_ip"
        return 1
    fi
}

# ============================================================================
# Whitelist Cleanup and Maintenance
# ============================================================================

# Remove duplicate entries from whitelist
# Args: $1 - Optional: Jacker root directory
cleanup_whitelist_duplicates() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_file
    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        error "Whitelist file not found: $whitelist_file"
        return 1
    fi

    info "Removing duplicate entries from whitelist..."

    # Backup current whitelist
    backup_crowdsec_whitelist "$jacker_root"

    # Use awk to remove duplicates while preserving order
    local temp_file="${whitelist_file}.tmp"

    awk '
        /^    -/ {
            if (!seen[$0]++) print
            next
        }
        { print }
    ' "$whitelist_file" > "$temp_file"

    mv "$temp_file" "$whitelist_file"

    success "Duplicate entries removed"
    return 0
}

# Remove invalid entries from whitelist
# Args: $1 - Optional: Jacker root directory
cleanup_whitelist_invalid() {
    local jacker_root="${1:-$(get_jacker_root)}"
    local whitelist_file
    whitelist_file=$(get_crowdsec_whitelist_file "$jacker_root")

    if [[ ! -f "$whitelist_file" ]]; then
        error "Whitelist file not found: $whitelist_file"
        return 1
    fi

    info "Removing invalid entries from whitelist..."

    # Backup current whitelist
    backup_crowdsec_whitelist "$jacker_root"

    local temp_file="${whitelist_file}.tmp"
    local removed_count=0

    # Process file line by line
    while IFS= read -r line; do
        # Check if line is an IP/CIDR entry
        if [[ "$line" =~ ^[[:space:]]*- ]]; then
            # Extract IP/CIDR
            local entry
            entry=$(echo "$line" | sed 's/^.*- "\(.*\)".*$/\1/' | sed 's/#.*//' | xargs)

            # Validate
            if [[ -n "$entry" ]] && (validate_ip "$entry" &>/dev/null || validate_cidr "$entry" &>/dev/null); then
                echo "$line" >> "$temp_file"
            else
                warning "Removing invalid entry: $entry"
                ((removed_count++))
            fi
        else
            # Keep non-entry lines as-is
            echo "$line" >> "$temp_file"
        fi
    done < "$whitelist_file"

    mv "$temp_file" "$whitelist_file"

    if [[ $removed_count -gt 0 ]]; then
        success "Removed $removed_count invalid entries"
    else
        info "No invalid entries found"
    fi

    return 0
}

# ============================================================================
# Export Functions
# ============================================================================

export -f configure_admin_whitelist
export -f quick_whitelist_add quick_whitelist_remove
export -f validate_whitelist_config test_current_ip_whitelist
export -f cleanup_whitelist_duplicates cleanup_whitelist_invalid
