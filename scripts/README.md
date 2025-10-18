# Jacker Stack Management Scripts

This directory contains scripts for managing the Jacker stack, including validation, security, and deployment.

## Scripts Overview

### 0. validate-deployment.sh

**CRITICAL: Run this BEFORE every deployment!**

Comprehensive pre-deployment validation script that catches permission and configuration issues before services start.

**Usage:**
```bash
./scripts/validate-deployment.sh
```

**Exit Codes:**
- `0` - All validations passed (safe to deploy)
- `Non-zero` - Validation errors detected (DO NOT deploy)

**What it validates:**

**1. Directory Permissions:**
- `/data/traefik/plugins` - UID 1000, mode 755
- `/data/loki` - UID 10001, mode 755
- `/data/jaeger/badger` - PUID from .env, mode 755
- `/data/crowdsec` - UID 1000, mode 755
- `/data/postgres/data/pgdata` - UID 70, mode 700
- `/data/redis/data` - writable

**2. Configuration Files:**
- All YAML files in `config/traefik/rules/` are valid
- No forbidden Traefik v3 fields (retryOn, bufferingBodyMode)
- Chain files have proper middleware references (no @file inside chains)
- `docker-compose.yml` syntax is valid

**3. Environment Variables:**
- All required vars from `.env.defaults` are set in `.env`
- PUID and PGID are numeric
- Domain names are valid format
- No default/placeholder values in critical vars

**4. Secrets:**
- All required secret files exist in `secrets/`
- Secrets have correct permissions (600 or 400)
- Secret files are not empty

**5. Docker:**
- Docker daemon is running
- Docker Compose is installed
- Required networks can be created
- Sufficient disk space available
- No port conflicts detected

**6. Network Configuration:**
- All network subnet variables are set
- Subnet formats are valid (CIDR notation)

**7. Firewall:**
- UFW configuration check (if installed)
- Required ports (80, 443) are allowed

**Output Format:**
- Green checkmarks (✅) for passed checks
- Red X (❌) for failed checks
- Yellow warning (⚠️) for non-critical issues
- Blue info (ℹ️) for informational messages
- Clear error messages with remediation steps

**Example Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Validating Environment Variables
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[CHECK] Checking for .env file
  ✅ Found .env file
[CHECK] Loading environment variables
  ✅ Environment variables loaded
[CHECK] Validating required environment variables are set
  ✅ All required environment variables are set
```

**Best Practice:**
Add this to your deployment workflow:
```bash
# Before deploying
./scripts/validate-deployment.sh && docker compose up -d
```

**Troubleshooting Common Issues:**

*Issue: "Required variable X is not set"*
```bash
# Copy defaults and configure
cp .env.defaults .env
# Edit .env and set the missing variable
```

*Issue: "Directory has incorrect ownership"*
```bash
# Fix ownership (example for Loki)
sudo chown -R 10001:10001 /data/loki
```

*Issue: "Secret file missing"*
```bash
# Generate and save secret
openssl rand -base64 32 > secrets/secret_name
chmod 600 secrets/secret_name
```

*Issue: "Chain file contains '@file' suffix"*
```bash
# Edit chain files and remove @file from middleware references
# Change: - middleware-name@file
# To:     - middleware-name
```

### 1. generate-postgres-ssl.sh

Generates self-signed SSL certificates for PostgreSQL.

**Usage:**
```bash
./scripts/generate-postgres-ssl.sh
```

**What it does:**
- Creates a Certificate Authority (CA)
- Generates server certificate and key
- Sets proper permissions automatically
- Verifies certificate validity
- Provides next steps for production

**Output Location:**
- `${DATADIR}/postgres/ssl/ca.crt` - CA certificate
- `${DATADIR}/postgres/ssl/ca.key` - CA private key
- `${DATADIR}/postgres/ssl/server.crt` - Server certificate
- `${DATADIR}/postgres/ssl/server.key` - Server private key

**Environment Variables:**
```bash
POSTGRES_SSL_CERT_DAYS=3650      # Certificate validity (days)
POSTGRES_SSL_COUNTRY="US"        # Country code
POSTGRES_SSL_STATE="State"       # State/Province
POSTGRES_SSL_CITY="City"         # City
POSTGRES_SSL_ORG="Organization"  # Organization name
POSTGRES_SSL_OU="IT Department"  # Organizational Unit
POSTGRES_SSL_CN="postgres"       # Common Name
POSTGRES_SSL_EMAIL="admin@localhost"  # Email address
```

### 2. set-postgres-permissions.sh

Sets proper file permissions for PostgreSQL configuration and SSL files.

**Usage:**
```bash
./scripts/set-postgres-permissions.sh
```

**What it does:**
- Sets pg_hba.conf to 0600
- Sets postgresql.conf to 0600
- Sets SSL keys to 0600
- Sets SSL certificates to 0644
- Sets proper ownership for PostgreSQL user
- Verifies all permissions

**Requirements:**
- May need to run with sudo for ownership changes
- PostgreSQL user ID varies by image (70 for Alpine, 999 for Debian)

## Quick Start

### Initial Setup

1. **Generate SSL certificates:**
   ```bash
   ./scripts/generate-postgres-ssl.sh
   ```

2. **Set file permissions:**
   ```bash
   ./scripts/set-postgres-permissions.sh
   ```

   Or with sudo if needed:
   ```bash
   sudo ./scripts/set-postgres-permissions.sh
   ```

3. **Restart PostgreSQL:**
   ```bash
   docker compose restart postgres
   ```

4. **Verify SSL is enabled:**
   ```bash
   docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SHOW ssl;'
   ```

### After Configuration Changes

Run the permissions script after modifying:
- `config/postgres/pg_hba.conf`
- `config/postgres/postgresql.conf`

```bash
./scripts/set-postgres-permissions.sh
docker compose restart postgres
```

### Certificate Renewal

Self-signed certificates expire after 10 years by default. To renew:

```bash
# Backup existing certificates
cp -r ${DATADIR}/postgres/ssl ${DATADIR}/postgres/ssl.backup

