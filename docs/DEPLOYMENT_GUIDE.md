# Jacker VPS Deployment Guide

## Overview

The `deploy-to-vps.sh` script provides automated, zero-downtime deployment of Jacker to remote VPS environments. It handles validation, file transfer, backup, deployment, and rollback with comprehensive error handling.

## Features

- **Pre-deployment Validation**: Verifies local environment and dependencies before deployment
- **SSH Connectivity Testing**: Ensures remote access before proceeding
- **Automatic Backup**: Creates timestamped backups before deployment (keeps last 5)
- **Efficient Transfer**: Uses rsync with intelligent exclusions for fast, incremental updates
- **Permission Management**: Automatically sets correct permissions on remote files
- **Smart Deployment**: Detects first-time setup vs updates and runs appropriate commands
- **Post-deployment Validation**: Verifies services are running and healthy
- **Automatic Rollback**: Reverts to previous version if deployment fails
- **Comprehensive Logging**: Timestamped logs for audit and troubleshooting
- **Idempotent**: Safe to run multiple times without side effects

## Prerequisites

### Local Machine

- Bash 4.0+
- rsync
- ssh client
- Docker (for local validation)

```bash
# Ubuntu/Debian
sudo apt-get install rsync openssh-client docker.io

# macOS (using Homebrew)
brew install rsync
```

### Remote VPS

- Ubuntu 20.04+ or Debian 11+ recommended
- SSH key authentication configured
- User with sudo privileges (preferably passwordless sudo)
- Docker and Docker Compose installed
- Minimum 4GB RAM, 20GB disk space

## Initial Setup

### 1. Configure SSH Access

```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy key to VPS
ssh-copy-id ubuntu@vps1.jacarsystems.net

# Test connection
ssh ubuntu@vps1.jacarsystems.net "echo 'Connection successful'"
```

### 2. Configure Passwordless Sudo (Recommended)

On the VPS:

```bash
# Edit sudoers file
sudo visudo

# Add this line (replace 'ubuntu' with your username)
ubuntu ALL=(ALL) NOPASSWD: ALL
```

### 3. Prepare Local Environment

```bash
# Navigate to Jacker directory
cd /path/to/jacker

# Ensure validation script is executable
chmod +x scripts/validate.sh

# Run local validation
./scripts/validate.sh
```

## Usage

### Basic Deployment

Deploy to default VPS:

```bash
./scripts/deploy-to-vps.sh
```

### Custom VPS Host

Deploy to different host:

```bash
./scripts/deploy-to-vps.sh --host user@vps2.example.com
```

### Dry Run (Testing)

Preview what would be done without making changes:

```bash
./scripts/deploy-to-vps.sh --dry-run
```

### Verbose Mode

Enable detailed logging output:

```bash
./scripts/deploy-to-vps.sh --verbose
```

### Skip Validation

Skip pre-deployment validation (not recommended for production):

```bash
./scripts/deploy-to-vps.sh --skip-validation
```

### Force Mode

Skip confirmation prompts:

```bash
./scripts/deploy-to-vps.sh --force
```

### Rollback

Revert to previous deployment:

```bash
./scripts/deploy-to-vps.sh --rollback
```

## Deployment Process

The script follows these phases:

### Phase 1: Pre-deployment Validation
- Checks for required dependencies (rsync, ssh, docker)
- Validates local Jacker directory structure
- Runs `validate.sh` to verify configuration
- Confirms critical files are present

### Phase 2: SSH Connectivity Test
- Tests SSH connection to VPS
- Verifies sudo privileges
- Ensures remote access is working

### Phase 3: Remote Backup
- Checks if deployment exists on VPS
- Creates timestamped backup if found
- Cleans old backups (keeps last 5)
- Stores deployment metadata

### Phase 4: File Transfer
- Uses rsync for efficient, incremental transfer
- Excludes non-essential files (see Exclusions below)
- Retries up to 3 times on failure
- Preserves file attributes and permissions

### Phase 5: Permission Setup
- Makes scripts executable
- Creates necessary directories
- Sets secure permissions (700 for secrets/)
- Configures proper ownership

### Phase 6: Remote Deployment
- Detects deployment type (init vs update)
- First deployment: Runs `./jacker init --auto`
- Updates: Runs `./jacker update`
- Restarts services
- Monitors execution output

