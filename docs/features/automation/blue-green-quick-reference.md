# Blue-Green Deployment - Quick Reference

## Quick Start

```bash
# 1. Dry run first (always!)
./scripts/blue-green-deploy.sh <service> <cpu> <memory> --dry-run

# 2. Execute deployment
./scripts/blue-green-deploy.sh <service> <cpu> <memory>

# 3. Check status
./scripts/blue-green-deploy.sh status <service>

# 4. Rollback if needed
./scripts/blue-green-deploy.sh rollback <service>
```

## Common Commands

| Command | Example | Description |
|---------|---------|-------------|
| **Deploy** | `./scripts/blue-green-deploy.sh grafana 1.5 768M` | Update resource limits |
| **Dry Run** | `./scripts/blue-green-deploy.sh grafana 1.5 768M --dry-run` | Preview changes |
| **Status** | `./scripts/blue-green-deploy.sh status grafana` | Check deployment status |
| **Rollback** | `./scripts/blue-green-deploy.sh rollback grafana` | Revert to previous config |

## Resource Format

| Type | Format | Examples | Valid Range |
|------|--------|----------|-------------|
| **CPU** | `<number>` | `0.5`, `1.0`, `2.5` | `0.1` - `16.0` |
| **Memory** | `<number><unit>` | `512M`, `1024M`, `2G` | `64M` - `32G` |

## Options Cheat Sheet

| Option | Short | Description |
|--------|-------|-------------|
| `--dry-run` | - | Show changes without executing |
| `--timeout <sec>` | - | Health check timeout (default: 120s) |
| `--no-rollback` | - | Disable automatic rollback |
| `--force` | - | Skip safety checks (DANGEROUS) |
| `--no-drain` | - | Skip connection draining |
| `--metrics` | - | Export Prometheus metrics |
| `--help` | `-h` | Show help message |

## Deployment Phases

```
1. Preparation    → Validate service, get current limits
2. Deploy Green   → Scale to 2 replicas (Blue + Green)
3. Health Check   → Wait for Green to be healthy (120s)
4. Verify Traffic → Check Traefik load balancing
5. Drain & Remove → Remove Blue replica
6. Verification   → Final health check
```

## Service Categories

### ✓ Supported (Stateless)

- **Monitoring**: grafana, prometheus, loki, alertmanager, jaeger
- **Security**: traefik, oauth2-proxy, crowdsec
- **Tools**: portainer, homepage, vscode
- **Exporters**: node-exporter, blackbox-exporter

### ✗ Not Supported (Stateful)

- **Database**: postgres, postgres-exporter
- **Cache**: redis, redis-exporter, redis-commander
- **Proxy**: socket-proxy

**Use instead**: Master-replica, maintenance window, or rolling restart

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Validation error |
| `2` | Deployment failure |
| `3` | Rollback failure |
| `4` | Health check timeout |

## Health Check States

| State | Symbol | Meaning |
|-------|--------|---------|
| **healthy** | ✓ | Service working correctly |
| **starting** | ⏳ | Waiting for health check |
| **unhealthy** | ✗ | Health check failed |
| **none** | ⚠ | No health check defined |

## Common Examples

### Update Grafana

```bash
# Increase memory to 1GB
./scripts/blue-green-deploy.sh grafana 1.5 1024M

# Or use dry-run first
./scripts/blue-green-deploy.sh grafana 1.5 1024M --dry-run
```

### Update Traefik (High Priority)

```bash
# Use longer timeout for safety
./scripts/blue-green-deploy.sh traefik 2.5 1536M --timeout 180
```

### Update Prometheus (Large Service)

```bash
# No connection draining needed
./scripts/blue-green-deploy.sh prometheus 2.0 2048M --no-drain --timeout 180
```

### Update with Metrics

```bash
# Export deployment metrics
./scripts/blue-green-deploy.sh grafana 1.5 768M --metrics

# Metrics saved to: /var/log/jacker/blue-green-metrics.prom
```

## Troubleshooting Quick Fixes

### Health Check Timeout

```bash
# Increase timeout
./scripts/blue-green-deploy.sh <service> <cpu> <mem> --timeout 300
```

### Deployment Fails

```bash
# Check logs
docker-compose logs --tail=50 <service>

# Rollback
./scripts/blue-green-deploy.sh rollback <service>
```

### Not Enough Resources

```bash
# Check host resources
free -h
docker stats

# Use lower limits
./scripts/blue-green-deploy.sh <service> <lower_cpu> <lower_mem>
```

