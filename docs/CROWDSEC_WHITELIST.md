# CrowdSec IP/DNS Whitelisting Guide

## Overview

Jacker includes comprehensive CrowdSec whitelisting capabilities to prevent your admin IPs from being blocked. This guide covers all aspects of managing your whitelist.

## Table of Contents

- [Quick Start](#quick-start)
- [CLI Commands](#cli-commands)
- [Configuration](#configuration)
- [Workflow](#workflow)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## Quick Start

### During Jacker Init

The easiest way to whitelist your IP is during the initial setup:

```bash
./jacker init
```

During initialization, Jacker will:
1. Auto-detect your current public IP
2. Prompt you to whitelist it
3. Optionally whitelist dynamic DNS names
4. Optionally whitelist additional IPs/networks

### After Installation

If you need to whitelist your IP after installation:

```bash
# Interactive wizard
./jacker whitelist add

# Or add directly
./jacker whitelist add 203.0.113.10 "My home IP"
```

---

## CLI Commands

### Add Entries

```bash
# Interactive wizard (recommended for first-time users)
./jacker whitelist add

# Add a specific IP
./jacker whitelist add 203.0.113.10

# Add a specific IP with description
./jacker whitelist add 203.0.113.10 "Home IP"

# Add a CIDR range
./jacker whitelist add 198.51.100.0/24 "Office network"

# Add a DNS name (will be resolved to IPs)
./jacker whitelist add home.dyndns.org "Dynamic DNS"
```

### List Whitelist

```bash
# Show current whitelist
./jacker whitelist list
```

### Remove Entries

```bash
# Remove an IP or CIDR
./jacker whitelist remove 203.0.113.10
```

### Test Whitelist

```bash
# Check if your current IP is whitelisted
./jacker whitelist current
```

### Import/Export

```bash
# Import IPs from a file
./jacker whitelist import /path/to/ips.txt

# Export whitelist to a file
./jacker whitelist export /path/to/backup.txt
```

###Apply Changes

```bash
# Restart CrowdSec to apply changes
./jacker whitelist reload
```

### Maintenance

```bash
# Validate whitelist configuration
./jacker whitelist validate

# Clean up duplicates and invalid entries
./jacker whitelist cleanup

# Initialize/reset whitelist file
./jacker whitelist init
```

---

## Configuration

### File Location

The whitelist configuration is stored at:

```
config/crowdsec/parsers/s02-enrich/jacker-whitelist.yaml
```

### Manual Configuration

You can also edit the whitelist file manually:

```yaml
name: jacker/admin-whitelist
description: "Whitelist for Jacker admin IPs and DNS names"

whitelist:
  reason: "Jacker admin access"

  # Individual IP addresses
  ip:
    - "203.0.113.10"  # Home IP
    - "198.51.100.42"  # Office IP

  # CIDR ranges
  cidr:
    - "198.51.100.0/24"  # Office network
    - "10.8.0.0/24"      # VPN network

  # Expression-based rules
  expression:
    - "evt.Meta.reverse_dns == 'home.example.com'"
```

After manual edits, restart CrowdSec:

```bash
./jacker whitelist reload
```

---

## Workflow

### 1. Detect Your IP

```bash
# Jacker's network library can detect your public IP
./jacker whitelist add
# Will auto-detect and prompt to add your IP
```

### 2. Add to Whitelist

Choose one of these methods:

**Interactive (Recommended)**
```bash
./jacker whitelist add
```

**Direct**
```bash
./jacker whitelist add $(curl -s ifconfig.me) "My current IP"
```

### 3. Verify

```bash
# Check if you're whitelisted
./jacker whitelist current

# View whitelist
./jacker whitelist list
```

### 4. Apply Changes

```bash
./jacker whitelist reload
```

---

## Best Practices

### 1. Whitelist Conservatively

Only whitelist IPs you control:
- Your home/office static IPs
- Your VPN exit IPs
- Known admin endpoints

**Avoid** whitelisting:
- Entire cloud provider ranges
- Public proxy/VPN services
- Unnecessarily broad CIDR ranges

### 2. Use Dynamic DNS for Dynamic IPs

If your home IP changes frequently:

```bash
# Set up dynamic DNS (e.g., DuckDNS, No-IP, DynDNS)
# Then whitelist the DNS name
./jacker whitelist add home.dyndns.org

# Jacker will resolve it to current IPs
```

###3. Document Your Entries

Always add descriptions:

```bash
./jacker whitelist add 203.0.113.10 "John's home IP - expires 2025-06"
./jacker whitelist add 198.51.100.0/24 "Company VPN network"
```

### 4. Regular Audits

Periodically review your whitelist:

```bash
# List all entries
./jacker whitelist list

# Remove outdated entries
./jacker whitelist remove <old-ip>

# Clean up invalid entries
./jacker whitelist cleanup
```

### 5. Backup Your Whitelist

```bash
# Export before major changes
./jacker whitelist export whitelist-backup-$(date +%Y%m%d).txt
```

### 6. Test After Changes

```bash
# Verify you're still whitelisted
./jacker whitelist current

# Check CrowdSec logs
./jacker logs crowdsec --tail 50
```

---

## Troubleshooting

### Issue: Can't Access Services After Enabling CrowdSec

**Solution:**

```bash
# Check if you're whitelisted
./jacker whitelist current

# If not, add your IP
./jacker whitelist add

# Apply changes
./jacker whitelist reload
```

### Issue: Whitelist Not Working

**Diagnosis:**

```bash
# 1. Verify whitelist file exists
ls -la config/crowdsec/parsers/s02-enrich/jacker-whitelist.yaml

# 2. Validate syntax
./jacker whitelist validate

# 3. Check CrowdSec logs
./jacker logs crowdsec --tail 100 | grep whitelist

# 4. Verify CrowdSec is running
./jacker status | grep crowdsec
```

**Solutions:**

```bash
# Reinitialize whitelist
./jacker whitelist init

# Restart CrowdSec
./jacker whitelist reload

# Check for syntax errors
./jacker whitelist validate
```

### Issue: IP Still Getting Blocked

**Diagnosis:**

```bash
# Check current decisions
docker compose exec crowdsec cscli decisions list

# Check your current IP
curl -s ifconfig.me

# Check whitelist
./jacker whitelist list
```

**Solutions:**

```bash
# Unban your IP
docker compose exec crowdsec cscli decisions delete --ip $(curl -s ifconfig.me)

# Add to whitelist
./jacker whitelist add $(curl -s ifconfig.me)

# Reload CrowdSec
./jacker whitelist reload
```

### Issue: Dynamic DNS Not Resolving

**Diagnosis:**

```bash
# Test DNS resolution
dig +short home.dyndns.org

# Check if IPs are in whitelist
./jacker whitelist list
```

**Solutions:**

```bash
# Remove old DNS entry
./jacker whitelist remove home.dyndns.org

# Re-add (will resolve to new IP)
./jacker whitelist add home.dyndns.org

# Reload
./jacker whitelist reload
```

---

## Advanced Usage

### Import Multiple IPs from File

Create a file `ips.txt`:

```
# Admin IPs
203.0.113.10
203.0.113.11

# Office network
198.51.100.0/24

# VPN network
10.8.0.0/24

# Dynamic DNS
home.dyndns.org
```

Import:

```bash
./jacker whitelist import ips.txt
./jacker whitelist reload
```

### Expression-Based Whitelisting

For advanced filtering, edit the whitelist file manually:

```yaml
expression:
  # Whitelist by reverse DNS
  - "evt.Meta.reverse_dns == 'myserver.example.com'"

  # Whitelist multiple domains
  - "evt.Meta.reverse_dns in ['home.example.com', 'office.example.com']"

  # Whitelist by user agent (for HTTP)
  - "evt.Meta.http_user_agent startsWith 'MyMonitoringTool'"

  # Complex conditions
  - "evt.Meta.source_ip == '203.0.113.10' && evt.Meta.http_path == '/admin'"
```

### Automated Whitelisting in CI/CD

```bash
# Non-interactive mode
export JACKER_AUTO_MODE=true

# During init
./jacker init --auto

# Or manually
CURRENT_IP=$(curl -s ifconfig.me)
./jacker whitelist add "$CURRENT_IP" "CI/CD runner"
./jacker whitelist reload
```

### Network-Specific Whitelists

For complex setups with multiple networks:

```yaml
# File: config/crowdsec/parsers/s02-enrich/office-whitelist.yaml
name: jacker/office-whitelist
description: "Office network whitelist"
whitelist:
  reason: "Office access"
  cidr:
    - "198.51.100.0/24"

# File: config/crowdsec/parsers/s02-enrich/vpn-whitelist.yaml
name: jacker/vpn-whitelist
description: "VPN network whitelist"
whitelist:
  reason: "VPN access"
  cidr:
    - "10.8.0.0/24"
```

### Integration with External IP Management

```bash
#!/bin/bash
# update-whitelist.sh - Cron job to update whitelist

# Get current IP
CURRENT_IP=$(curl -s ifconfig.me)

# Check if already whitelisted
if ! ./jacker whitelist list | grep -q "$CURRENT_IP"; then
    echo "IP changed to $CURRENT_IP, updating whitelist..."
    ./jacker whitelist add "$CURRENT_IP" "Auto-updated on $(date)"
    ./jacker whitelist reload
else
    echo "IP $CURRENT_IP already whitelisted"
fi
```

Add to crontab:

```bash
# Check every hour
0 * * * * /path/to/update-whitelist.sh
```

---

## Security Considerations

### 1. Don't Whitelist Broadly

❌ **Bad:**
```bash
./jacker whitelist add 0.0.0.0/0  # Whitelists everyone!
```

✅ **Good:**
```bash
./jacker whitelist add 203.0.113.10  # Specific IP
./jacker whitelist add 198.51.100.0/24  # Small network
```

### 2. Regular Audits

Schedule monthly whitelist reviews:

```bash
# Review whitelist
./jacker whitelist list

# Remove old/unused entries
./jacker whitelist remove <ip>

# Clean up
./jacker whitelist cleanup
```

### 3. Monitor CrowdSec Decisions

```bash
# Check recent blocks
docker compose exec crowdsec cscli decisions list

# If you see your IP
docker compose exec crowdsec cscli decisions delete --ip <your-ip>
./jacker whitelist add <your-ip>
./jacker whitelist reload
```

### 4. Backup Whitelist Configuration

```bash
# Include in your backup strategy
./jacker backup --with-volumes

# Or export specifically
./jacker whitelist export "whitelist-backup-$(date +%Y%m%d).txt"
```

---

## Reference

### Whitelist File Format

Full YAML structure:

```yaml
name: "jacker/admin-whitelist"          # Unique identifier
description: "Description of whitelist"  # Human-readable description

# Optional: Filter which events this whitelist applies to
filter: "evt.Meta.service == 'http'"

whitelist:
  reason: "Brief reason for whitelisting"  # Mandatory field

  ip:                                    # Individual IPs
    - "203.0.113.10"
    - "198.51.100.42"

  cidr:                                  # CIDR ranges
    - "192.168.1.0/24"
    - "10.0.0.0/8"

  expression:                            # Advanced expressions
    - "evt.Meta.reverse_dns == 'admin.example.com'"
```

### Available Expression Fields

Common fields for expressions:

- `evt.Meta.source_ip` - Source IP address
- `evt.Meta.reverse_dns` - Reverse DNS hostname
- `evt.Meta.http_verb` - HTTP method (GET, POST, etc.)
- `evt.Meta.http_path` - HTTP request path
- `evt.Meta.http_user_agent` - User-Agent header
- `evt.Meta.service` - Service name (http, ssh, etc.)
- `evt.Meta.log_type` - Log type

### CLI Command Reference

| Command | Description |
|---------|-------------|
| `jacker whitelist add [ip]` | Add IP/CIDR (interactive if no IP) |
| `jacker whitelist remove <ip>` | Remove from whitelist |
| `jacker whitelist list` | Show current whitelist |
| `jacker whitelist init` | Initialize whitelist file |
| `jacker whitelist reload` | Restart CrowdSec |
| `jacker whitelist current` | Test current IP |
| `jacker whitelist import <file>` | Import from file |
| `jacker whitelist export [file]` | Export to file |
| `jacker whitelist validate` | Validate configuration |
| `jacker whitelist cleanup` | Remove duplicates/invalid |

---

## Support

For more information:

- **CrowdSec Docs:** https://docs.crowdsec.net/docs/whitelist/create/
- **Jacker Issues:** https://github.com/yourusername/jacker/issues
- **CrowdSec Forum:** https://discourse.crowdsec.net/

---

## Examples

### Example 1: Home User with Dynamic IP

```bash
# Set up DuckDNS or similar
# Then whitelist the DNS name
./jacker whitelist add home.mydomain.duckdns.org "Home dynamic DNS"
./jacker whitelist reload
```

### Example 2: Office Network

```bash
# Whitelist office network range
./jacker whitelist add 198.51.100.0/24 "Office network"
./jacker whitelist reload
```

### Example 3: Multiple Admins

Create `admin-ips.txt`:

```
203.0.113.10  # Alice
203.0.113.11  # Bob
203.0.113.12  # Charlie
```

Import:

```bash
./jacker whitelist import admin-ips.txt
./jacker whitelist reload
```

### Example 4: Whitelist VPN and Office

```bash
# VPN network
./jacker whitelist add 10.8.0.0/24 "Company VPN"

# Office network
./jacker whitelist add 198.51.100.0/24 "Office network"

# Reload
./jacker whitelist reload

# Verify
./jacker whitelist list
```

---

**Note:** Always test your whitelist configuration after making changes to ensure you maintain access to your services.
