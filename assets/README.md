# Jacker Assets Directory

This directory contains libraries, templates, and supporting files for the Jacker platform. Most functionality has been unified into the main `jacker` CLI command.

## 📋 Table of Contents

- [Unified Jacker CLI](#unified-jacker-cli)
- [Library Modules (lib/)](#library-modules-lib)
- [Templates](#templates)
- [Legacy Scripts](#legacy-scripts)

---

## Unified Jacker CLI

**As of v3.0.0, all primary functionality has been consolidated into the `jacker` command:**

```bash
# Core Commands
./jacker init           # Initialize Jacker (replaces setup.sh)
./jacker start          # Start services
./jacker stop           # Stop services
./jacker restart        # Restart services
./jacker status         # Show service status
./jacker logs <service> # View service logs
./jacker shell <service># Access service shell

# Management Commands
./jacker health         # Run health checks (replaces health-check.sh)
./jacker fix [issue]    # Fix common issues (replaces fix-*.sh scripts)
./jacker backup         # Create backup (replaces backup.sh)
./jacker restore <file> # Restore from backup (replaces restore.sh)
./jacker update         # Update Jacker and services (replaces update.sh)
./jacker clean          # Clean up containers and data (replaces clean.sh)

# Configuration Commands
./jacker config         # Manage configuration
./jacker secrets        # Manage secrets (replaces rotate-secrets.sh)
./jacker security       # Security operations

# For help
./jacker help           # Show all commands
./jacker <command> --help  # Show command-specific help
```

---

## Library Modules (lib/)

The lib/ directory contains reusable functions that power the unified jacker CLI. These libraries are not intended for direct use but are sourced by the main jacker command.

### 📚 lib/common.sh
**Core Utility Functions**
- Color output (success, error, warning, info)
- Logging functions
- Environment variable loading
- Path detection and validation
- User input prompts
- Directory creation helpers
- File permission management

### 📦 lib/setup.sh
**Installation and Configuration**
- Interactive setup wizard
- Auto-detection of system settings
- Configuration file generation
- Service initialization

### ⚙️ lib/config.sh
**Configuration Management**
- Show/set configuration values
- OAuth configuration
- Domain configuration
- SSL certificate management
- Authentik setup

### 🔐 lib/security.sh
**Security Operations**
- Secrets management
- CrowdSec operations
- Firewall management
- Security scanning

### 🏥 lib/monitoring.sh
**Health and Monitoring**
- Health checks
- Service status monitoring
- Performance metrics
- Diagnostics

### 💾 lib/maintenance.sh
**Maintenance Operations**
- Backup creation
- Restore from backup
- System updates
- Cleanup operations

### 🔧 lib/fixes.sh
**Problem Resolution**
- Loki permissions fixes
- Traefik certificate fixes
- CrowdSec database fixes
- PostgreSQL fixes
- Network fixes

---

## Templates

The templates/ directory contains configuration file templates with variable substitution.

### Configuration Templates
- `alertmanager.yml.template` - Alertmanager notification configuration
- `config.yaml.local.template` - CrowdSec local configuration
- `loki-config.yml.template` - Loki log aggregation settings
- `middlewares-oauth.template` - Traefik OAuth middleware
- `promtail-config.yml.template` - Promtail log collection config

### CrowdSec Templates
- `crowdsec-acquis.yaml` - Log source definitions for CrowdSec
- `crowdsec-custom-whitelists.yaml` - IP whitelist configuration
- `crowdsec-firewall-bouncer.yaml.template` - Firewall bouncer config

### Systemd Templates
- `jacker-compose.service.template` - Main Jacker systemd service
- `jacker-compose-reload.service.template` - Auto-reload service
- `jacker-compose-reload.timer.template` - Reload timer configuration

### Template Usage

Templates use `envsubst` for variable replacement:
```bash
envsubst < templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
```

Variables are loaded from the .env file.

---

## Legacy Scripts

Some standalone scripts remain for specific purposes or backward compatibility:

### Setup Scripts
- `setup-authentik.sh` - Configure Authentik authentication (called by `jacker config authentik`)
- `setup-crowdsec-db.sh` - Initialize CrowdSec database (called during `jacker init`)
- `disable-oauth-for-testing.sh` - Temporarily disable OAuth (development only)

### Fix Scripts
These are now integrated into `jacker fix` but remain for direct access:
- `fix-loki-permissions.sh` - Fix Loki directory permissions
- `fix-traefik-acme.sh` - Fix Traefik ACME certificate
- `fix-promtail-labels.sh` - Fix Promtail label cardinality
- `fix-crowdsec-postgres.sh` - Fix CrowdSec database issues
- `fix-postgres-password-mismatch.sh` - Sync PostgreSQL passwords
- `fix-alertmanager.sh` - Fix Alertmanager configuration

### Utility Scripts
- `register_bouncers.sh` - Register CrowdSec bouncers
- `resize_container_shm.sh` - Resize container shared memory
- `migrate-crowdsec-plugin.sh` - Migrate to CrowdSec Traefik plugin

### Diagnostic Scripts
- `check-jacker-config.sh` - Validate configuration (now in `jacker config validate`)
- `check-postgres-state.sh` - Check PostgreSQL state

---

## Migration Guide

If you're upgrading from an older version of Jacker:

### Old Command → New Command

| Old Command | New Command |
|-------------|-------------|
| `./assets/setup.sh` | `./jacker init` |
| `make install` | `./jacker init` |
| `make start` | `./jacker start` |
| `make stop` | `./jacker stop` |
| `make restart` | `./jacker restart` |
| `make status` | `./jacker status` |
| `make logs` | `./jacker logs` |
| `make health` | `./jacker health` |
| `make backup` | `./jacker backup` |
| `make update` | `./jacker update` |
| `make clean` | `./jacker clean` |
| `./assets/backup.sh` | `./jacker backup` |
| `./assets/restore.sh` | `./jacker restore` |
| `./assets/health-check.sh` | `./jacker health` |
| `./assets/rotate-secrets.sh` | `./jacker secrets rotate` |
| `./assets/fix-*.sh` | `./jacker fix [component]` |

### Makefile Compatibility

The Makefile remains as a thin wrapper for backward compatibility:
```bash
make install  # Calls: ./jacker init
make start    # Calls: ./jacker start
make health   # Calls: ./jacker health
# etc...
```

---

## Development Guidelines

### Script Conventions

All scripts follow these conventions:

1. **Shebang and Options**
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   ```

2. **Script Location Detection**
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   JACKER_ROOT="$(dirname "$SCRIPT_DIR")"
   ```

3. **Library Loading**
   ```bash
   source "$SCRIPT_DIR/lib/common.sh"
   ```

4. **Error Handling**
   ```bash
   error() { echo -e "${RED}✗ $*${NC}" >&2; }
   success() { echo -e "${GREEN}✓ $*${NC}"; }
   ```

### Color Coding

- 🔴 **Red** - Errors and critical issues
- 🟢 **Green** - Success messages
- 🟡 **Yellow** - Warnings
- 🔵 **Blue** - Info messages
- 🟣 **Magenta** - Prompts

### Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid usage
- `130` - User cancelled (Ctrl+C)

---

## Related Documentation

- [Main README](../README.md) - Project overview and quick start
- [compose/README.md](../compose/README.md) - Service documentation
- [config/README.md](../config/README.md) - Configuration management
- [data/README.md](../data/README.md) - Runtime data documentation
- [secrets/README.md](../secrets/README.md) - Secrets management

---

**Last Updated:** 2025-10-12
**Jacker Version:** 3.0.0 (Unified CLI)