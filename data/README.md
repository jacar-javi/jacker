# Data Directory

This directory contains **runtime data only**. In the repository, it maintains the directory structure using `.gitkeep` files. All actual data is generated during setup or created at runtime.

## Important Note

**This directory in the repository contains ONLY:**
- Directory structure with `.gitkeep` files
- This README.md file

**All actual data is:**
- Generated from templates during `./jacker init`
- Created at runtime by services
- Never tracked in git (see `.gitignore`)

## Directory Structure

```
data/
├── alertmanager/       # Alert state and silences (runtime)
├── authentik/          # Identity provider database (runtime, optional)
├── crowdsec/           # IPS/IDS runtime data and decisions
├── grafana/            # Dashboard database and plugins (runtime)
├── homepage/           # Generated custom CSS/JS (from templates)
├── jaeger/             # Distributed tracing data (runtime)
├── loki/               # Log chunks and index (runtime)
├── node-exporter/      # Text file collector data (runtime)
├── oauth2-proxy/       # OAuth session cache (runtime)
├── pgbackrest/         # PostgreSQL backup data (runtime)
├── postgres/           # PostgreSQL database files (runtime)
├── prometheus/         # Time-series metrics database (runtime)
├── promtail/           # Log shipping positions (runtime)
├── redis/              # Session cache data (runtime)
├── traefik/            # SSL certificates and dynamic config (runtime)
└── vscode/             # VS Code Server settings (runtime)
```

## Configuration Management

### Where Configuration Lives

1. **Docker Configs** (Immutable, defined in compose files)
   - Most service configurations are now Docker configs
   - Mounted read-only into containers
   - Source files in `config/` directory

2. **Generated from Templates** (During setup)
   - Files created by `./jacker init` from `assets/templates/`
   - Examples:
     - `data/loki/loki-config.yml` ← `assets/templates/loki-config.yml.template`
     - `data/loki/promtail-config.yml` ← `assets/templates/promtail-config.yml.template`
     - `data/crowdsec/config/config.yaml.local` ← `assets/templates/config.yaml.local.template`
     - `data/homepage/custom.css` ← `assets/templates/homepage-custom.css.template`
     - `data/homepage/custom.js` ← `assets/templates/homepage-custom.js.template`

3. **Runtime Generated** (Created by services)
   - SSL certificates (`data/traefik/acme/acme.json`)
   - Database files (PostgreSQL, Redis)
   - Log data (Loki chunks, Promtail positions)
   - Session data (OAuth2-Proxy)

## Service Data Details

### 🔀 Traefik
- **acme/acme.json** - Let's Encrypt SSL certificates (auto-generated, chmod 600)
- **rules/** - Dynamic configuration (generated from templates during setup)
- **certs/** - Custom certificates (if manually added)
- **logs/** - Access logs (if enabled)

### 📝 Loki
- **data/chunks/** - Compressed log data
- **data/index/** - Log index files
- **data/compactor/** - Compacted data
- **data/rules/** - Alert rules (if configured)
- **loki-config.yml** - Generated from template
- **promtail-config.yml** - Generated from template
- **⚠️ Permissions:** All subdirs need chmod 777 for UID 10001

### 🛡️ CrowdSec
- **config/config.yaml.local** - Generated from template with DB credentials
- **data/** - Decision cache and local database
- **hub/** - Downloaded scenarios and parsers

### 📊 Grafana
- **data/grafana.db** - Dashboard and user database
- **plugins/** - Installed Grafana plugins
- **provisioning/** - Auto-provisioned dashboards/datasources (from config/)

### 🗄️ PostgreSQL
- **data/** - Database cluster files
- Used by CrowdSec for decision storage
- Initialized during setup with proper credentials

### 💾 Redis
- **dump.rdb** - Database snapshot
- **appendonly.aof** - Append-only file (if enabled)
- Stores OAuth2 session data

### 🏠 Homepage
- **custom.css** - Generated from template (empty by default)
- **custom.js** - Generated from template (empty by default)
- Configuration files are in `config/homepage/`

### 📈 Prometheus
- **data/** - Time-series database (TSDB)
- **wal/** - Write-ahead log
- Configuration and rules in `config/prometheus/`

## Permission Requirements

Critical permissions that must be set during setup:

```bash
# Traefik SSL certificates (private keys)
chmod 600 data/traefik/acme/acme.json

# Loki data directories (UID 10001 needs write access)
chmod -R 777 data/loki/data

# Secrets directory
chmod 700 secrets/
```

## Setup Process

When you run `./jacker init`, the setup script:

1. **Creates directory structure**
   - All directories listed above
   - Sets proper permissions

2. **Generates configuration from templates**
   - Processes templates with environment variables
   - Creates service-specific configs

3. **Initializes runtime requirements**
   - Creates empty `acme.json` with 600 permissions
   - Sets Loki directory permissions
   - Creates PostgreSQL database for CrowdSec

## Backup Considerations

### What to Backup
- **Configuration:** Everything in `config/` directory
- **Certificates:** `data/traefik/acme/acme.json` (avoid rate limits)
- **Databases:** `data/postgres/`, `data/grafana/data/`
- **Custom files:** Any manually added configurations

### What NOT to Backup
- Log data (Loki chunks) - Can be regenerated
- Metrics data (Prometheus) - Historical data, not critical
- Session data (OAuth2-Proxy, Redis) - Temporary
- Cache files

### Backup Command
```bash
./jacker backup
```

## Troubleshooting

### Permission Denied Errors

**Loki Issues:**
```bash
# Fix Loki permissions (UID 10001)
chmod -R 777 data/loki/data
```

**Traefik Certificate Issues:**
```bash
# Fix acme.json permissions
chmod 600 data/traefik/acme/acme.json
```

### Missing Directories

If directories are missing after clone:
```bash
# Re-run setup to create all directories
./jacker init

# Or manually create structure
mkdir -p data/{traefik,loki,grafana,...}/...
```

### Configuration Not Found

If services can't find config files:
```bash
# Regenerate from templates
./jacker init

# Or manually process templates
envsubst < assets/templates/[template-name] > data/[service]/[config-file]
```

## Clean Slate

To completely reset runtime data:
```bash
# Stop all services
./jacker stop

# Remove all runtime data (CAUTION: Loses all data!)
find data -type f ! -name '.gitkeep' ! -name 'README.md' -delete

# Recreate structure and configs
./jacker init

# Start services
./jacker start
```

## Important Notes

1. **Never commit runtime data to git** - The `.gitignore` prevents this
2. **Don't edit generated files** - Edit templates in `assets/templates/` instead
3. **Permissions matter** - Especially for Loki (777) and Traefik acme.json (600)
4. **Configuration is separate** - Check `config/` directory for actual service configs
5. **Everything is reproducible** - Running `./jacker init` recreates all necessary files

## Related Documentation

- [Config Directory](../config/README.md) - Service configuration files
- [Assets Directory](../assets/README.md) - Templates and scripts
- [Compose Services](../compose/README.md) - Service definitions
- [Main README](../README.md) - Project overview

---

**Last Updated:** 2025-10-12
**Jacker Version:** 3.0.0 (Unified CLI)