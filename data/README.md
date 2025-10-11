# Jacker Data Directory

This directory contains persistent data, configuration files, and runtime volumes for all Jacker services. Each service has its own subdirectory with specific purposes and file structures.

## Directory Overview

```
data/
├── alertmanager/       # Alert routing and notification configuration
├── authentik/          # Self-hosted identity provider data (optional)
├── crowdsec/           # IPS/IDS configuration and threat intelligence
├── grafana/            # Dashboard and visualization configuration
├── homepage/           # Dashboard homepage configuration
├── jaeger/             # Distributed tracing data
├── loki/               # Log aggregation configuration
├── oauth2-proxy/       # OAuth authentication sessions (runtime)
├── postgres/           # PostgreSQL database data (runtime)
├── prometheus/         # Metrics collection configuration
├── redis/              # Session cache data (runtime)
├── traefik/            # Reverse proxy configuration and SSL certificates
└── vscode/             # VS Code Server settings (runtime)
```

## Directory Details

### 🚨 alertmanager/

**Purpose:** Alert routing, grouping, and notification management for Prometheus alerts

**Files:**
- `alertmanager.yml` - Main configuration file
  - **Description:** Defines routing rules, receivers, and notification channels
  - **Key Sections:**
    - Global SMTP settings for email notifications
    - Route definitions for critical/warning/info severity levels
    - Receiver configurations (email, Telegram)
    - Inhibition rules to prevent alert flooding
  - **Customization:** Edit email addresses, Telegram bot tokens, SMTP server details

**Runtime Data:**
- `data/` - Alert state and silences (generated, gitignored)

**Documentation:** https://prometheus.io/docs/alerting/latest/alertmanager/

---

### 🔐 authentik/

**Purpose:** Self-hosted identity provider with SSO, MFA, LDAP, and SAML support (optional alternative to OAuth)

**Directories:**
- `postgres/` - Authentik's PostgreSQL database (runtime, gitignored)
- `media/` - User avatars and uploaded assets
- `certs/` - Custom SSL certificates for LDAP/SAML
- `custom-templates/` - Email and UI template overrides

**Setup:** Requires `./assets/setup-authentik.sh` to initialize

**When to Use:**
- Need multi-factor authentication (MFA)
- Require LDAP/SAML integration
- Want full control over identity management
- Corporate SSO requirements

**Documentation:** https://docs.goauthentik.io/

---

### 🛡️ crowdsec/

**Purpose:** Collaborative intrusion prevention system with community threat intelligence

**Directories:**
- `config/` - CrowdSec configuration files
  - `config.yaml.local` - Main configuration (database connection, API settings)
  - `profiles.yaml` - Ban duration and remediation profiles
  - `parsers/s02-enrich/` - Custom log parsers and enrichment rules
- `data/` - Threat intelligence database and decision cache (runtime, gitignored)

**Key Features:**
- Parses logs from Traefik, SSH, web services
- Stores decisions (bans) in PostgreSQL
- Shares threat intelligence with CrowdSec community
- Provides local API for bouncers (firewall integration)

**Configuration Files Generated During Setup:**
- Created by `assets/templates/config.yaml.local.template`
- Database credentials from `.env` variables

**Documentation:** https://docs.crowdsec.net/

---

### 📊 grafana/

**Purpose:** Visualization dashboards for metrics (Prometheus) and logs (Loki)

**Structure:**
```
grafana/
├── data/                   # Runtime database (gitignored)
└── provisioning/           # Auto-provisioned configuration
    ├── datasources/
    │   └── datasource.yml  # Prometheus and Loki connections
    └── dashboards/
        ├── default.yml     # Dashboard provider configuration
        ├── dashboard.yml   # Dashboard discovery settings
        ├── main-overview.json         # System overview dashboard
        ├── traefik.json               # Traefik metrics
        ├── node-exporter.json         # System metrics (CPU, RAM, disk)
        ├── prometheus.json            # Prometheus internal metrics
        ├── crowdsec-overview.json     # CrowdSec statistics
        ├── crowdsec-details.json      # Detailed threat analysis
        └── crowdsec-lapi.json         # CrowdSec API metrics
```

