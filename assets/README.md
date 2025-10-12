# Jacker Assets Directory

This directory contains all scripts, libraries, and templates for the Jacker platform. Scripts are organized into core operations (setup, maintenance, diagnostics) and modular libraries.

## 📋 Table of Contents

- [Main Scripts](#main-scripts)
- [Setup & Configuration](#setup--configuration)
- [Maintenance & Operations](#maintenance--operations)
- [Diagnostics & Health](#diagnostics--health)
- [Fix Scripts](#fix-scripts)
- [Library Modules (lib/)](#library-modules-lib)
- [Templates](#templates)
- [Script Conventions](#script-conventions)

---

## Main Scripts

### 🚀 setup.sh
**Primary Installation Script**

- **Purpose:** Orchestrates the complete Jacker installation process
- **Usage:** `./assets/setup.sh` or `make install`
- **Description:** The main setup script that guides users through Jacker installation. Supports two modes: Quick Setup (minimal prompts, auto-configuration) and Advanced Setup (full customization). Handles system preparation, Docker installation, directory creation, service configuration, and initial deployment. Includes first_round (pre-reboot) and second_round (post-reboot) phases for complete installation.
- **Key Features:**
  - Interactive mode selection (Quick/Advanced)
  - Auto-detection of system settings (hostname, timezone, PUID/PGID)
  - Environment file generation from templates
  - UFW firewall configuration (optional)
  - PostgreSQL and CrowdSec setup
  - OAuth or Authentik authentication configuration
- **Dependencies:** lib/common.sh, lib/system.sh, lib/services.sh

### 📦 stack.sh
**Stack Management CLI**

- **Purpose:** Browse, install, and manage Docker application stacks
- **Usage:** `./assets/stack.sh [command]` or `make stacks`
- **Description:** Command-line interface for managing additional application stacks beyond core Jacker services. Discovers stacks from configured repositories, handles installation/uninstallation, and integrates with systemd for service management. Replaces the old jacker-stack and stack-manager tools.
- **Commands:**
  - `list` - List available stacks from all repositories
  - `search <query>` - Search for stacks by name
  - `info <stack>` - Show detailed stack information
  - `install <stack>` - Install a stack to the system
  - `uninstall <stack>` - Remove an installed stack
  - `installed` - List all installed stacks
  - `repos` - List configured repositories
  - `repo-add <url>` - Add a new stack repository
  - `repo-remove <name>` - Remove a repository
  - `systemd-*` - Systemd service management commands
- **Dependencies:** lib/common.sh, lib/stacks.sh

### 🔄 update.sh
**System Update Script**

- **Purpose:** Updates Jacker, Docker images, and installed stacks
- **Usage:** `./assets/update.sh` or `make update`
- **Description:** Performs a complete system update including pulling latest Jacker code from git, updating all Docker images, recreating containers with new images, and updating any installed stacks. Backs up configurations before updating and can restore on failure.
- **Update Process:**
  1. Create backup of current configuration
  2. Pull latest changes from git
  3. Pull updated Docker images
  4. Recreate containers with new images
  5. Update installed stacks (if any)
  6. Clean up unused images
- **Safety:** Creates backup before updating, maintains `.env` configuration

---

## Setup & Configuration

### 🔑 setup-authentik.sh
**Authentik Authentication Setup**

- **Purpose:** Configure Authentik as an alternative to Google OAuth
- **Usage:** `./assets/setup-authentik.sh`
- **Description:** Automated setup script for Authentik identity provider. Generates required secrets (AUTHENTIK_SECRET_KEY, AUTHENTIK_POSTGRES_PASSWORD), updates .env file, enables Authentik service in docker-compose.yml, creates necessary directories, and starts Authentik services. Use when you need advanced authentication features like MFA, LDAP integration, or self-hosted SSO.
- **What it does:**
  - Generates secure secrets for Authentik
  - Adds Authentik variables to .env
  - Uncomments compose/authentik.yml inclusion
  - Creates data directories
  - Initializes Authentik database
  - Starts Authentik services
- **Documentation:** See jacker-docs/docs/guides/authentik.md

### 🗄️ setup-crowdsec-db.sh
**CrowdSec Database Setup**

- **Purpose:** Initialize PostgreSQL database for CrowdSec
- **Usage:** `./assets/setup-crowdsec-db.sh`
- **Description:** Creates and configures the PostgreSQL database required by CrowdSec. Verifies PostgreSQL is running, creates the crowdsec_db database if it doesn't exist, creates the crowdsec user with appropriate permissions, and tests the connection. Automatically called by setup.sh during installation.
- **Performs:**
  - PostgreSQL availability check
  - Database creation (crowdsec_db)
  - User creation with password
  - Permission grants
  - Connection verification

### 🔧 disable-oauth-for-testing.sh
**OAuth Bypass for Testing**

- **Purpose:** Temporarily disable OAuth authentication for testing/debugging
- **Usage:** `./assets/disable-oauth-for-testing.sh`
- **Description:** Modifies Traefik middleware configuration to bypass OAuth authentication, allowing direct access to services without Google login. Useful for local development, testing, or troubleshooting authentication issues. Updates middlewares-oauth.yml to use no-auth chain instead of OAuth forward-auth.
- **Warning:** Only use in development/testing environments. Re-enable OAuth before production use.
- **Reversal:** Re-run setup.sh or manually restore middlewares-oauth.yml

---

## Maintenance & Operations

### 💾 backup.sh
**Backup Configuration and Data**

- **Purpose:** Create complete backup of Jacker configuration and data
- **Usage:** `./assets/backup.sh` or `make backup`
- **Description:** Creates timestamped backup archives of critical Jacker components including .env configuration, Docker Compose files, Traefik rules and certificates, service data directories, and custom configurations. Stores backups in the backups/ directory with date-stamped filenames.
- **Backup Includes:**
  - .env configuration file
  - docker-compose.yml and all compose/*.yml files
  - data/traefik/ (rules, certificates)
  - data/crowdsec/config/
  - data/grafana/provisioning/
  - Custom scripts and configurations
- **Format:** tar.gz archives with timestamp
- **Dependencies:** lib/backup.sh

### 🔄 restore.sh
**Restore from Backup**

- **Purpose:** Restore Jacker configuration and data from backup
- **Usage:** `./assets/restore.sh <backup-file>`
- **Description:** Restores a previous Jacker backup, extracting the archive and copying files back to their original locations. Stops services before restoration, restores files, and restarts services. Useful for disaster recovery, rolling back changes, or migrating to a new server.
- **Process:**
  1. Stop all services
  2. Extract backup archive
  3. Restore configuration files
  4. Restore data directories
  5. Restart services
  6. Verify restoration
- **Safety:** Creates backup of current state before restoring

### 🧹 clean.sh
**Clean Up Installation**

- **Purpose:** Remove all Jacker containers, volumes, and data
- **Usage:** `./assets/clean.sh` or `make clean`
- **Description:** **DANGEROUS** - Completely removes the Jacker installation including stopping and removing all containers, deleting all volumes and data, removing networks, and cleaning up configuration files. Use for fresh reinstall or complete removal. Prompts for confirmation before proceeding.
- **Removes:**
  - All Docker containers
  - All Docker volumes (data loss!)
  - Docker networks
  - data/ directory contents
  - logs/ directory
- **Warning:** This is destructive and irreversible. Backup first!

### 🔐 rotate-secrets.sh
**Rotate Security Secrets**

- **Purpose:** Generate new secrets for enhanced security
- **Usage:** `./assets/rotate-secrets.sh`
- **Description:** Regenerates security-critical secrets including PostgreSQL passwords, CrowdSec API keys, OAuth secrets, and other credentials. Useful for security hardening, post-breach response, or periodic security maintenance. Updates .env and restarts affected services.
- **Rotates:**
  - PostgreSQL passwords
  - CrowdSec Local API key
  - CrowdSec Bouncer keys
  - OAuth client secrets (requires manual Google update)
  - Session encryption keys
- **Process:** Generates new secrets, updates configs, restarts services

### 🔗 register_bouncers.sh
**Register CrowdSec Bouncers**

- **Purpose:** Register CrowdSec bouncers with the Local API
- **Usage:** `./assets/register_bouncers.sh`
- **Description:** Registers Traefik bouncer and firewall bouncer with CrowdSec's Local API, generating API keys for communication. Required when setting up new bouncers or after CrowdSec reinstallation. Outputs bouncer API keys for configuration.

### 📏 resize_container_shm.sh
**Resize Container Shared Memory**

- **Purpose:** Increase /dev/shm size for containers that need it
- **Usage:** `./assets/resize_container_shm.sh <container-name> <size>`
- **Description:** Some containers (browsers, databases) require larger shared memory (/dev/shm) than Docker's default 64MB. This script modifies container configuration to increase shm size. Useful for preventing "out of shared memory" errors.
- **Example:** `./assets/resize_container_shm.sh postgres 256m`

---

## Diagnostics & Health

### ✅ health-check.sh
**System Health Diagnostics**

- **Purpose:** Comprehensive health check of Jacker installation
- **Usage:** `./assets/health-check.sh` or `make health`
- **Description:** Performs detailed diagnostics of the entire Jacker stack including container status, service connectivity, volume permissions, network configuration, and endpoint accessibility. Generates a health report with actionable recommendations for fixing issues.
- **Checks:**
  - Container status (running/stopped/unhealthy)
  - Service health endpoints
  - Network connectivity
  - Volume permissions (especially Loki)
  - Configuration file validity
  - SSL certificate status
  - Database connectivity
  - CrowdSec status
  - Traefik routing
- **Output:** Color-coded report with pass/fail indicators
- **Dependencies:** lib/health-check.sh

### 🔍 check-jacker-config.sh
**Configuration Validation**

- **Purpose:** Validate Jacker configuration for common issues
- **Usage:** `./assets/check-jacker-config.sh`
- **Description:** Analyzes .env configuration file and system setup to identify common configuration problems including missing OAuth credentials, invalid domain names, placeholder values, missing Let's Encrypt email, and configuration mismatches. Provides specific recommendations for fixing each issue found.
- **Validates:**
  - OAuth credentials (CLIENT_ID, CLIENT_SECRET, WHITELIST)
  - Domain configuration (PUBLIC_FQDN, DOMAINNAME)
  - Let's Encrypt email
  - File permissions (acme.json)
  - Directory structure
  - Required secrets files
  - Environment variable completeness
- **Output:** Detailed report with warnings and fix suggestions

### 🔗 check-postgres-state.sh
**PostgreSQL State Check**

- **Purpose:** Verify PostgreSQL database configuration and connectivity
- **Usage:** `./assets/check-postgres-state.sh`
- **Description:** Checks PostgreSQL container status, database existence, user permissions, and connectivity. Useful for troubleshooting CrowdSec database connection issues. Reports on all PostgreSQL-related configuration and provides diagnostic information.
- **Checks:**
  - PostgreSQL container running
  - crowdsec_db database exists
  - crowdsec user exists and has permissions
  - Connection with configured credentials
  - Environment variable consistency
  - CrowdSec database configuration

### 🧪 test.sh
**Automated Test Suite**

- **Purpose:** Run automated tests for Jacker components
- **Usage:** `./assets/test.sh` or `make test`
- **Description:** Executes the comprehensive test suite including unit tests for library functions, integration tests for scripts, and end-to-end tests for services. Uses BATS (Bash Automated Testing System) framework. Reports test results with coverage metrics.
- **Test Categories:**
  - Unit tests (lib/ functions)
  - Integration tests (script workflows)
  - Service tests (container health)
  - Configuration tests (validation)
- **Framework:** BATS with support libraries
- **Results:** TAP output with pass/fail summary

---

## Fix Scripts

### 🔧 fix-crowdsec-postgres.sh
**Fix CrowdSec PostgreSQL Connection**

- **Purpose:** Resolve CrowdSec database connection issues
- **Description:** Diagnoses and fixes common CrowdSec PostgreSQL problems including password mismatches, missing databases, incorrect configuration, and permission issues. Recreates database if needed and updates CrowdSec configuration.
- **Fixes:**
  - Password mismatches between .env and database
  - Missing crowdsec_db database
  - Incorrect user permissions
  - Config.yaml.local database settings
  - Connection string format

### 🗄️ fix-postgres-password-mismatch.sh
**Fix PostgreSQL Password Mismatch**

- **Purpose:** Synchronize PostgreSQL password across all configurations
- **Description:** Resolves password mismatches when .env, database, and service configurations have different PostgreSQL passwords. Updates all locations to use consistent password and restarts affected services.

### 🗄️ fix-postgres-crowdsec-connection.sh
**Fix CrowdSec Database Connection**

- **Purpose:** Repair CrowdSec connection to PostgreSQL
- **Description:** Specialized fix for CrowdSec unable to connect to PostgreSQL. Verifies database exists, checks credentials, updates CrowdSec configuration, and restarts CrowdSec service.

### 📊 fix-loki.sh
**Fix Loki Configuration Issues**

- **Purpose:** Resolve Loki logging system problems
- **Description:** Fixes common Loki issues including permission problems (UID 10001 needs write access), configuration errors, missing directories, and startup failures. Ensures Loki can write to its data directories.

### 📂 fix-loki-permissions.sh
**Fix Loki Directory Permissions**

- **Purpose:** Set correct permissions for Loki data directories
- **Description:** Loki runs as UID 10001 and requires specific permissions on its data directories (chunks, rules, compactor). This script creates missing directories and sets chmod 777 to allow Loki write access. Run if Loki shows permission denied errors.
- **Directories Fixed:**
  - data/loki/data/chunks
  - data/loki/data/rules
  - data/loki/data/compactor

### 🔒 fix-traefik-acme.sh
**Fix Traefik ACME Certificate File**

- **Purpose:** Ensure ACME certificate file exists with correct permissions
- **Description:** Creates and fixes the acme.json file used by Traefik to store Let's Encrypt certificates. The file must exist with 600 permissions (owner read/write only) for Traefik to accept it. This script creates the file if missing, initializes with empty JSON if empty, and sets correct permissions. Also verifies Traefik container can access the file.
- **Fixes:**
  - Creates data/traefik/acme.json if missing
  - Initializes empty file with `{}`
  - Sets permissions to 600 (required by Traefik)
  - Verifies volume mounting
  - Checks certificate count

### 🏷️ fix-promtail-labels.sh
**Fix Promtail Label Cardinality**

- **Purpose:** Reduce Promtail label cardinality to prevent HTTP 400 errors
- **Description:** Promtail's default labelmap can create 20+ labels per log line, exceeding Loki's limits and causing HTTP 400 errors. This script updates promtail-config.yml to use selective label mapping (7 essential labels only), preventing cardinality issues while maintaining useful log organization.
- **Reduces Labels To:**
  - container_name
  - compose_project
  - compose_service
  - source (stream)
  - filename
  - host
  - app_group/app_name (optional)

### 🔔 fix-alertmanager.sh
**Fix Alertmanager Configuration**

- **Purpose:** Repair Alertmanager configuration and connectivity
- **Description:** Fixes Alertmanager issues including invalid configuration YAML, missing notification receivers, incorrect Prometheus integration, and permission problems.

### 🔌 migrate-crowdsec-plugin.sh
**Migrate to CrowdSec Plugin**

- **Purpose:** Switch from bouncer container to Traefik plugin
- **Description:** Migrates CrowdSec integration from using the separate bouncer container to using Traefik's native plugin system. Updates Traefik configuration, disables bouncer service, and enables plugin in docker-compose.yml.

---

## Library Modules (lib/)

The lib/ directory contains reusable functions organized by purpose. All main scripts source these libraries for consistency.

### 📚 lib/common.sh
**Core Utility Functions**

- **Purpose:** Shared utilities used across all scripts
- **Functions:**
  - Color output (success, error, warning, info)
  - Logging functions
  - Environment variable loading
  - Path detection and validation
  - User input prompts
  - Directory creation helpers
  - File permission management
- **Exports:** Colors, symbols, utility functions
- **Used By:** All scripts

### ⚙️ lib/system.sh
**System Configuration Functions**

- **Purpose:** Operating system and package management
- **Functions:**
  - OS detection (Ubuntu, Debian, etc.)
  - Package installation (apt, yum)
  - Docker installation and configuration
  - System tuning (sysctl, limits)
  - UFW firewall setup
  - Service management (systemctl)
  - User and group management
  - Timezone configuration
- **Used By:** setup.sh, update.sh

### 🐳 lib/services.sh
**Docker Service Management**

- **Purpose:** Docker and Docker Compose service operations
- **Functions:**
  - Docker Compose up/down/restart
  - Container status checking
  - Log retrieval and monitoring
  - Volume management
  - Network configuration
  - Image pulling and cleanup
  - Health check execution
  - Service dependency ordering
- **Used By:** setup.sh, update.sh, health-check.sh

### 📦 lib/stacks.sh
**Stack Management Functions**

- **Purpose:** Application stack operations (used by stack.sh)
- **Functions:**
  - Stack discovery from repositories
  - Stack installation/uninstallation
  - Repository management
  - Systemd service integration
  - Configuration file handling
  - Stack metadata parsing
  - Dependency resolution
- **Used By:** stack.sh
- **Created:** October 2025 (refactored from jacker-stack)

### 💾 lib/backup.sh
**Backup and Restore Functions**

- **Purpose:** Backup creation and restoration operations
- **Functions:**
  - Archive creation (tar.gz)
  - Selective backup (config vs data)
  - Backup verification
  - Restoration with validation
  - Backup listing and management
  - Compression and encryption
- **Used By:** backup.sh, restore.sh, update.sh

### 🏥 lib/health-check.sh
**Health Check Functions**

- **Purpose:** System diagnostics and health monitoring
- **Functions:**
  - Container health checks
  - Service endpoint testing
  - Network connectivity tests
  - Volume permission verification
  - Configuration validation
  - SSL certificate checking
  - Database connectivity tests
  - Performance metrics collection
- **Used By:** health-check.sh, test.sh

---

## Templates

The templates/ directory contains configuration file templates with variable substitution.

### Configuration Templates

- **alertmanager.yml.template** - Alertmanager notification configuration
- **config.yaml.local.template** - CrowdSec local configuration
- **loki-config.yml.template** - Loki log aggregation settings
- **middlewares-oauth.template** - Traefik OAuth middleware
- **promtail-config.yml.template** - Promtail log collection config

### CrowdSec Templates

- **crowdsec-acquis.yaml** - Log source definitions for CrowdSec
- **crowdsec-custom-whitelists.yaml** - IP whitelist configuration
- **crowdsec-firewall-bouncer.yaml.template** - Firewall bouncer config

### Systemd Templates

- **jacker-compose.service.template** - Main Jacker systemd service
- **jacker-compose-reload.service.template** - Auto-reload service
- **jacker-compose-reload.timer.template** - Reload timer configuration

### System Templates

- **docker-daemon.json** - Docker daemon configuration
- **traefik.yml.template** - Traefik main configuration

### Template Usage

Templates use `envsubst` for variable replacement:
```bash
envsubst < templates/config.yaml.local.template > data/crowdsec/config/config.yaml.local
```

Variables are loaded from .env file.

---

## Script Conventions

### Common Patterns

All scripts in assets/ follow these conventions:

#### 1. **Shebang and Options**
```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

#### 2. **Script Location Detection**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */assets ]]; then
    JACKER_DIR="$(dirname "$SCRIPT_DIR")"
else
    JACKER_DIR="$SCRIPT_DIR"
fi
cd "$JACKER_DIR" || exit 1
```

#### 3. **Library Loading**
```bash
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/system.sh"
# Load other libraries as needed
```

#### 4. **Environment Loading**
```bash
if [[ -f ".env" ]]; then
    set -a  # Auto-export variables
    source .env
    set +a
fi
```

#### 5. **Error Handling**
```bash
error() {
    echo -e "${RED}✗ $*${NC}" >&2
}

success() {
    echo -e "${GREEN}✓ $*${NC}"
}
```

### Color Coding

All scripts use consistent color coding:
- **🔴 Red** - Errors and critical issues
- **🟢 Green** - Success messages and confirmations
- **🟡 Yellow** - Warnings and important notices
- **🔵 Blue** - Info messages and headers
- **🟣 Magenta** - Prompts and questions

### Exit Codes

Scripts use standard exit codes:
- **0** - Success
- **1** - General error
- **2** - Invalid usage
- **130** - User cancelled (Ctrl+C)

---

## Development Guidelines

### Adding New Scripts

When creating new scripts in assets/:

1. **Follow naming convention**: `verb-noun.sh` (e.g., `fix-loki.sh`, `setup-authentik.sh`)
2. **Include header comment**:
   ```bash
   #!/usr/bin/env bash
   #
   # Script Name - Brief description
   # Usage: ./assets/script-name.sh [options]
   #
   ```
3. **Source required libraries**
4. **Use helper functions** from lib/common.sh
5. **Implement error handling** with informative messages
6. **Add to Makefile** if user-facing
7. **Document in this README**
8. **Create tests** in tests/unit/ or tests/integration/

### Modifying Existing Scripts

1. **Preserve backward compatibility** when possible
2. **Update documentation** if behavior changes
3. **Add/update tests** for new functionality
4. **Test in fresh environment** before committing

---

## Related Documentation

- [Main README](../README.md) - Project overview and quick start
- [compose/README.md](../compose/README.md) - Service documentation
- [tests/README.md](../tests/README.md) - Testing documentation

---

**Last Updated:** 2025-10-11
**Jacker Version:** 2.0.0 (Modular Architecture)
