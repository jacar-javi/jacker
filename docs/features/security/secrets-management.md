# Secrets Management Guide

Complete guide to managing sensitive credentials in Jacker using Docker secrets for enhanced security.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Secret Types](#secret-types)
- [Implementation Details](#implementation-details)
- [Rotation Procedures](#rotation-procedures)
- [Backup and Recovery](#backup-and-recovery)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)

## Overview

Jacker uses Docker Compose file-based secrets to manage sensitive credentials securely. This approach:

- **Separates secrets from code** - No plaintext credentials in configuration files
- **Provides file-level security** - Secrets stored with restrictive permissions (600)
- **Enables rotation** - Easy to update credentials without modifying compose files
- **Supports auditing** - Track when secrets were created/modified
- **Prevents exposure** - `.gitignore` prevents accidental commits

### Why Not Environment Variables?

Environment variables have several security drawbacks:
- Visible in `docker inspect` and process lists
- Logged in container output and debugging tools
- Difficult to rotate without redeploying
- No built-in access control

Docker secrets address these issues by:
- Mounting secrets as read-only files in `/run/secrets/`
- Never exposing values in environment or logs
- Supporting easy rotation via file updates

## Architecture

### Secret Storage

```
jacker/
├── secrets/                    # Secret files directory (mode 700)
│   ├── .gitignore              # Prevents commits
│   ├── README.md               # Usage instructions
│   ├── oauth_client_secret     # OAuth2 client secret (mode 600)
│   ├── oauth_cookie_secret     # OAuth2 cookie encryption (mode 600)
│   ├── postgres_password       # PostgreSQL password (mode 600)
│   ├── redis_password          # Redis authentication (mode 600)
│   ├── crowdsec_lapi_key       # CrowdSec API key (mode 600)
│   ├── crowdsec_bouncer_key    # Traefik bouncer key (mode 600)
│   ├── grafana_admin_password  # Grafana admin password (mode 600)
│   └── ...                     # Additional secrets
├── docker-compose.yml          # Secrets defined at root level
└── compose/                    # Service-specific configurations
    ├── postgres.yml            # References postgres_password secret
    ├── redis.yml               # References redis_password secret
    ├── oauth.yml               # References OAuth secrets
    └── grafana.yml             # References grafana_admin_password
```

### Secret Definition

In `/workspaces/jacker/docker-compose.yml`:

```yaml
secrets:
  # OAuth secrets
  oauth_client_secret:
    file: ${SECRETSDIR}/oauth_client_secret
  oauth_cookie_secret:
    file: ${SECRETSDIR}/oauth_cookie_secret

  # Database secrets
  postgres_password:
    file: ${SECRETSDIR}/postgres_password
  redis_password:
    file: ${SECRETSDIR}/redis_password

  # Security secrets
  crowdsec_bouncer_key:
    file: ${SECRETSDIR}/crowdsec_bouncer_key

  # Monitoring secrets
  grafana_admin_password:
    file: ${SECRETSDIR}/grafana_admin_password
```

### Secret Consumption

Services reference secrets in their compose files:

```yaml
services:
  postgres:
    secrets:
      - postgres_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password

  oauth:
    secrets:
      - oauth_client_secret
      - oauth_cookie_secret
    environment:
      OAUTH2_PROXY_CLIENT_SECRET_FILE: /run/secrets/oauth_client_secret
      OAUTH2_PROXY_COOKIE_SECRET_FILE: /run/secrets/oauth_cookie_secret
```

## Quick Start

### Initial Setup

1. **Initialize secrets from `.env` file:**

```bash
./scripts/init-secrets.sh
```

This script:
- Reads credentials from `.env` file
- Creates individual secret files in `secrets/` directory
- Sets proper permissions (600 on files, 700 on directory)
- Generates random values for missing secrets

2. **Verify secret creation:**

```bash
ls -la secrets/
# Should show files with permissions -rw-------
```

3. **Update production secrets:**

```bash
# Replace test/generated values with production credentials
echo "YOUR-PRODUCTION-SECRET" > secrets/oauth_client_secret
chmod 600 secrets/oauth_client_secret
```

4. **Start services:**

```bash
docker compose up -d
```

### Migration from .env

If you're migrating from environment variables:

1. **Run initialization script:**
```bash
./scripts/init-secrets.sh
```

2. **Verify services can read secrets:**
```bash
docker compose config | grep -A 5 secrets
```

3. **Test service startup:**
```bash
docker compose up -d
docker compose logs oauth postgres redis grafana
```

4. **Optional: Remove secrets from `.env`:**
```bash
# Comment out or remove sensitive values
# Keep non-secret configuration in .env
sed -i 's/^POSTGRES_PASSWORD=.*/# POSTGRES_PASSWORD=  # Moved to secrets\/postgres_password/' .env
sed -i 's/^REDIS_PASSWORD=.*/# REDIS_PASSWORD=  # Moved to secrets\/redis_password/' .env
```

## Secret Types

### OAuth Secrets

| Secret | Purpose | Used By | Generation |
|--------|---------|---------|------------|
| `oauth_client_secret` | OAuth2 provider client secret | oauth2-proxy | From OAuth provider (Google/GitHub) |
| `oauth_cookie_secret` | Cookie encryption key | oauth2-proxy | `openssl rand -base64 32` |
| `traefik_forward_oauth` | Traefik forward auth token | Traefik, oauth2-proxy | `openssl rand -base64 32` |

**Setup OAuth Client Secret:**
```bash
# Google OAuth
# 1. Visit https://console.cloud.google.com/apis/credentials
# 2. Create OAuth 2.0 Client ID
# 3. Add authorized redirect: https://oauth.yourdomain.com/oauth2/callback
# 4. Save client secret to file
echo "YOUR-GOOGLE-CLIENT-SECRET" > secrets/oauth_client_secret
chmod 600 secrets/oauth_client_secret
```

### Database Secrets

| Secret | Purpose | Used By | Generation |
|--------|---------|---------|------------|
| `postgres_password` | PostgreSQL root password | postgres, crowdsec, authentik | `openssl rand -base64 32` |
| `redis_password` | Redis authentication | redis, oauth2-proxy, grafana | `openssl rand -base64 32` |

**Generate Database Passwords:**
```bash
# PostgreSQL password
openssl rand -base64 32 > secrets/postgres_password
chmod 600 secrets/postgres_password

# Redis password
openssl rand -base64 32 > secrets/redis_password
chmod 600 secrets/redis_password
```

### Security Secrets

| Secret | Purpose | Used By | Generation |
|--------|---------|---------|------------|
| `crowdsec_lapi_key` | CrowdSec Local API authentication | CrowdSec LAPI | `openssl rand -hex 32` |
| `crowdsec_bouncer_key` | Traefik bouncer authentication | Traefik bouncer, CrowdSec | `openssl rand -hex 32` |

### Monitoring Secrets

| Secret | Purpose | Used By | Generation |
|--------|---------|---------|------------|
| `grafana_admin_password` | Grafana admin user password | Grafana | `openssl rand -base64 32` |
| `alertmanager_gmail_password` | Gmail app password for alerts | AlertManager | From Gmail app passwords |

## Implementation Details

### Service-Specific Implementations

#### PostgreSQL (Already Implemented)

PostgreSQL uses the `POSTGRES_PASSWORD_FILE` environment variable natively:

```yaml
# compose/postgres.yml
services:
  postgres:
    secrets:
      - postgres_password
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
```

#### Redis (Updated)

Redis doesn't support password files natively, so we use an entrypoint wrapper:

```yaml
# compose/redis.yml
services:
  redis:
    secrets:
      - redis_password
    entrypoint: ["/bin/sh", "-c"]
    command: >
      "REDIS_PASSWORD=$$(cat /run/secrets/redis_password) &&
      redis-server --requirepass \"$$REDIS_PASSWORD\" ..."
```

#### OAuth2-Proxy (Updated)

OAuth2-Proxy supports `_FILE` suffix for secret files:

```yaml
# compose/oauth.yml
services:
  oauth:
    secrets:
      - oauth_client_secret
      - oauth_cookie_secret
      - redis_password
    environment:
      OAUTH2_PROXY_CLIENT_SECRET_FILE: /run/secrets/oauth_client_secret
      OAUTH2_PROXY_COOKIE_SECRET_FILE: /run/secrets/oauth_cookie_secret
      OAUTH2_PROXY_REDIS_PASSWORD_FILE: /run/secrets/redis_password
```

#### Grafana (Updated)

Grafana supports `__FILE` suffix (double underscore) for secrets:

```yaml
# compose/grafana.yml
services:
  grafana:
    secrets:
      - grafana_admin_password
      - redis_password
    entrypoint: ["/bin/sh", "-c"]
    command: >
      "REDIS_PASSWORD=$$(cat /run/secrets/redis_password) &&
      export GF_REMOTE_CACHE_CONNSTR=\"addr=redis:6379,password=$$REDIS_PASSWORD\" &&
      exec /run.sh"
    environment:
      GF_SECURITY_ADMIN_PASSWORD__FILE: /run/secrets/grafana_admin_password
```

## Rotation Procedures

### When to Rotate

- **Immediately**: After suspected compromise or unauthorized access
- **Regularly**:
  - OAuth secrets: Monthly
  - Database passwords: Quarterly
  - API keys: Quarterly
  - Long-lived tokens: Annually
- **Team changes**: When team members leave or change roles

### Rotation Process

#### Automated Rotation (Recommended)

```bash
# Rotate all secrets with new random values
./scripts/init-secrets.sh --rotate

# Restart services to apply new secrets
docker compose down
docker compose up -d
```

#### Manual Rotation

**Step 1: Generate new secret**
```bash
# Example: Rotate PostgreSQL password
NEW_PASSWORD=$(openssl rand -base64 32)
echo "$NEW_PASSWORD" > secrets/postgres_password.new
chmod 600 secrets/postgres_password.new
```

**Step 2: Update dependent services**
```bash
# For databases, you may need to update the password in the DB first
docker compose exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW_PASSWORD';"
```

**Step 3: Replace secret file**
```bash
mv secrets/postgres_password.new secrets/postgres_password
```

**Step 4: Restart affected services**
```bash
docker compose restart postgres postgres-exporter
```

#### OAuth Client Secret Rotation

OAuth secrets require updates in both Jacker and the OAuth provider:

```bash
# 1. Generate new client secret in OAuth provider console
#    (Google: https://console.cloud.google.com/apis/credentials)

# 2. Update secret file
echo "NEW-CLIENT-SECRET-FROM-PROVIDER" > secrets/oauth_client_secret
chmod 600 secrets/oauth_client_secret

# 3. Restart OAuth service
docker compose restart oauth

# 4. Test authentication
curl -I https://oauth.yourdomain.com/ping
```

### Rotation Checklist

- [ ] Backup current secrets before rotation
- [ ] Generate new secure random values
- [ ] Update secrets in secret files
- [ ] Update external systems (OAuth providers, SMTP, etc.)
- [ ] Restart affected services
- [ ] Verify service functionality
- [ ] Test authentication and access
- [ ] Update backup with new secrets
- [ ] Document rotation in change log

## Backup and Recovery

### Backup Secrets

**Encrypted Backup (GPG):**
```bash
# Create encrypted backup
tar -czf - secrets/ | gpg --symmetric --cipher-algo AES256 > secrets-backup-$(date +%Y%m%d).tar.gz.gpg

# Store backup securely (not in git repository)
mv secrets-backup-*.tar.gz.gpg ~/secure-backups/
```

**Encrypted Backup (age):**
```bash
# Install age: https://github.com/FiloSottile/age
# Create encrypted backup
tar -czf - secrets/ | age -p > secrets-backup-$(date +%Y%m%d).tar.gz.age
```

### Restore Secrets

**From GPG Backup:**
```bash
# Restore from encrypted backup
gpg --decrypt secrets-backup-YYYYMMDD.tar.gz.gpg | tar -xzf -

# Fix permissions
chmod 700 secrets/
chmod 600 secrets/*
```

**From age Backup:**
```bash
# Restore from age backup
age -d secrets-backup-YYYYMMDD.tar.gz.age | tar -xzf -

# Fix permissions
chmod 700 secrets/
chmod 600 secrets/*
```

### Disaster Recovery

1. **Restore from backup:**
```bash
gpg --decrypt secrets-backup.tar.gz.gpg | tar -xzf -
```

2. **Or regenerate all secrets:**
```bash
./scripts/init-secrets.sh --force
```

3. **Update external dependencies:**
   - Recreate OAuth client secret in provider console
   - Update SMTP credentials if changed
   - Regenerate API keys in third-party services

4. **Restart all services:**
```bash
docker compose down
docker compose up -d
```

## Troubleshooting

### Secret File Not Found

**Symptom:** Service fails with "secret not found" error

**Solution:**
```bash
# Check if secret file exists
ls -la secrets/

# Regenerate missing secrets
./scripts/init-secrets.sh

# Verify secret is defined in docker-compose.yml
docker compose config | grep -A 10 "^secrets:"
```

### Permission Denied

**Symptom:** Service cannot read secret file

**Solution:**
```bash
# Fix directory permissions
chmod 700 secrets/

# Fix file permissions
chmod 600 secrets/*

# Verify ownership (should match your user)
ls -la secrets/
```

### Service Cannot Read Secret

**Symptom:** Service starts but authentication fails

**Solution:**
```bash
# Check if secret is mounted
docker compose exec SERVICE ls -la /run/secrets/

# Verify secret content (be careful, this exposes the secret)
docker compose exec SERVICE cat /run/secrets/SECRET_NAME

# Check service logs
docker compose logs SERVICE
```

### OAuth Authentication Fails

**Symptom:** OAuth redirects fail or show "invalid client"

**Solution:**
```bash
# Verify OAuth client secret matches provider
cat secrets/oauth_client_secret

# Check OAuth2-Proxy logs
docker compose logs oauth

# Verify OAuth provider configuration
# - Redirect URI: https://oauth.yourdomain.com/oauth2/callback
# - Client ID matches .env
# - Client secret matches secrets/oauth_client_secret
```

### Database Connection Fails

**Symptom:** Services cannot connect to PostgreSQL/Redis

**Solution:**
```bash
# Verify database password secret
docker compose exec postgres cat /run/secrets/postgres_password

# Test database connection
docker compose exec postgres psql -U postgres -d postgres

# Check if password in database matches secret
docker compose exec postgres psql -U postgres -c "SELECT 'OK' AS status;"

# Reset database password if needed
NEW_PASS=$(cat secrets/postgres_password)
docker compose exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD '$NEW_PASS';"
```

## Security Best Practices

### Secret Generation

✅ **DO:**
- Use cryptographically secure random generation
- Generate unique secrets for each service
- Use sufficient length (32+ bytes for passwords)
- Store secrets in encrypted backups
- Rotate secrets regularly

❌ **DON'T:**
- Use predictable values (password123, admin, etc.)
- Reuse secrets across services
- Store secrets in version control
- Share secrets via insecure channels
- Log secret values

### Secret Storage

✅ **DO:**
- Use restrictive file permissions (600 for files, 700 for directory)
- Keep secrets directory outside of version control
- Encrypt backups of secrets directory
- Use separate secrets for dev/staging/production
- Limit access to secrets directory

❌ **DON'T:**
- Commit secrets to git
- Share secrets directory via network shares
- Include secrets in container images
- Store secrets on unencrypted volumes
- Grant write access to application users

### Secret Usage

✅ **DO:**
- Use Docker secrets with file-based references
- Inject secrets at runtime only
- Use secret scanning tools (gitleaks, truffleHog)
- Monitor access to secret files
- Audit secret usage regularly

❌ **DON'T:**
- Pass secrets as command-line arguments
- Log secret values in application logs
- Expose secrets in environment variables (when possible)
- Include secrets in error messages
- Cache secrets in memory longer than necessary

### Access Control

✅ **DO:**
- Implement principle of least privilege
- Use separate credentials for each service
- Require authentication for all services
- Enable audit logging for secret access
- Review access regularly

❌ **DON'T:**
- Use root passwords for application access
- Share administrative credentials
- Allow anonymous access to sensitive services
- Disable authentication in production
- Grant excessive permissions

### Monitoring and Auditing

✅ **DO:**
- Monitor failed authentication attempts
- Track secret file modifications
- Alert on unusual access patterns
- Log rotation activities
- Review audit logs regularly

❌ **DON'T:**
- Ignore authentication failures
- Skip logging for sensitive operations
- Allow unrestricted access attempts
- Disable security monitoring
- Ignore security alerts

## Related Documentation

- [Docker Secrets Documentation](https://docs.docker.com/engine/swarm/secrets/)
- [OAuth2-Proxy Configuration](https://oauth2-proxy.github.io/oauth2-proxy/)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/auth-password.html)
- [Redis Security](https://redis.io/docs/manual/security/)
- [Grafana Security](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/)

## Additional Resources

### Secret Generation Commands

```bash
# Generate 32-byte base64 secret (passwords, tokens)
openssl rand -base64 32

# Generate 64-byte base64 secret (encryption keys)
openssl rand -base64 64

# Generate hex secret (API keys)
openssl rand -hex 32

# Generate URL-safe token
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Generate UUID
uuidgen
```

### Verification Commands

```bash
# List all secrets with permissions
ls -lh secrets/

# Count secrets
find secrets/ -type f ! -name "README.md" ! -name ".gitignore" | wc -l

# Verify no secrets in git
git status secrets/

# Check secret references in compose
docker compose config | grep -A 5 secrets

# Verify mounted secrets in containers
docker compose exec SERVICE ls -la /run/secrets/
```

### Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Rotate OAuth secrets | Monthly | `./scripts/init-secrets.sh --rotate` |
| Rotate database passwords | Quarterly | Manual rotation per service |
| Backup secrets | Weekly | `tar -czf - secrets/ \| gpg --symmetric > backup.tar.gz.gpg` |
| Audit secret access | Monthly | Review service logs |
| Verify permissions | Weekly | `find secrets/ -type f ! -perm 600` |
| Test disaster recovery | Quarterly | Restore from backup in test environment |

---

**Last Updated:** 2025-10-16
**Version:** 1.0
**Maintainer:** Jacker Security Team
