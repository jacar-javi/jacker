# Blue-Green Deployment Guide

## Overview

The Blue-Green deployment script (`scripts/blue-green-deploy.sh`) enables **zero-downtime service updates** for Docker Compose services by running two versions simultaneously and switching traffic once the new version (Green) is healthy.

## Table of Contents

- [How It Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Deployment Phases](#deployment-phases)
- [Health Checks](#health-checks)
- [Rollback Strategy](#rollback-strategy)
- [Stateful Services](#stateful-services)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Advanced Features](#advanced-features)

---

## How It Works

### Blue-Green Strategy

1. **Blue** = Current running version with existing resource limits
2. **Green** = New version with updated resource limits
3. **Process**:
   - Deploy Green alongside Blue (scale to 2 replicas)
   - Wait for Green to be healthy
   - Traefik automatically load balances traffic between both
   - Remove Blue once Green is stable (scale to 1 replica)

### Key Benefits

- **Zero Downtime**: Users never experience service interruption
- **Instant Rollback**: If Green fails, Blue is still running
- **Safe Testing**: Green receives real traffic while Blue provides fallback
- **Automated**: Script handles orchestration, health checks, and rollback

---

## Prerequisites

### Required

1. **Health Checks**: Service must have health check defined in `docker-compose.yml`
2. **Traefik**: For automatic load balancing (optional for internal services)
3. **Dependencies**: `docker`, `docker-compose`, `jq`, `bc`

### Health Check Example

```yaml
services:
  grafana:
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
```

### Install Dependencies

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y docker.io docker-compose jq bc

# Verify installation
docker --version
docker-compose --version
jq --version
bc --version
```

---

## Usage

### Basic Deployment

```bash
# Syntax
./scripts/blue-green-deploy.sh <service> <new_cpu> <new_memory> [options]

# Update Grafana resource limits
./scripts/blue-green-deploy.sh grafana 1.5 768M

# Update Traefik with custom timeout
./scripts/blue-green-deploy.sh traefik 2.5 1536M --timeout 180
```

### Dry Run (Recommended First)

```bash
# See what would happen without making changes
./scripts/blue-green-deploy.sh grafana 1.5 768M --dry-run
```

### Rollback

```bash
# Manual rollback to previous configuration
./scripts/blue-green-deploy.sh rollback grafana
```

### Status Check

```bash
# Check current deployment status
./scripts/blue-green-deploy.sh status grafana
```

### Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--dry-run` | Show changes without executing | disabled |
| `--timeout <sec>` | Health check timeout | 120 |
| `--no-rollback` | Disable automatic rollback | enabled |
| `--force` | Skip safety checks (dangerous!) | disabled |
| `--log-file <path>` | Custom log file path | `/var/log/jacker/blue-green.log` |
| `--no-drain` | Skip connection draining | disabled |
| `--metrics` | Export metrics to Prometheus | disabled |

---

## Deployment Phases

### Phase 1: Preparation

**Actions**:
- Validate service exists and is running
- Check for health check definition
- Get current resource limits
- Create override configuration

**Validations**:
- Service exists in `docker-compose.yml`
- Service is not a stateful service (unless `--force`)
- Service has health check (unless `--force`)
- Resource format is valid (CPU: 0.1-16.0, Memory: 64M-32G)

### Phase 2: Deploy Green

**Actions**:
- Create `docker-compose.blue-green.yml` with new limits
- Scale service to 2 replicas using override
- New replica (Green) gets new resource limits
- Old replica (Blue) keeps original limits

**Command**:
```bash
docker-compose -f docker-compose.yml -f docker-compose.blue-green.yml up -d --scale service=2
```

### Phase 3: Health Check

**Actions**:
- Poll service health every 5 seconds
- Wait for Green replica to report "healthy"
- Timeout after 120 seconds (configurable)
- Show real-time progress

**Health Check Logic**:
```bash
# Check Docker health status
docker inspect <container> --format='{{.State.Health.Status}}'

# Valid statuses:
# - "healthy" = Health check passed
# - "unhealthy" = Health check failed
# - "starting" = Container starting, health check not run yet
# - "none" = No health check defined (fallback to running state)
```

### Phase 4: Traffic Verification

**Actions**:
- Verify Traefik is load balancing to both replicas
- Check that Green is receiving traffic
- Monitor for errors in logs

**Note**: Traefik automatically discovers both replicas via Docker labels and load balances between them.

### Phase 5: Drain and Remove Blue

**Actions**:
- Wait 30 seconds for active connections to drain (configurable)
- Scale down to 1 replica (removes Blue, keeps Green)
- Verify only Green is running

**Command**:
```bash
docker-compose -f docker-compose.yml -f docker-compose.blue-green.yml up -d --scale service=1
```

### Phase 6: Final Verification

**Actions**:
- Verify Green is healthy
- Confirm resource limits applied
- Export deployment metrics (if `--metrics`)
- Clean up temporary files

---

## Health Checks

### Why Health Checks Are Required

Health checks ensure the new replica (Green) is **actually working** before removing the old replica (Blue). Without health checks, you might remove a working service and replace it with a broken one.

### How Health Checks Are Performed

1. **Docker Native**: Uses Docker's built-in health check system
2. **Polling**: Checks health status every 5 seconds
3. **Timeout**: Fails after 120 seconds (configurable with `--timeout`)
4. **Multiple Replicas**: Waits for at least 2 healthy replicas (Blue + Green)

### Health Check States

```bash
# healthy - Service is working correctly
✓ Green replica is healthy! (2/2 replicas healthy)

# starting - Health check running but not complete
⏳ Waiting for health... 15s/120s (healthy: 1/2)

# unhealthy - Health check failed
✗ Health check timeout after 120s
```

### Fallback Behavior

If no health check is defined:
- Script will **fail by default** (safe)
- Can override with `--force` (uses container "running" state)
- **Not recommended** for production

---

## Rollback Strategy

### Automatic Rollback

**Triggers**:
- Green fails to start
- Health check timeout
- Scale operations fail
- Verification fails

**Actions**:
1. Restore previous configuration
2. Scale back to 1 replica with original limits
3. Remove Green replica
4. Keep Blue running (service never went down)

**Disable**: Use `--no-rollback` flag (not recommended)

### Manual Rollback

```bash
# Rollback command
./scripts/blue-green-deploy.sh rollback grafana

# What it does:
# 1. Restores backup configuration
# 2. Scales to 1 replica with original limits
# 3. Removes override file
# 4. Verifies service is healthy
```

### Rollback Verification

After rollback:
```bash
# Check service status
./scripts/blue-green-deploy.sh status grafana

# Verify resource limits
docker inspect grafana --format='{{.HostConfig.NanoCpus}}'  # CPU
docker inspect grafana --format='{{.HostConfig.Memory}}'     # Memory
```

---

## Stateful Services

### Services That Should NOT Use Blue-Green

The following services maintain **state** and should **NOT** use Blue-Green deployment:

#### 1. Databases

- **postgres**: Running 2 instances = data inconsistency
- **postgres-exporter**: Tied to single database instance

**Alternative**:
- Use **master-replica** pattern with failover
- Or schedule **maintenance window** for updates

#### 2. Caches

- **redis**: Session data inconsistency between instances
- **redis-exporter**: Monitors single Redis instance
- **redis-commander**: Management UI for single instance

**Alternative**:
- Use **Redis Cluster** or **Redis Sentinel** for HA
- Or use **rolling restart** with persistence enabled

#### 3. Socket Proxies

- **socket-proxy**: Single point of access to Docker socket

**Alternative**:
- Use **graceful restart** with minimal downtime
- Or run multiple proxies with different paths (advanced)

### Detection

Script automatically detects stateful services:

```bash
$ ./scripts/blue-green-deploy.sh postgres 1.0 512M
✗ Service 'postgres' is a stateful service and should NOT use Blue-Green deployment
✗ Stateful services: postgres postgres-exporter redis redis-exporter redis-commander socket-proxy
```

### Override (Use Caution!)

```bash
# Force deployment on stateful service (NOT RECOMMENDED)
./scripts/blue-green-deploy.sh postgres 1.0 512M --force

⚠ Proceeding anyway due to --force flag (DANGEROUS!)
```

**Warning**: Using `--force` on stateful services can cause:
- Data corruption
- Connection errors
- Session loss
- Service unavailability

---

## Best Practices

### 1. Always Dry Run First

```bash
# Test deployment without making changes
./scripts/blue-green-deploy.sh grafana 1.5 768M --dry-run
```

### 2. Start with Small Changes

```bash
# Incremental updates are safer
# Bad: Double resources at once
./scripts/blue-green-deploy.sh grafana 4.0 4096M  # Too big jump

# Good: Gradual increase
./scripts/blue-green-deploy.sh grafana 1.5 768M   # 25% increase
# Monitor, then:
./scripts/blue-green-deploy.sh grafana 2.0 1024M  # Another 25%
```

### 3. Monitor During Deployment

```bash
# In one terminal: Run deployment
./scripts/blue-green-deploy.sh grafana 1.5 768M

# In another terminal: Watch logs
docker-compose logs -f grafana

# In third terminal: Monitor metrics
watch -n 1 'docker stats --no-stream | grep grafana'
```

### 4. Test Health Checks First

```bash
# Verify health check works
docker-compose ps grafana
# Should show "healthy" status

# Test health check manually
docker exec grafana /bin/sh -c "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health"
```

### 5. Use Custom Timeouts for Slow Services

```bash
# Some services take longer to start
./scripts/blue-green-deploy.sh prometheus 2.0 2048M --timeout 180
```

### 6. Export Metrics

```bash
# Track deployment success/failure rates
./scripts/blue-green-deploy.sh grafana 1.5 768M --metrics

# Metrics written to: /var/log/jacker/blue-green-metrics.prom
# Import into Prometheus for monitoring
```

### 7. Keep Logs

```bash
# Use custom log location
./scripts/blue-green-deploy.sh grafana 1.5 768M --log-file /var/log/deployments/grafana-$(date +%Y%m%d).log
```

### 8. Verify After Deployment

```bash
# Check status
./scripts/blue-green-deploy.sh status grafana

# Verify service works
curl -I https://grafana.yourdomain.com/api/health

# Check resource usage
docker stats --no-stream grafana
```

---

## Troubleshooting

### Issue: Health Check Timeout

**Symptom**:
```
✗ Health check timeout after 120s
```

**Causes**:
- Service starting slowly
- Health check endpoint wrong
- Resource limits too low (container OOM)

**Solutions**:
```bash
# 1. Increase timeout
./scripts/blue-green-deploy.sh grafana 1.5 768M --timeout 300

# 2. Check health check definition
docker-compose config | grep -A 10 "healthcheck:"

# 3. Check container logs
docker-compose logs --tail=50 grafana

# 4. Test health check manually
docker exec grafana wget --spider http://localhost:3000/api/health
```

### Issue: Deployment Fails to Scale

**Symptom**:
```
✗ Failed to scale up grafana
```

**Causes**:
- Resource limits too high (insufficient host resources)
- Port conflicts
- Volume conflicts

**Solutions**:
```bash
# 1. Check host resources
free -h
docker stats

# 2. Try lower resource limits
./scripts/blue-green-deploy.sh grafana 1.0 512M

# 3. Check for errors
docker-compose -f docker-compose.yml -f docker-compose.blue-green.yml up -d --scale grafana=2
```

### Issue: Rollback Fails

**Symptom**:
```
✗ Rollback failed!
✗ Manual intervention required
```

**Solutions**:
```bash
# 1. Manual rollback
docker-compose -f docker-compose.yml up -d grafana

# 2. Check for stuck containers
docker ps -a | grep grafana
docker rm -f <container_id>

# 3. Remove override files
rm -f docker-compose.blue-green.yml docker-compose.blue-green.backup.yml

# 4. Restart service
docker-compose restart grafana
```

### Issue: Service Becomes Unhealthy After Deployment

**Symptom**:
- Deployment succeeds
- Service becomes unhealthy later

**Causes**:
- Resource limits too low (gradual OOM)
- Memory leak
- Configuration issue

**Solutions**:
```bash
# 1. Check resource usage over time
docker stats grafana

# 2. Check for OOM kills
dmesg | grep -i oom

# 3. Rollback immediately
./scripts/blue-green-deploy.sh rollback grafana

# 4. Increase limits and try again
./scripts/blue-green-deploy.sh grafana 2.0 1536M
```

### Issue: Traefik Not Load Balancing

**Symptom**:
- Both replicas running
- Traffic only goes to one

**Causes**:
- Traefik labels missing
- Service name mismatch

**Solutions**:
```bash
# 1. Check Traefik labels
docker inspect grafana | jq '.[0].Config.Labels'

# 2. Check Traefik dashboard
# Visit: https://traefik.yourdomain.com/dashboard/

# 3. Verify both containers in same network
docker network inspect traefik_proxy
```

---

## Advanced Features

### 1. Custom Health Check Timeout

```bash
# For slow-starting services (e.g., databases)
./scripts/blue-green-deploy.sh postgres 2.0 2048M --timeout 300 --force
```

### 2. Skip Connection Draining

```bash
# For services with no persistent connections
./scripts/blue-green-deploy.sh prometheus 2.0 2048M --no-drain
```

### 3. Disable Automatic Rollback

```bash
# Keep both replicas running on failure for debugging
./scripts/blue-green-deploy.sh grafana 1.5 768M --no-rollback
```

### 4. Export Prometheus Metrics

```bash
# Enable metrics export
./scripts/blue-green-deploy.sh grafana 1.5 768M --metrics

# Metrics file: /var/log/jacker/blue-green-metrics.prom
# Metrics include:
# - blue_green_deployment_total{service,status}
# - blue_green_deployment_duration_seconds{service}
# - blue_green_cpu_limit{service}
# - blue_green_memory_limit_bytes{service}
```

### 5. Batch Deployments

```bash
#!/bin/bash
# deploy-all-monitoring.sh - Update all monitoring services

services=(
  "prometheus:2.0:2048M"
  "grafana:1.5:1024M"
  "alertmanager:0.5:512M"
  "loki:1.0:1024M"
)

for service_spec in "${services[@]}"; do
  IFS=':' read -r service cpu memory <<< "$service_spec"
  echo "Deploying $service..."
  ./scripts/blue-green-deploy.sh "$service" "$cpu" "$memory" || {
    echo "Failed to deploy $service, stopping"
    break
  }
  sleep 10  # Wait between deployments
done
```

### 6. Integration with CI/CD

```yaml
# .github/workflows/deploy.yml
name: Deploy Service Update

on:
  workflow_dispatch:
    inputs:
      service:
        description: 'Service to update'
        required: true
      cpu:
        description: 'New CPU limit'
        required: true
      memory:
        description: 'New memory limit'
        required: true

jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Deploy Blue-Green
        run: |
          ./scripts/blue-green-deploy.sh \
            ${{ github.event.inputs.service }} \
            ${{ github.event.inputs.cpu }} \
            ${{ github.event.inputs.memory }} \
            --metrics

      - name: Upload Metrics
        uses: actions/upload-artifact@v3
        with:
          name: deployment-metrics
          path: /var/log/jacker/blue-green-metrics.prom
```

---

## Examples

### Example 1: Update Grafana

```bash
# Scenario: Grafana is using too much memory, need to reduce limits

# 1. Check current usage
docker stats --no-stream grafana

# 2. Dry run to verify
./scripts/blue-green-deploy.sh grafana 1.0 768M --dry-run

# 3. Execute deployment
./scripts/blue-green-deploy.sh grafana 1.0 768M

# 4. Monitor deployment
# Watch logs in another terminal:
# docker-compose logs -f grafana

# 5. Verify success
./scripts/blue-green-deploy.sh status grafana
```

### Example 2: Update Traefik with Custom Timeout

```bash
# Scenario: Traefik handles all traffic, needs careful deployment

# 1. Use longer timeout for safety
./scripts/blue-green-deploy.sh traefik 2.5 1536M --timeout 180

# 2. Monitor Traefik dashboard during deployment
# https://traefik.yourdomain.com/dashboard/

# 3. Check all services still accessible
curl -I https://grafana.yourdomain.com
curl -I https://prometheus.yourdomain.com
```

### Example 3: Failed Deployment and Rollback

```bash
# Scenario: Deployment fails due to health check timeout

$ ./scripts/blue-green-deploy.sh prometheus 0.5 256M
...
✗ Health check timeout after 120s
⚠ Initiating rollback for prometheus...
✓ Rollback complete - service restored to original state

# Service never went down - Blue kept running
```

### Example 4: Monitoring Stack Upgrade

```bash
#!/bin/bash
# upgrade-monitoring.sh - Upgrade all monitoring services

set -e

echo "Upgrading monitoring stack with Blue-Green deployment..."

# Grafana
./scripts/blue-green-deploy.sh grafana 2.0 1024M
sleep 10

# Prometheus
./scripts/blue-green-deploy.sh prometheus 2.0 2048M --timeout 180
sleep 10

# Loki
./scripts/blue-green-deploy.sh loki 1.0 1024M
sleep 10

# Alertmanager
./scripts/blue-green-deploy.sh alertmanager 0.5 512M

echo "Monitoring stack upgraded successfully!"
```

---

## Summary

### Supported Services

- ✓ Grafana, Prometheus, Loki, Alertmanager, Jaeger
- ✓ Traefik, OAuth2-Proxy, CrowdSec
- ✓ Portainer, Homepage, VS Code
- ✓ Node Exporter, Blackbox Exporter

### NOT Supported Services

- ✗ PostgreSQL, Redis (use master-replica or maintenance window)
- ✗ Socket Proxy (single point of access)

### Key Points

1. **Always dry-run first**: `--dry-run` flag
2. **Health checks required**: Ensure services have health checks
3. **Automatic rollback**: Failed deployments rollback automatically
4. **Zero downtime**: Blue keeps running until Green is healthy
5. **Stateful services**: Use different strategy (no Blue-Green)

### Exit Codes

- `0` - Success
- `1` - Validation error
- `2` - Deployment failure
- `3` - Rollback failure
- `4` - Health check timeout

### Logs

- Default: `/var/log/jacker/blue-green.log`
- Custom: `--log-file /path/to/log`
- Metrics: `/var/log/jacker/blue-green-metrics.prom`

---

## Additional Resources

- **Docker Compose Docs**: https://docs.docker.com/compose/
- **Traefik Load Balancing**: https://doc.traefik.io/traefik/routing/services/
- **Health Checks**: https://docs.docker.com/engine/reference/builder/#healthcheck
- **Blue-Green Deployment Pattern**: https://martinfowler.com/bliki/BlueGreenDeployment.html
