# PostgreSQL Security Configuration Guide

## Overview

This guide documents the security enhancements implemented for PostgreSQL in the Jacker infrastructure project. These changes address critical security vulnerabilities related to authentication and encryption.

## Security Improvements

### 1. Authentication Security (pg_hba.conf)

#### Changes Made

**Before:**
- Local connections used `trust` authentication (passwordless access)
- Network connections used weak `md5` password hashing
- Overly permissive network access (10.0.0.0/8, 192.168.0.0/16)

**After:**
- All connections now require `scram-sha-256` authentication
- Local socket connections require password authentication
- Network access restricted to Docker subnet (172.16.0.0/12)
- Removed unnecessary network ranges

#### Authentication Method: SCRAM-SHA-256

SCRAM-SHA-256 (Salted Challenge Response Authentication Mechanism) provides:
- Strong password encryption
- Protection against replay attacks
- Resistance to brute-force attacks
- Industry-standard authentication

### 2. SSL/TLS Encryption (postgresql.conf)

#### Changes Made

**Before:**
- SSL completely disabled (`ssl = off`)
- All database traffic transmitted in plaintext
- No certificate configuration

**After:**
- SSL enabled with TLS 1.2 minimum version
- Strong cipher suite configuration
- Certificate-based encryption
- Server-preferred cipher ordering

#### SSL Configuration Details

```ini
ssl = on
ssl_cert_file = '/var/lib/postgresql/ssl/server.crt'
ssl_key_file = '/var/lib/postgresql/ssl/server.key'
ssl_ca_file = '/var/lib/postgresql/ssl/ca.crt'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

### 3. Client Connection Updates

#### postgres-exporter
Updated connection string to require SSL:
```yaml
DATA_SOURCE_URI: "postgres:5432/${POSTGRES_DB}?sslmode=require"
```

#### CrowdSec
Added SSL mode environment variable:
```yaml
POSTGRES_SSLMODE: require
```

## Setup Instructions

### Step 1: Generate SSL Certificates

Generate self-signed certificates for development/testing:

```bash
./scripts/generate-postgres-ssl.sh
```

This script will:
- Create a Certificate Authority (CA) certificate and key
- Generate server certificate signed by the CA
- Set proper file permissions (0600 for keys, 0644 for certificates)
- Verify certificate validity

**Certificate Locations:**
- CA Certificate: `${DATADIR}/postgres/ssl/ca.crt`
- CA Key: `${DATADIR}/postgres/ssl/ca.key`
- Server Certificate: `${DATADIR}/postgres/ssl/server.crt`
- Server Key: `${DATADIR}/postgres/ssl/server.key`

### Step 2: Set File Permissions

Ensure proper permissions on security-sensitive files:

```bash
./scripts/set-postgres-permissions.sh
```

This script will:
- Set pg_hba.conf to 0600
- Set postgresql.conf to 0600
- Set SSL keys to 0600
- Set SSL certificates to 0644
- Set proper ownership for PostgreSQL user

### Step 3: Update User Passwords

Since we switched from `md5` to `scram-sha-256`, existing password hashes need to be updated:

```bash
# Connect to PostgreSQL
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB}

# Update password for each user (this will re-hash with SCRAM-SHA-256)
ALTER USER your_username PASSWORD 'your_password';
```

### Step 4: Restart PostgreSQL

```bash
docker compose restart postgres
```

### Step 5: Verify SSL is Enabled

```bash
# Check SSL status
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SHOW ssl;'

# Expected output: on

# Check SSL cipher
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c 'SELECT version(), ssl_cipher();'
```

### Step 6: Test Secure Connection

```bash
# Test connection with SSL required
psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}?sslmode=require"

# Verify connection security
\conninfo
```

## Production Recommendations

### 1. Use Trusted Certificates

Replace self-signed certificates with certificates from a trusted Certificate Authority (e.g., Let's Encrypt):

```bash
# Obtain Let's Encrypt certificates
certbot certonly --standalone -d postgres.yourdomain.com

# Copy certificates to PostgreSQL SSL directory
cp /etc/letsencrypt/live/postgres.yourdomain.com/fullchain.pem ${DATADIR}/postgres/ssl/server.crt
cp /etc/letsencrypt/live/postgres.yourdomain.com/privkey.pem ${DATADIR}/postgres/ssl/server.key
cp /etc/letsencrypt/live/postgres.yourdomain.com/chain.pem ${DATADIR}/postgres/ssl/ca.crt

# Set permissions
chmod 0600 ${DATADIR}/postgres/ssl/server.key
chmod 0644 ${DATADIR}/postgres/ssl/server.crt
chmod 0644 ${DATADIR}/postgres/ssl/ca.crt
chown -R 70:70 ${DATADIR}/postgres/ssl  # or 999:999 for Debian-based images

# Restart PostgreSQL
docker compose restart postgres
```

### 2. Restrict Network Access

Further restrict `pg_hba.conf` to specific container IPs or services:

```conf
# Instead of entire Docker subnet
host    all             all             172.16.0.0/12           scram-sha-256

# Use specific container IPs
host    crowdsec_db     crowdsec_user   172.16.0.10/32          scram-sha-256
host    grafana_db      grafana_user    172.16.0.11/32          scram-sha-256
```

### 3. Enable Certificate Verification

Update client connections to verify server certificates:

```yaml
# postgres-exporter
DATA_SOURCE_URI: "postgres:5432/${POSTGRES_DB}?sslmode=verify-full&sslrootcert=/etc/ssl/certs/ca.crt"