**Dashboards Included:**

1. **main-overview.json** - System health at a glance
   - Service status and uptime
   - Resource utilization (CPU, memory, disk)
   - Network traffic
   - Active alerts

2. **traefik.json** - Reverse proxy metrics
   - Request rates and response times
   - HTTP status code distribution
   - Active connections
   - SSL certificate expiry

3. **node-exporter.json** - Host system metrics
   - CPU usage per core
   - Memory and swap usage
   - Disk I/O and space
   - Network bandwidth

4. **crowdsec-overview.json** - Security overview
   - Banned IPs count
   - Attack types distribution
   - Top attacking countries
   - Decisions timeline

5. **crowdsec-details.json** - Threat intelligence details
   - Alert breakdown by scenario
   - Machine activity
   - Parser performance
   - Decision reasons

**Customization:**
- Add custom dashboards by placing JSON files in `provisioning/dashboards/`
- Edit datasources in `provisioning/datasources/datasource.yml`
- Grafana will auto-reload changes

**Access:** `https://grafana.$PUBLIC_FQDN`

**Documentation:** https://grafana.com/docs/grafana/latest/

---

### 🏠 homepage/

**Purpose:** Unified dashboard with service discovery, status widgets, and bookmarks

**Files:**

- **bookmarks.yaml** - Quick link bookmarks
  - **Description:** Organize external and internal links by category
  - **Example:** Documentation links, admin panels, external tools

- **custom.css** - Custom styling
  - **Description:** Override default Homepage theme colors and layouts
  - **Usage:** Add custom CSS rules to personalize appearance

- **custom.js** - Custom JavaScript
  - **Description:** Add client-side functionality and interactivity
  - **Usage:** Custom widgets, dynamic content, integrations

- **docker.yaml** - Docker container discovery
  - **Description:** Configure which Docker containers to display
  - **Features:** Auto-discovery via Docker socket, container status, stats

- **kubernetes.yaml** - Kubernetes integration (optional)
  - **Description:** Connect to Kubernetes clusters for monitoring
  - **Usage:** Typically empty for Docker-only deployments

- **services.yaml** - Manual service definitions
  - **Description:** Define services not auto-discovered by Docker
  - **Features:** Custom icons, URLs, descriptions, health checks

- **settings.yaml** - Global Homepage settings
  - **Description:** Theme, layout, language, default page settings
  - **Customization:** Background images, color schemes, widget placement

- **widgets.yaml** - Dashboard widgets
  - **Description:** System info, weather, search, custom API widgets
  - **Examples:** CPU/RAM usage, disk space, external API data

**Configuration Tips:**
- Homepage auto-discovers Docker services via socket proxy
- Add custom services in `services.yaml` for non-Docker apps
- Use widgets for real-time system information
- Supports Homepage API for custom integrations

**Access:** `https://$PUBLIC_FQDN`

**Documentation:** https://gethomepage.dev/

---

### 🔍 jaeger/

**Purpose:** Distributed tracing for microservices and API requests

**Directories:**
- `badger/` - BadgerDB storage for trace data (runtime, gitignored)
- `sampling_strategies.json` - Trace sampling configuration (optional)

**Use Cases:**
- Trace request flow across multiple services
- Identify performance bottlenecks
- Debug microservice interactions
- Monitor service dependencies

**Access:** `https://jaeger.$PUBLIC_FQDN`

**Documentation:** https://www.jaegertracing.io/docs/

---

### 📝 loki/

**Purpose:** Log aggregation and querying system (like Prometheus for logs)

**Files:**

- **loki-config.yml** - Loki server configuration
  - **Description:** Storage, retention, and ingestion limits
  - **Key Settings:**
    - Authentication disabled (internal network only)
    - Chunk storage in `/loki/chunks`
    - Index storage in `/loki/index`
    - 30-day retention period (configurable)
    - Label cardinality limits (prevents memory issues)
  - **Generated From:** `assets/templates/loki-config.yml.template`

