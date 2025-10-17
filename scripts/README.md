# PostgreSQL Security Scripts

This directory contains scripts for managing PostgreSQL security configuration.

## Scripts Overview

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