### Phase 7: Post-deployment Validation
- Checks service status
- Runs health checks
- Waits for services to stabilize
- Verifies container health

### Phase 8: Cleanup & Reporting
- Removes temporary files
- Generates deployment summary
- Provides next steps and troubleshooting info

## Files Excluded from Transfer

The following are automatically excluded to reduce transfer size and protect VPS-specific configurations:

- `data/` - Service data (databases, volumes)
- `.git/` - Version control history
- `*.log` - Log files
- `logs/` - Log directory
- `.env` - Environment file (created on VPS)
- `secrets/*.txt` - Secret files (regenerated on VPS)
- `secrets/*.key` - SSL keys
- `backups/` - Backup archives
- `node_modules/` - Node.js dependencies
- `.cache/`, `.local/`, `.config/` - Cache directories
- `__pycache__/`, `*.pyc` - Python cache
- IDE files (`.vscode/`, `.idea/`)
- Temporary files (`*.tmp`, `*.bak`, `*.old`)

## Directory Structure on VPS

After deployment:

```
/opt/jacker/                  # Main application directory
├── docker-compose.yml        # Compose configuration
├── jacker                    # Main CLI script
├── scripts/                  # Management scripts
├── config/                   # Service configurations
├── data/                     # Service data (created on VPS)
├── secrets/                  # Secrets (created on VPS)
├── logs/                     # Application logs
└── .env                      # Environment (created on VPS)

/opt/jacker-backups/          # Backup directory
├── jacker-backup-20251017_120000/
├── jacker-backup-20251017_140000/
└── ...                       # Last 5 backups kept
```

## Logging

### Local Logs

Deployment logs are saved locally:

```
/path/to/jacker/logs/deploy-YYYYMMDD_HHMMSS.log
```

### Remote Logs

VPS application logs:

```bash
# View deployment logs on VPS
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker logs"

# View specific service logs
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker logs traefik -f"
```

## Backup Management

### Automatic Backups

- Created before each deployment
- Timestamped: `jacker-backup-YYYYMMDD_HHMMSS`
- Last 5 backups retained automatically
- Includes deployment metadata

### Manual Backup

Create manual backup on VPS:

```bash
ssh ubuntu@vps1.jacarsystems.net
cd /opt/jacker
./jacker backup
```

### List Available Backups

```bash
ssh ubuntu@vps1.jacarsystems.net "ls -lh /opt/jacker-backups/"
```

## Rollback Procedure

### Automatic Rollback

If deployment fails, the script automatically attempts rollback.

### Manual Rollback

Roll back to previous version:

```bash
# Using deployment script
./scripts/deploy-to-vps.sh --rollback

# Manually on VPS
ssh ubuntu@vps1.jacarsystems.net
cd /opt/jacker
./jacker restore /opt/jacker-backups/jacker-backup-20251017_120000
```

## Troubleshooting

### SSH Connection Failed

```bash
# Check SSH key is loaded
ssh-add -l

# Test connection manually
ssh -v ubuntu@vps1.jacarsystems.net

# Check firewall
telnet vps1.jacarsystems.net 22
```

### Validation Failed

```bash
# Run validation locally
./scripts/validate.sh

# Check specific issues in output
# Common fixes:
chmod 600 .env secrets/*
```

### Transfer Failed

```bash
# Check network connectivity
ping vps1.jacarsystems.net

# Verify rsync is installed
ssh ubuntu@vps1.jacarsystems.net "which rsync"

# Check remote disk space
ssh ubuntu@vps1.jacarsystems.net "df -h /opt"
```

### Deployment Failed

```bash
# Check remote logs
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker logs --tail 100"

# Check service status
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker status"

# Run health checks
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker health --verbose"
```

### Rollback Failed

If automatic rollback fails:

```bash
# SSH to VPS
ssh ubuntu@vps1.jacarsystems.net

# Stop services
cd /opt/jacker
./jacker stop

# Manually restore from backup
sudo rm -rf /opt/jacker
sudo cp -a /opt/jacker-backups/jacker-backup-YYYYMMDD_HHMMSS /opt/jacker
sudo chown -R $USER:$(id -gn) /opt/jacker

# Start services
cd /opt/jacker
./jacker start
```

## Best Practices

### Before Deployment

1. **Test locally first**: Ensure everything works in development
2. **Run validation**: `./scripts/validate.sh`
3. **Dry run**: `./scripts/deploy-to-vps.sh --dry-run`
4. **Check VPS status**: Verify current deployment is healthy
5. **Backup confirmation**: Ensure backups are available

