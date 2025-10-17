# Jacker Deployment Scripts

## Overview

This directory contains deployment and management scripts for Jacker.

## Deployment Script

### deploy-to-vps.sh

**Purpose**: Automated deployment of Jacker to remote VPS with zero-downtime capability.

**Location**: `/workspaces/jacker/scripts/deploy-to-vps.sh`

**Version**: 1.0.0

**Size**: 884 lines, 25KB

### Quick Start

```bash
# Basic deployment to default VPS
./scripts/deploy-to-vps.sh

# Test deployment (dry run)
./scripts/deploy-to-vps.sh --dry-run

# Deploy to custom host
./scripts/deploy-to-vps.sh --host user@your-vps.com

# Rollback failed deployment
./scripts/deploy-to-vps.sh --rollback
```

### Key Features

#### ✅ Pre-deployment Checks
- Validates all dependencies (rsync, ssh, docker)
- Runs `validate.sh` for comprehensive checks
- Tests SSH connectivity before proceeding
- Verifies critical files are present

#### ✅ Backup System
- Automatic backup before each deployment
- Timestamped backups with deployment metadata
- Automatic cleanup (keeps last 5 backups)
- Fast rollback capability

#### ✅ Efficient File Transfer
- Uses rsync for incremental updates
- Intelligent exclusions (data/, .git/, logs/, etc.)
- Retry logic (up to 3 attempts)
- Progress reporting

#### ✅ Remote Deployment
- Automatic detection of init vs update
- Runs appropriate jacker commands
- Sets correct permissions automatically
- Manages secrets securely

#### ✅ Error Handling
- Automatic rollback on failure
- Detailed error messages
- Comprehensive logging
- Clear exit codes

#### ✅ Post-deployment Validation
- Service health checks
- Status verification
- Stability monitoring
- Performance validation

### Excluded Files

The following are automatically excluded from transfer:

```
data/              # Service data volumes
.git/              # Version control
*.log              # Log files
logs/              # Log directory
.env               # Environment (created on VPS)
secrets/*.txt      # Secrets (regenerated on VPS)
backups/           # Backup archives
node_modules/      # Dependencies
.cache/            # Cache directories
__pycache__/       # Python cache
.vscode/           # IDE files
*.tmp, *.bak       # Temporary files
```

### Deployment Flow

```
1. Pre-deployment Validation
   ├── Check dependencies
   ├── Validate local environment
   └── Run validate.sh

2. SSH Connectivity Test
   ├── Test connection
   └── Verify sudo access

3. Backup Creation
   ├── Check existing deployment
   ├── Create timestamped backup
   └── Clean old backups

4. File Transfer (rsync)
   ├── Exclude non-essential files
   ├── Incremental sync
   └── Retry on failure

5. Permission Setup
   ├── Make scripts executable
   ├── Create directories
   └── Set ownership

6. Remote Deployment
   ├── Detect deployment type
   ├── Run init or update
   └── Restart services

7. Post-deployment Validation
   ├── Check service status
   ├── Run health checks
   └── Verify stability

8. Cleanup & Report
   ├── Remove temp files
   ├── Generate summary
   └── Provide next steps
```

### Command-Line Options

```
-h, --host HOST         VPS hostname
-d, --remote-dir DIR    Remote directory (default: /opt/jacker)
-b, --backup-dir DIR    Backup directory (default: /opt/jacker-backups)
--dry-run               Preview without executing
--force                 Skip confirmation prompts
--rollback              Rollback to previous version
--skip-validation       Skip pre-deployment checks
-v, --verbose           Enable detailed logging
--help                  Show help message
```

### Exit Codes

```
0 - Success
1 - Validation error
2 - Transfer error
3 - Deployment error
4 - Rollback error
```

### Logging

All deployments are logged with timestamps:

**Local**: `/path/to/jacker/logs/deploy-YYYYMMDD_HHMMSS.log`

Example log entry:
```
[2025-10-17 11:34:42] [INFO] Starting deployment
[2025-10-17 11:34:43] [SUCCESS] SSH connection successful
[2025-10-17 11:34:45] [STEP] Creating Remote Backup
```

### Requirements

#### Local System
- Bash 4.0+
- rsync
- ssh client
- Docker (for validation)

#### Remote VPS
- Ubuntu 20.04+ or Debian 11+
- SSH key authentication
- Sudo privileges
- Docker & Docker Compose
- 4GB+ RAM, 20GB+ disk