# Generate new certificates
./scripts/generate-postgres-ssl.sh

# Restart PostgreSQL
docker compose restart postgres
```

## Production Notes

### Using Let's Encrypt Certificates

For production environments, use trusted certificates from Let's Encrypt:

```bash
# 1. Obtain certificates using certbot
certbot certonly --standalone -d postgres.yourdomain.com

# 2. Copy to PostgreSQL SSL directory
cp /etc/letsencrypt/live/postgres.yourdomain.com/fullchain.pem \
   ${DATADIR}/postgres/ssl/server.crt
cp /etc/letsencrypt/live/postgres.yourdomain.com/privkey.pem \
   ${DATADIR}/postgres/ssl/server.key
cp /etc/letsencrypt/live/postgres.yourdomain.com/chain.pem \
   ${DATADIR}/postgres/ssl/ca.crt

# 3. Set permissions
chmod 0600 ${DATADIR}/postgres/ssl/server.key
chmod 0644 ${DATADIR}/postgres/ssl/server.crt
chmod 0644 ${DATADIR}/postgres/ssl/ca.crt
chown -R 70:70 ${DATADIR}/postgres/ssl

# 4. Restart PostgreSQL
docker compose restart postgres
```

### Automated Certificate Renewal

Create a cron job for automatic Let's Encrypt renewal:

```bash
# Add to crontab: sudo crontab -e
0 3 1 * * certbot renew --post-hook "cd /path/to/jacker && ./scripts/copy-letsencrypt-certs.sh && docker compose restart postgres"
```

## Troubleshooting

### Certificates Not Found

**Error:** `FATAL: could not load server certificate file`

**Solution:**
```bash
./scripts/generate-postgres-ssl.sh
docker compose restart postgres
```

### Permission Errors

**Error:** `FATAL: pg_hba.conf permissions too open`

**Solution:**
```bash
sudo ./scripts/set-postgres-permissions.sh
docker compose restart postgres
```

### Ownership Issues

**Error:** `FATAL: could not access private key file`

**Solution:**
```bash
# Check PostgreSQL user ID in your container
docker compose exec postgres id postgres

# Set ownership manually (use UID from above)
sudo chown -R 70:70 ${CONFIGDIR}/postgres
sudo chown -R 70:70 ${DATADIR}/postgres/ssl
```

### Script Execution Errors

**Error:** `Permission denied`

**Solution:**
```bash
# Make scripts executable
chmod +x scripts/*.sh
```

## Security Best Practices

1. **Never commit SSL keys to version control**
   - Keys are in .gitignore by default
   - Keep backups in secure, encrypted storage

2. **Rotate certificates regularly**
   - Set calendar reminders for expiration
   - Test renewal process in development first

3. **Use strong passwords**
   - Generate with: `openssl rand -base64 32`
   - Store in secure password manager

4. **Restrict file permissions**
   - Run permission script after any changes
   - Verify with: `ls -la config/postgres/`

5. **Monitor logs**
   - Check PostgreSQL logs: `docker compose logs postgres`
   - Look for authentication failures
   - Watch for SSL errors

## Additional Resources

- [PostgreSQL Security Documentation](../docs/POSTGRESQL_SECURITY.md)
- [PostgreSQL SSL Documentation](https://www.postgresql.org/docs/current/ssl-tcp.html)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

## Support

For issues or questions:
1. Check logs: `docker compose logs postgres`
2. Review security documentation: `docs/POSTGRESQL_SECURITY.md`
3. Open an issue in the project repository