# CrowdSec
POSTGRES_SSLMODE: verify-full
POSTGRES_SSLROOTCERT: /etc/ssl/certs/ca.crt
```

### 4. Implement Connection Auditing

Enable comprehensive logging in `postgresql.conf`:

```ini
log_connections = on
log_disconnections = on
log_statement = 'all'  # or 'ddl' for schema changes only
log_line_prefix = '%m [%p] %q%u@%d from %h '
```

### 5. Use Database-Specific Users

Create dedicated users for each service instead of using the superuser:

```sql
-- Create database-specific users
CREATE USER crowdsec_user WITH ENCRYPTED PASSWORD 'strong_password';
CREATE DATABASE crowdsec_db OWNER crowdsec_user;
GRANT ALL PRIVILEGES ON DATABASE crowdsec_db TO crowdsec_user;

CREATE USER grafana_user WITH ENCRYPTED PASSWORD 'strong_password';
CREATE DATABASE grafana_db OWNER grafana_user;
GRANT ALL PRIVILEGES ON DATABASE grafana_db TO grafana_user;
```

Update `pg_hba.conf` to restrict users to their databases:

```conf
host    crowdsec_db     crowdsec_user   172.16.0.0/12           scram-sha-256
host    grafana_db      grafana_user    172.16.0.0/12           scram-sha-256
```

### 6. Enable SSL Client Certificates (Mutual TLS)

For maximum security, require client certificates:

```conf
# In pg_hba.conf
hostssl all             all             172.16.0.0/12           cert clientcert=verify-full
```

Generate client certificates:

```bash
# Generate client key and certificate
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -out client.crt -days 365
```

### 7. Regular Security Maintenance

- **Rotate certificates**: Renew SSL certificates before expiration
- **Update passwords**: Regularly rotate database passwords
- **Review access logs**: Monitor for suspicious connection attempts
- **Update PostgreSQL**: Keep PostgreSQL version up-to-date with security patches
- **Audit permissions**: Regularly review pg_hba.conf and user privileges

## Security Validation

### Verify Authentication

```bash
# This should FAIL (no password-less access)
docker compose exec postgres psql -U postgres -d postgres -h localhost

# This should SUCCEED (with password)
docker compose exec postgres psql -U postgres -d postgres -h localhost -W
```

### Verify SSL Encryption

```bash
# Check SSL status
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SELECT * FROM pg_stat_ssl WHERE pid = pg_backend_pid();"

# Verify SSL is required
docker compose exec postgres psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "SHOW ssl;"
```

### Test Connection Modes

```bash
# This should FAIL (SSL required)
psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}?sslmode=disable"

# This should SUCCEED (SSL required)
psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}?sslmode=require"
```

## Troubleshooting

### Issue: PostgreSQL Won't Start

**Error:** `FATAL: could not load server certificate file`

**Solution:**
```bash
# Verify SSL certificate files exist
ls -la ${DATADIR}/postgres/ssl/

# Regenerate if missing
./scripts/generate-postgres-ssl.sh

# Check permissions
./scripts/set-postgres-permissions.sh
```

### Issue: Permission Denied Errors

**Error:** `FATAL: pg_hba.conf permissions too open`

**Solution:**
```bash
# Set correct permissions
chmod 0600 ${CONFIGDIR}/postgres/pg_hba.conf
chmod 0600 ${CONFIGDIR}/postgres/postgresql.conf
chown -R 70:70 ${CONFIGDIR}/postgres  # or 999:999
```

### Issue: Authentication Failures

**Error:** `FATAL: password authentication failed`

**Solution:**
```bash
# Update user password to use SCRAM-SHA-256
docker compose exec postgres psql -U postgres -c "ALTER USER username PASSWORD 'password';"
```

### Issue: SSL Connection Failures

**Error:** `SSL connection has been closed unexpectedly`

**Solution:**
```bash
# Check certificate validity
openssl x509 -in ${DATADIR}/postgres/ssl/server.crt -noout -dates

# Verify certificate chain
openssl verify -CAfile ${DATADIR}/postgres/ssl/ca.crt ${DATADIR}/postgres/ssl/server.crt
```

## Security Checklist

- [ ] SSL certificates generated and installed
- [ ] pg_hba.conf updated to use scram-sha-256
- [ ] postgresql.conf updated to enable SSL
- [ ] File permissions set correctly (0600 for sensitive files)
- [ ] User passwords updated/rehashed with SCRAM-SHA-256
- [ ] postgres-exporter using SSL connections
- [ ] CrowdSec using SSL connections
- [ ] PostgreSQL successfully restarted
- [ ] SSL verified as enabled
- [ ] Secure connections tested and working
- [ ] Connection logs reviewed for errors

## References

- [PostgreSQL SSL Documentation](https://www.postgresql.org/docs/current/ssl-tcp.html)
- [PostgreSQL Authentication Methods](https://www.postgresql.org/docs/current/auth-methods.html)
- [SCRAM-SHA-256 Authentication](https://www.postgresql.org/docs/current/sasl-authentication.html)
- [pg_hba.conf Configuration](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)

## Support

For issues or questions:
1. Check PostgreSQL logs: `docker compose logs postgres`
2. Review this documentation
3. Check PostgreSQL official documentation
4. Open an issue in the project repository