### Security Features

- SSH key authentication only
- Excludes secrets from transfer
- Secure permission handling (700 for secrets/)
- Backup before changes
- Automatic rollback on failure
- Comprehensive audit logging

### Idempotency

The script is fully idempotent:

- Safe to run multiple times
- Won't duplicate data
- Preserves existing configurations
- Updates only changed files
- Creates backups each time

### Error Recovery

If deployment fails:

1. **Automatic Rollback**: Script attempts to restore previous version
2. **Manual Rollback**: Run `./scripts/deploy-to-vps.sh --rollback`
3. **Check Logs**: Review `logs/deploy-*.log` for details
4. **Verify Backup**: Check `/opt/jacker-backups/` on VPS

### Examples

#### Production Deployment

```bash
# Full deployment with validation
./scripts/deploy-to-vps.sh --host ubuntu@prod.example.com --verbose

# Expected output:
# ✓ All dependencies available
# ✓ Pre-deployment validation passed
# ✓ SSH connection successful
# ✓ Backup created: jacker-backup-20251017_120000
# ✓ File transfer completed
# ✓ Permissions configured
# ✓ Update completed
# ✓ Services restarted
# ✓ Health checks passed
#
# Deployment Summary
# Status:        SUCCESS
# Duration:      42s
```

#### Staging Deployment

```bash
# Quick deployment to staging (skip validation)
./scripts/deploy-to-vps.sh \
    --host ubuntu@staging.example.com \
    --skip-validation \
    --force
```

#### Dry Run

```bash
# Test what would happen without making changes
./scripts/deploy-to-vps.sh --dry-run

# Output shows all steps that would execute
# [DRY RUN] Would test SSH connection
# [DRY RUN] Would create backup
# [DRY RUN] Would transfer files
# etc.
```

#### Rollback

```bash
# Rollback to previous deployment
./scripts/deploy-to-vps.sh --rollback

# Confirm when prompted:
# Are you sure you want to rollback? (yes/no): yes
# ✓ Files restored from backup
# ✓ Services started
# ✓ Rollback completed successfully
```

### Troubleshooting

#### SSH Connection Failed

```bash
# Check SSH key
ssh-add -l

# Test connection
ssh ubuntu@vps1.jacarsystems.net "echo test"

# Check logs
cat logs/deploy-*.log | grep SSH
```

#### Transfer Failed

```bash
# Check network
ping vps1.jacarsystems.net

# Check disk space
ssh ubuntu@vps1.jacarsystems.net "df -h"

# Manual rsync test
rsync -avz --dry-run ./ ubuntu@vps1.jacarsystems.net:/tmp/test/
```

#### Deployment Failed

```bash
# Check remote logs
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker logs --tail 100"

# Check service status
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker status"

# Run health checks
ssh ubuntu@vps1.jacarsystems.net "cd /opt/jacker && ./jacker health -v"
```

### Integration

#### CI/CD Example (GitHub Actions)

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
          echo "${{ secrets.SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

      - name: Deploy
        run: ./scripts/deploy-to-vps.sh --force --verbose
```

#### Cron Example

```bash
# Daily deployment at 2 AM
0 2 * * * cd /path/to/jacker && ./scripts/deploy-to-vps.sh --force >> /var/log/jacker/deploy-cron.log 2>&1
```

### Best Practices

1. **Always test with --dry-run first**
2. **Ensure backups are available before deployment**
3. **Monitor logs during deployment**
4. **Verify services after deployment**
5. **Keep at least 3 backups**
6. **Use --verbose for troubleshooting**
7. **Test rollback procedure periodically**

### Documentation

Full deployment guide: [`/docs/DEPLOYMENT_GUIDE.md`](../docs/DEPLOYMENT_GUIDE.md)

Topics covered:
- Detailed prerequisites
- Step-by-step setup
- Advanced usage
- Security considerations
- Troubleshooting guide
- FAQ

### Support

For issues:
1. Check deployment logs
2. Review [DEPLOYMENT_GUIDE.md](../docs/DEPLOYMENT_GUIDE.md)
3. Test with --dry-run and --verbose
4. Verify VPS resources and connectivity
5. Check GitHub issues

### Version History

- **v1.0.0** (2025-10-17)
  - Initial release
  - Full automation
  - Backup & rollback
  - Comprehensive validation
  - Error handling
  - Production-ready

---

**Production-ready** ✅ **Idempotent** ✅ **Tested** ✅