- **promtail-config.yml** - Log shipping agent configuration
  - **Description:** Discovers Docker containers and ships logs to Loki
  - **Key Features:**
    - Auto-discovers containers via Docker socket
    - Extracts 7 essential labels (container_name, compose_project, etc.)
    - Filters out noisy system logs
    - Relabeling pipeline to reduce cardinality
  - **Label Strategy:** Limited to 7 labels to prevent HTTP 400 errors
  - **Generated From:** `assets/templates/promtail-config.yml.template`

**Runtime Directories:** (gitignored)
- `data/chunks/` - Log data chunks (requires UID 10001 write access)
- `data/index/` - Log index files
- `data/rules/` - Recording and alerting rules
- `data/compactor/` - Compacted data

**Permission Requirements:**
- All `data/` subdirectories must be writable by UID 10001
- Setup script applies `chmod -R 777 data/loki/data`
- See `assets/fix-loki-permissions.sh` for troubleshooting

**Common Issues:**
- **HTTP 400 errors:** Too many labels (>20) sent to Loki
  - **Fix:** `./assets/fix-promtail-labels.sh` (reduces to 7 labels)
- **Permission denied:** Loki can't write to data directories
  - **Fix:** `./assets/fix-loki-permissions.sh`

**Access:** `https://loki.$PUBLIC_FQDN` (API only, use Grafana for UI)

**Documentation:** https://grafana.com/docs/loki/latest/

---

### 🔑 oauth2-proxy/

**Purpose:** OAuth authentication session cache (runtime only)

**Contents:** Session data and cookies (automatically managed, gitignored)

**Function:**
- Stores authenticated user sessions
- Caches OAuth tokens from Google
- Validates requests via Redis backend

**Configuration:** Defined in `compose/oauth.yml`, no manual files needed

**Documentation:** https://oauth2-proxy.github.io/oauth2-proxy/

---

### 🗄️ postgres/

**Purpose:** PostgreSQL database for CrowdSec decisions and metadata

**Directories:**
- `data/` - PostgreSQL data files (runtime, gitignored)

**Files:**
- `postgresql.conf` - PostgreSQL configuration (optional)
  - **Description:** Performance tuning, connection limits, logging
  - **Usually:** Not needed, defaults work well

**Database Schema:**
- Created by `assets/setup-crowdsec-db.sh` during installation
- Database name: `$POSTGRES_DB` (from .env, typically `crowdsec_db`)
- User: `$POSTGRES_USER` (from .env, typically `crowdsec`)
- Password: `$POSTGRES_PASSWORD` (from .env, auto-generated)

**Setup Script:** `./assets/setup-crowdsec-db.sh`

**Health Check:** Verifies PostgreSQL ready before starting CrowdSec

**Documentation:** https://www.postgresql.org/docs/

---

### 📈 prometheus/

**Purpose:** Metrics collection, storage, and alerting

**Structure:**
```
prometheus/
├── config/
│   ├── prometheus.yml       # Main configuration
│   ├── alert.rules          # Alert rules (legacy)
│   ├── alerts/
│   │   ├── security.yml     # Security-related alerts
│   │   ├── services.yml     # Service availability alerts
│   │   └── system.yml       # System resource alerts
│   └── scrape.d/
│       ├── prometheus.yml   # Prometheus self-monitoring
│       ├── node-exporter.yml # System metrics
│       ├── traefik.yml      # Traefik metrics
│       └── crowdsec.yml     # CrowdSec metrics
├── data/                    # Time-series database (gitignored)
└── prometheus.yml           # Alternative config location
```

**Configuration Files:**

1. **config/prometheus.yml** - Main configuration
   - Global scrape interval (15s)
   - Alertmanager endpoint
   - Scrape config includes from `scrape.d/*.yml`
   - Rule file includes from `alerts/*.yml`

2. **alerts/security.yml** - Security alerts
   - High CrowdSec ban rate
   - Unusual authentication failures
   - Suspicious traffic patterns

3. **alerts/services.yml** - Service health alerts
   - Container down
   - Service unresponsive
   - High error rates
   - Certificate expiring soon

