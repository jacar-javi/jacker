# Secrets Directory

This directory stores sensitive data that should NEVER be committed to version control. All files except this README and .gitkeep are excluded via .gitignore.

## Purpose

Docker secrets provide a secure way to manage sensitive data such as:
- Passwords and API keys
- SSL certificates and private keys
- OAuth tokens and secrets
- Database credentials
- SMTP authentication

## Directory Structure

```
secrets/
├── .gitkeep                        # Ensures directory exists in git
├── .gitignore                      # Excludes all secrets from git
├── README.md                       # This file
└── [runtime secrets]               # Created during setup (all gitignored)
```

## Active Secrets

| File | Purpose | Used By |
|------|---------|---------|
| `oauth_cookie_secret` | OAuth2-proxy cookie encryption | OAuth2-Proxy |
| `postgres_password` | PostgreSQL root password | PostgreSQL, CrowdSec |
| `redis_password` | Redis authentication | Redis, OAuth2-Proxy |
| `crowdsec_lapi_key` | CrowdSec Local API key | CrowdSec LAPI |
| `crowdsec_bouncer_key` | Traefik bouncer API key | Traefik Bouncer |
| `grafana_admin_password` | Grafana admin password | Grafana |
| `portainer_secret` | Portainer agent secret | Portainer |
| `traefik_forward_oauth` | Traefik OAuth forward auth | Traefik |

### Optional Secrets (Authentik)

| File | Purpose | When Needed |
|------|---------|-------------|
| `authentik_secret_key` | Authentik encryption key | When using Authentik |
| `authentik_postgres_password` | Authentik database password | When using Authentik |
| `authentik_api_token` | Authentik API access | Homepage integration |

## Security Requirements

### File Permissions

```bash
# Directory (owner only)
chmod 700 /workspaces/jacker/secrets

# Files (owner read/write only)
chmod 600 /workspaces/jacker/secrets/*

# Verify permissions
ls -la /workspaces/jacker/secrets/
```

### Secret Generation

All secrets should be cryptographically secure:

```bash
# Generate 32-byte secret
openssl rand -base64 32

# Generate 64-byte secret
openssl rand -base64 64

# Generate hex secret
openssl rand -hex 32

# Generate URL-safe token
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

## Usage in Jacker

Secrets are automatically generated during setup:

```bash
# Initial setup generates all required secrets
./jacker init

# Regenerate specific secrets
./jacker secrets generate

# Validate existing secrets
./jacker secrets validate
```

## Important Security Notes

⚠️ **NEVER:**
- Commit secrets to git (check .gitignore)
- Share secrets via email or chat
- Log secret values in plain text
- Store secrets in Docker images
- Use weak or predictable values

✅ **ALWAYS:**
- Use strong random generation
- Rotate secrets regularly
- Backup encrypted secrets
- Monitor for exposed secrets
- Update secrets after team changes

## Backup and Recovery

### Backup Secrets (Encrypted)

```bash
# Backup with GPG encryption
tar -czf - secrets/ | gpg --symmetric --cipher-algo AES256 > secrets-backup.tar.gz.gpg

# Backup with age encryption
tar -czf - secrets/ | age -p > secrets-backup.tar.gz.age
```

### Restore Secrets

```bash
# Restore from GPG backup
gpg --decrypt secrets-backup.tar.gz.gpg | tar -xzf -

# Restore from age backup
age -d secrets-backup.tar.gz.age | tar -xzf -
```

## Secret Rotation

Regular rotation schedule:
- **Monthly:** OAuth secrets, API keys
- **Quarterly:** Database passwords
- **Annually:** Long-lived tokens
- **Immediately:** After any suspected compromise

## Troubleshooting

### Permission Denied

```bash
# Fix permissions
sudo chown -R $USER:$USER secrets/
chmod 700 secrets/
chmod 600 secrets/*
```

### Secret Not Found

```bash
# Regenerate missing secrets
./jacker secrets generate

# Or manually create
echo "$(openssl rand -base64 32)" > secrets/missing_secret
chmod 600 secrets/missing_secret
```

### Services Can't Read Secrets

Verify secrets are properly mounted in compose files and that services are configured to read from secret files rather than environment variables.

## Related Documentation

- [Docker Secrets Best Practices](https://docs.docker.com/engine/swarm/secrets/)
- [Security Configuration](../docs/security.md)
- [Environment Variables](../.env.defaults)
- [Main README](../README.md)