### Service Unhealthy After Deploy

```bash
# Immediate rollback
./scripts/blue-green-deploy.sh rollback <service>

# Check what went wrong
docker-compose logs <service>
```

## Best Practices Checklist

- [ ] Always dry-run first: `--dry-run`
- [ ] Check current usage: `docker stats <service>`
- [ ] Start with small increments (25% increase)
- [ ] Monitor during deployment: `docker-compose logs -f <service>`
- [ ] Verify health check works: `docker-compose ps <service>`
- [ ] Use custom timeout for slow services: `--timeout 300`
- [ ] Export metrics for tracking: `--metrics`
- [ ] Keep deployment logs: `--log-file /path/to/log`

## File Locations

| File | Path | Description |
|------|------|-------------|
| Script | `/workspaces/jacker/scripts/blue-green-deploy.sh` | Main script |
| Override | `/workspaces/jacker/docker-compose.blue-green.yml` | Generated config |
| Logs | `/var/log/jacker/blue-green.log` | Deployment logs |
| Metrics | `/var/log/jacker/blue-green-metrics.prom` | Prometheus metrics |

## One-Liners

```bash
# Deploy with all safety features
./scripts/blue-green-deploy.sh grafana 1.5 768M --timeout 180 --metrics

# Quick status check
./scripts/blue-green-deploy.sh status grafana

# Emergency rollback
./scripts/blue-green-deploy.sh rollback grafana

# Dry run with custom timeout
./scripts/blue-green-deploy.sh prometheus 2.0 2048M --timeout 300 --dry-run

# Deploy without connection draining (faster)
./scripts/blue-green-deploy.sh loki 1.0 1024M --no-drain

# Force deploy stateful service (NOT RECOMMENDED)
./scripts/blue-green-deploy.sh redis 1.0 512M --force
```

## Monitoring During Deployment

### Terminal 1: Run deployment
```bash
./scripts/blue-green-deploy.sh grafana 1.5 768M
```

### Terminal 2: Watch logs
```bash
docker-compose logs -f grafana
```

### Terminal 3: Monitor resources
```bash
watch -n 1 'docker stats --no-stream | grep grafana'
```

### Terminal 4: Check Traefik
```bash
# Visit: https://traefik.yourdomain.com/dashboard/
```

## Script Output Guide

### Successful Deployment

```
ℹ Blue-Green Deployment Tool v1.0
▶ Phase 1: Preparation
✓ Service validation passed
✓ Green configuration created

▶ Phase 2: Deploy Green Replica
✓ Scaled grafana to 2 replicas (Blue + Green)

▶ Phase 3: Health Check
⏳ Waiting for health... 45s/120s (healthy: 2/2)
✓ Green replica is healthy! (2/2 replicas healthy)

▶ Phase 4: Traffic Verification
✓ Traefik managing 2 replicas for load balancing

▶ Phase 5: Remove Blue Replica
✓ Scaled down to 1 replica (Green only)

▶ Phase 6: Final Verification
✓ Service is healthy

▶ Deployment Complete
✓ Blue-Green deployment completed successfully!
🎉 Deployment successful!
```

### Failed Deployment (with Rollback)

```
▶ Phase 3: Health Check
✗ Health check timeout after 120s
⚠ Initiating rollback for grafana...
✓ Rollback complete - service restored to original state
❌ Deployment failed!
```

## Quick Decision Tree

```
Do you need to update resource limits?
├─ YES → Is it a stateful service (postgres/redis)?
│  ├─ YES → Use maintenance window or master-replica
│  └─ NO → Use Blue-Green deployment
│     ├─ 1. Dry run: --dry-run
│     ├─ 2. Execute deployment
│     ├─ 3. Monitor logs
│     └─ 4. Verify or rollback
└─ NO → No action needed
```

## Remember

1. **ALWAYS dry-run first** in production
2. **Stateful services** should NOT use Blue-Green
3. **Health checks** are required (or use `--force`)
4. **Automatic rollback** keeps your service safe
5. **Zero downtime** - Blue runs until Green is healthy

## Get Help

```bash
# Full help
./scripts/blue-green-deploy.sh --help

# Check script version
head -2 /workspaces/jacker/scripts/blue-green-deploy.sh

# View deployment logs
tail -100 /var/log/jacker/blue-green.log

# Full documentation
cat /workspaces/jacker/docs/BLUE_GREEN_DEPLOYMENT.md
```