4. **alerts/system.yml** - System resource alerts
   - High CPU usage (>80%)
   - High memory usage (>90%)
   - Low disk space (<10%)
   - High disk I/O wait

5. **scrape.d/*.yml** - Scrape job definitions
   - Auto-discovered service endpoints
   - Metric collection intervals
   - Label configurations

**Metrics Exported:**
- **Traefik:** Request rates, response times, status codes
- **Node Exporter:** CPU, memory, disk, network
- **CrowdSec:** Bans, alerts, parser performance
- **Prometheus:** Internal metrics and performance

**Retention:** Default 15 days (configurable in compose/prometheus.yml)

**Access:** `https://prometheus.$PUBLIC_FQDN`

**Documentation:** https://prometheus.io/docs/

---

### 💾 redis/

**Purpose:** In-memory cache for OAuth session storage

**Contents:** Redis RDB snapshots and AOF logs (runtime, gitignored)

**Function:**
- Stores OAuth2 Proxy sessions
- Provides fast session lookup
- Persists data to disk via RDB snapshots

**Configuration:** Managed by Redis container, no manual configuration needed

**Persistence:**
- RDB snapshots every 60 seconds if data changed
- AOF (Append-Only File) for durability

**Documentation:** https://redis.io/docs/

---

### 🔀 traefik/

**Purpose:** Reverse proxy, SSL termination, and dynamic routing

**Structure:**
```
traefik/
├── traefik.yml              # Main static configuration
├── middleware.yml           # Middleware definitions (deprecated)
├── plugins.yml              # Plugin configurations (deprecated)
├── acme.json                # Let's Encrypt certificates (gitignored)
├── certs/                   # Custom SSL certificates (gitignored)
└── rules/                   # Dynamic configuration files
    ├── chain-oauth.yml                      # OAuth-protected route chain
    ├── chain-no-oauth.yml                   # Public route chain
    ├── chain-oauth-no-crowdsec.yml         # OAuth without CrowdSec
    ├── chain-no-oauth-no-crowdsec.yml      # Public without CrowdSec
    ├── middlewares-oauth.yml               # OAuth2 Proxy forwardAuth
    ├── middlewares-authentik.yml           # Authentik forwardAuth
    ├── middlewares-traefik-bouncer.yml     # CrowdSec IP blocking
    ├── middlewares-secure-headers.yml      # Security headers (HSTS, CSP)
    ├── middlewares-security-advanced.yml   # Advanced security rules
    ├── middlewares-rate-limit.yml          # Rate limiting rules
    ├── middlewares-compress.yml            # Gzip/Brotli compression
    ├── middlewares-caching.yml             # Cache-Control headers
    ├── middlewares-redirect-to-non-www.yml # WWW to non-WWW redirect
    └── tls-opts.yml                        # TLS/SSL options (min version, ciphers)
```

**Configuration Files:**

1. **traefik.yml** - Static configuration
   - **Description:** Entry points, providers, API/dashboard settings
   - **Key Settings:**
     - HTTP (port 80) and HTTPS (port 443) entry points
     - Docker provider for service discovery
     - File provider for `rules/` directory
     - Let's Encrypt ACME configuration
     - HTTP/3 (QUIC) support on port 443/udp
     - Access logs and metrics

2. **acme.json** - Let's Encrypt certificates
   - **Description:** Automatically generated SSL certificates
   - **Permissions:** Must be `chmod 600` (only owner can read/write)
   - **Contents:** Private keys, certificates, ACME account info
   - **Renewal:** Automatic via Traefik ACME client
   - **Important:** Never commit to git (contains private keys)

3. **Middleware Chains** - Pre-configured middleware stacks
   - **chain-oauth@file:** OAuth + CrowdSec + security headers (default for sensitive services)
   - **chain-no-oauth@file:** CrowdSec + security headers only (public services)
   - **chain-oauth-no-crowdsec@file:** OAuth + security headers (bypass CrowdSec)
   - **chain-no-oauth-no-crowdsec@file:** Security headers only (minimal protection)

4. **Individual Middlewares:**
   - **middlewares-oauth.yml:** Google OAuth via oauth2-proxy
     - ForwardAuth to `http://oauth:4181`
     - Validates session cookies
     - Redirects unauthenticated users to Google login

   - **middlewares-authentik.yml:** Self-hosted authentication
     - ForwardAuth to Authentik server
     - Supports MFA, SSO, LDAP, SAML
     - Alternative to Google OAuth

   - **middlewares-traefik-bouncer.yml:** CrowdSec IP blocking
     - Queries CrowdSec local API for ban decisions
     - Blocks IPs with active bans
     - Returns 403 Forbidden for banned IPs

   - **middlewares-secure-headers.yml:** Security headers
     - HSTS (HTTP Strict Transport Security)
     - X-Frame-Options: DENY
     - X-Content-Type-Options: nosniff
     - Referrer-Policy: strict-origin-when-cross-origin
     - Permissions-Policy

   - **middlewares-rate-limit.yml:** Rate limiting
     - Prevents abuse and DDoS
     - Configurable per-IP limits
     - Burst allowance

   - **middlewares-compress.yml:** Response compression
     - Gzip and Brotli compression
     - Reduces bandwidth usage
     - Faster page loads

   - **tls-opts.yml:** TLS/SSL configuration
     - Minimum TLS 1.2
     - Modern cipher suites
     - Prefer server cipher order

**Usage in Service Labels:**
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`myservice.${PUBLIC_FQDN}`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls=true"
  - "traefik.http.routers.myservice.middlewares=chain-oauth@file"
```

**Common Middleware Patterns:**
- **Authenticated Admin Panel:** `chain-oauth@file`
- **Public Website:** `chain-no-oauth@file`
- **Testing/Development:** `chain-no-oauth-no-crowdsec@file`
- **Authentik-Protected:** `chain-authentik@file` (custom chain with middlewares-authentik)

**Troubleshooting:**
- **404 on all endpoints:** OAuth not configured, use `./assets/disable-oauth-for-testing.sh`
- **Invalid certificate:** Set real domain in `.env`, verify DNS, check `acme.json` populated
- **Permission denied on acme.json:** Run `chmod 600 data/traefik/acme.json`

**Access:** `https://traefik.$PUBLIC_FQDN` (dashboard)

**Documentation:** https://doc.traefik.io/traefik/

---

### 💻 vscode/

**Purpose:** VS Code Server configuration and extensions (runtime only)

**Directories:**
- `config/` - User settings, extensions, workspace data (gitignored)

**Contents:**
- VS Code settings.json
- Installed extensions
- User snippets
- Workspace configurations

**Access:** `https://vscode.$PUBLIC_FQDN`

**Documentation:** https://github.com/coder/code-server

---

## Data Management

### Backup Strategy

**Included in Backup:**
- All configuration files (*.yml, *.yaml, *.json)
- Traefik rules and middleware definitions
- Grafana dashboards and datasources
- Prometheus alert rules
- Homepage configuration

**Excluded from Backup:** (runtime data, regeneratable)
- Database files (postgres/, redis/, loki/data/)
- SSL certificates (acme.json - can be regenerated)
- Log data (loki/, jaeger/)
- Session data (oauth2-proxy/)
- Container data directories

**Backup Commands:**
```bash
# Full backup (includes config and data)
make backup

# Manual backup script
./assets/backup.sh
```

**Restore:**
```bash
# Restore from backup
./assets/restore.sh /path/to/backup.tar.gz
```

### Permissions

**Critical Permissions:**
- `traefik/acme.json` - Must be `chmod 600` (owner read/write only)
- `loki/data/*` - Must be writable by UID 10001 (`chmod -R 777`)

**Fix Scripts:**
- `./assets/fix-loki-permissions.sh` - Fix Loki permission issues
- `./assets/fix-traefik-acme.sh` - Fix acme.json permissions

### Cleanup

**Safe to Delete:** (will be regenerated)
- `postgres/data/` - Database files (loses CrowdSec decisions)
- `redis/` - Session data (users will need to re-authenticate)
- `loki/data/` - Log history (loses historical logs)
- `prometheus/data/` - Metrics history (loses historical metrics)

**Never Delete:**
- `traefik/acme.json` - SSL certificates (will hit Let's Encrypt rate limits)
- `traefik/rules/` - Routing configuration (services will become inaccessible)
- Configuration files (`*.yml`, `*.yaml`)

**Cleanup Commands:**
```bash
# Remove all runtime data (dangerous!)
make clean-data

# Remove specific service data
docker compose down -v <service-name>
```

### Volume Mounts

All data directories are mounted as Docker volumes in `docker-compose.yml`:

```yaml
volumes:
  - $DATADIR/service-name:/container-path
```

**Read-Only Mounts:** (`:ro` flag)
- Configuration files that shouldn't be modified by containers
- Example: `traefik/traefik.yml`, `loki/loki-config.yml`

**Read-Write Mounts:** (default)
- Runtime data directories
- Example: `postgres/data`, `grafana/data`

## Configuration Generation

Many configuration files are generated from templates during setup:

**Template Location:** `assets/templates/*.template`

**Generated Files:**
- `loki/loki-config.yml` ← `loki-config.yml.template`
- `loki/promtail-config.yml` ← `promtail-config.yml.template`
- `crowdsec/config/config.yaml.local` ← `config.yaml.local.template`
- `traefik/rules/middlewares-oauth.yml` ← Generated by setup script

**Generation Process:**
1. Setup script reads template
2. Substitutes environment variables with `envsubst`
3. Writes final configuration to `data/` directory

**Regeneration:**
```bash
# Re-run setup to regenerate configs
./assets/setup.sh

# Or manually regenerate specific config
envsubst < assets/templates/loki-config.yml.template > data/loki/loki-config.yml
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   - **Symptom:** Container crashes with "permission denied"
   - **Cause:** Wrong ownership or permissions on data directories
   - **Fix:** Check UID/GID requirements, run fix-permissions scripts

2. **Configuration Not Applied**
   - **Symptom:** Changes to YAML files not reflected in service
   - **Cause:** Container hasn't been restarted
   - **Fix:** `make restart` or `docker compose restart <service>`

3. **Data Directory Not Found**
   - **Symptom:** Container fails to start, "no such file or directory"
   - **Cause:** Directory not created during setup
   - **Fix:** Run `./assets/setup.sh` or manually create required directories

4. **Loki HTTP 400 Errors**
   - **Symptom:** Promtail logs show HTTP 400 from Loki
   - **Cause:** Too many labels (>20) sent per log line
   - **Fix:** Run `./assets/fix-promtail-labels.sh` to reduce to 7 labels

5. **SSL Certificate Issues**
   - **Symptom:** Invalid certificate warnings in browser
   - **Cause:** Let's Encrypt not configured, wrong domain, or rate limited
   - **Fix:**
     - Verify `LETSENCRYPT_EMAIL` set in `.env`
     - Check DNS points to server
     - Verify `acme.json` has `chmod 600`
     - Check Traefik logs for ACME errors

### Diagnostic Commands

```bash
# Check data directory permissions
ls -la data/

# Check specific service data
ls -la data/traefik/
ls -la data/loki/data/

# View container logs for data-related errors
make logs SVC=loki
make logs SVC=traefik

# Verify volume mounts
docker inspect <container-name> | grep -A 20 Mounts

# Check configuration syntax
# Traefik
docker compose config | grep -A 100 traefik

# Prometheus (YAML syntax)
docker run --rm -v $PWD/data/prometheus/config:/config prom/prometheus:latest promtool check config /config/prometheus.yml
```

## Additional Resources

- **Main Documentation:** [jacker.jacar.es](https://jacker.jacar.es)
- **Service Documentation:** [compose/README.md](../compose/README.md)
- **Scripts Documentation:** [assets/README.md](../assets/README.md)
- **Developer Guide:** [CLAUDE.md](../CLAUDE.md)

---

**Note:** Directories marked as "runtime" or "gitignored" are automatically generated and should not be manually edited. Configuration files (*.yml, *.yaml) are safe to edit and will persist across container restarts.