### During Deployment

1. **Monitor output**: Watch for errors or warnings
2. **Check logs**: Review deployment log in real-time
3. **Verify services**: Confirm services restart successfully
4. **Health checks**: Ensure all health checks pass

### After Deployment

1. **Verify services**: `ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker status"`
2. **Check logs**: Look for any errors or warnings
3. **Run health checks**: `ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker health"`
4. **Test functionality**: Verify application is working correctly
5. **Monitor performance**: Watch metrics for anomalies

### Maintenance

1. **Regular deployments**: Keep VPS updated with latest changes
2. **Backup retention**: Monitor backup disk usage
3. **Log rotation**: Implement log rotation on VPS
4. **Security updates**: Keep VPS system packages updated
5. **Capacity planning**: Monitor disk and memory usage

## Security Considerations

### SSH Key Management

- Use strong SSH keys (ED25519 or RSA 4096-bit)
- Protect private keys with passphrase
- Use ssh-agent for key management
- Rotate keys periodically

### Secrets Handling

- Never commit secrets to git
- Use `.env` for local development only
- Regenerate secrets on VPS using `./jacker secrets generate`
- Use Docker secrets for production credentials

### VPS Hardening

- Configure firewall (ufw or iptables)
- Disable password authentication
- Limit SSH access by IP if possible
- Enable automatic security updates
- Use CrowdSec for intrusion prevention

## Advanced Usage

### Custom Remote Directory

Deploy to non-standard directory:

```bash
./scripts/deploy-to-vps.sh --remote-dir /home/user/jacker
```

### Custom Backup Directory

Use different backup location:

```bash
./scripts/deploy-to-vps.sh --backup-dir /mnt/backups/jacker
```

### Multiple VPS Environments

Deploy to different environments:

```bash
# Production
./scripts/deploy-to-vps.sh --host ubuntu@prod.example.com

# Staging
./scripts/deploy-to-vps.sh --host ubuntu@staging.example.com

# Development
./scripts/deploy-to-vps.sh --host ubuntu@dev.example.com --skip-validation
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy to VPS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H vps1.jacarsystems.net >> ~/.ssh/known_hosts

      - name: Deploy to VPS
        run: |
          ./scripts/deploy-to-vps.sh --force --verbose
```

## Exit Codes

- `0` - Success
- `1` - Validation error
- `2` - Transfer error
- `3` - Deployment error
- `4` - Rollback error

Use exit codes in scripts:

```bash
if ./scripts/deploy-to-vps.sh; then
    echo "Deployment successful"
else
    echo "Deployment failed with code $?"
    exit 1
fi
```

## FAQ

### Q: Can I run this from CI/CD?

Yes, use `--force` to skip prompts and configure SSH keys in CI environment.

### Q: What happens to existing data on VPS?

Data in `data/` directory is preserved. Only application files are updated.

### Q: How do I update environment variables on VPS?

SSH to VPS and edit `.env` manually, then restart services:

```bash
ssh ubuntu@vps1.jacarsystems.net
cd /opt/jacker
nano .env
./jacker restart
```

### Q: Can I deploy to multiple VPS simultaneously?

Yes, run multiple instances with different `--host` parameters.

### Q: What if deployment hangs?

- Check network connectivity
- Verify VPS has sufficient resources
- Check for port conflicts on VPS
- Review logs for stuck services

### Q: How do I clean up old backups manually?

```bash
ssh ubuntu@vps1.jacarsystems.net
cd /opt/jacker-backups
ls -lh
sudo rm -rf jacker-backup-YYYYMMDD_HHMMSS
```

## Support

For issues or questions:

1. Review deployment logs
2. Check Jacker documentation
3. Verify VPS system logs: `ssh ubuntu@vps1.jacarsystems.net "journalctl -xe"`
4. Open GitHub issue with logs and error details

## Related Documentation

- [Jacker Main README](../README.md)
- [Security Documentation](SECURITY.md)
- [Secrets Management](SECRETS_MANAGEMENT.md)
- [PostgreSQL Security](POSTGRESQL_SECURITY.md)

## Version History

- **v1.0.0** (2025-10-17): Initial release
  - Automated deployment
  - Backup and rollback
  - Comprehensive validation
  - Error handling and logging
