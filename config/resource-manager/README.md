# Resource Manager - Automated Resource Monitoring and Management

## Overview

The Resource Manager is an automated service that monitors container resource usage via Prometheus and triggers resource adjustments when needed. It implements zero-downtime Blue-Green deployments for resource reallocation.

## Features

- **Automated Monitoring**: Continuously monitors container CPU and memory usage
- **Smart Adjustments**: Increases/decreases resources based on configurable thresholds
- **Hysteresis Control**: Requires consecutive threshold breaches to avoid flip-flopping
- **Zero-Downtime Updates**: Uses Blue-Green deployment strategy for resource changes
- **Priority-Based**: Respects service priorities (critical, normal, optional)
- **Cooldown Periods**: Prevents excessive adjustments with configurable cooldowns
- **Daily Limits**: Caps maximum adjustments per service per day
- **Health Monitoring**: Waits for service health before completing adjustments
- **Auto-Rollback**: Automatically rolls back failed deployments
- **Prometheus Integration**: Queries metrics and exports deployment metrics
- **Alertmanager Notifications**: Sends alerts on adjustments and failures

## Architecture

### Components

1. **manager.py** - Main Python application
   - Queries Prometheus for container metrics
   - Analyzes resource usage patterns
   - Makes adjustment decisions
   - Triggers Blue-Green deployments

2. **config.yml** - Configuration file
   - Monitoring settings
   - Threshold definitions
   - Service prioritization
   - Deployment settings

3. **blue-green-deploy.sh** - Deployment script
   - Performs zero-downtime resource updates
   - Handles health checks and rollbacks

4. **Dockerfile** - Container image
   - Python 3.11 slim base
   - Required dependencies
   - Security hardening

## Configuration

### Environment Variables

```bash
# Prometheus
PROMETHEUS_URL=http://prometheus:9090

# Docker
DOCKER_HOST=tcp://docker-socket-proxy:2375

# Monitoring
CHECK_INTERVAL=300                    # 5 minutes
CPU_HIGH_THRESHOLD=0.8                # 80%
CPU_LOW_THRESHOLD=0.3                 # 30%
MEMORY_HIGH_THRESHOLD=0.8             # 80%
MEMORY_LOW_THRESHOLD=0.3              # 30%

# Adjustments
INCREASE_FACTOR=1.25                  # +25%
DECREASE_FACTOR=0.75                  # -25%

# Blue-Green
BLUE_GREEN_ENABLED=true

# Logging
LOG_LEVEL=info
LOG_FILE=/logs/resource-manager.log
```

### Service Tiers

**Critical Services** (never reduce below baseline):
- traefik
- postgres
- redis
- prometheus

**Normal Services**:
- grafana
- loki
- alertmanager
- crowdsec
- oauth

**Optional Services** (can be scaled down):
- jaeger
- portainer
- vscode

## How It Works

### 1. Metric Collection

The manager queries Prometheus every `CHECK_INTERVAL` seconds:

```python
# CPU Usage (rate over 5 minutes)
rate(container_cpu_usage_seconds_total{name=~".*service.*"}[5m])

# Memory Usage
container_memory_usage_bytes{name=~".*service.*"}

# Resource Limits
container_spec_cpu_quota{name=~".*service.*"}
container_spec_memory_limit_bytes{name=~".*service.*"}
```

### 2. Analysis

For each monitored service:

1. Calculate current usage percentage
2. Compare against high/low thresholds
3. Track consecutive threshold breaches (hysteresis)
4. Check cooldown periods
5. Verify daily adjustment limits
6. Respect service priority and baselines

### 3. Decision Logic

**Increase Resources** when:
- CPU/Memory usage > high threshold (default: 80%)
- Consecutive checks >= 3
- Not in cooldown period
- Daily limit not exceeded

**Decrease Resources** when:
- CPU/Memory usage < low threshold (default: 30%)
- Consecutive checks >= 3
- Service is not critical
- Not in cooldown period
- Daily limit not exceeded

### 4. Adjustment Calculation

**Increase**: `new_limit = current_limit * 1.25` (+25%)
**Decrease**: `new_limit = current_limit * 0.75` (-25%)

With bounds:
- CPU: 0.1 to 8.0 cores
- Memory: 64M to 8192M

Critical services respect baseline minimums.

### 5. Blue-Green Deployment

When adjustment is needed:

1. **Backup** current configuration
2. **Create Green** container with new limits
3. **Scale Up** to 2 replicas (Blue + Green)
4. **Health Check** Green replica
5. **Verify** traffic distribution via Traefik
6. **Drain** connections from Blue
7. **Scale Down** to 1 replica (Green only)
8. **Verify** final deployment
9. **Rollback** if any step fails (optional)

## Prometheus Queries

### CPU Usage Rate
```promql
rate(container_cpu_usage_seconds_total{name=~".*service.*"}[5m])
```
Returns CPU cores used per second over 5 minute window.

### CPU Usage Percentage
```promql
rate(container_cpu_usage_seconds_total{name=~".*service.*"}[5m])
/
(container_spec_cpu_quota{name=~".*service.*"} / 100000)
```

### Memory Usage Percentage
```promql
container_memory_usage_bytes{name=~".*service.*"}
/
container_spec_memory_limit_bytes{name=~".*service.*"}
```

### Trend Analysis (1 hour)
```promql
avg_over_time(
  rate(container_cpu_usage_seconds_total{name=~".*service.*"}[5m])[1h:]
)
```

## Usage

### Deploy Resource Manager

```bash
# Build and start
docker-compose -f compose/resource-manager.yml build
docker-compose -f compose/resource-manager.yml up -d

# View logs
docker-compose -f compose/resource-manager.yml logs -f

# Check health
curl http://localhost:8000/health
```

### Manual Blue-Green Deployment

```bash
# Adjust resources for a service
./scripts/blue-green-deploy.sh grafana 1.5 768M

# Dry run to preview changes
./scripts/blue-green-deploy.sh grafana 1.5 768M --dry-run

# With custom timeout
./scripts/blue-green-deploy.sh traefik 2.0 1024M --timeout 180

# Rollback a deployment
./scripts/blue-green-deploy.sh rollback grafana

# Check deployment status
./scripts/blue-green-deploy.sh status grafana
```

### Configuration Changes

Edit `/workspaces/jacker/config/resource-manager/config.yml`:

```yaml
# Adjust thresholds
thresholds:
  cpu_high: 0.85      # Trigger at 85% instead of 80%
  consecutive_checks: 5  # Require 5 checks instead of 3

# Change adjustment factors
adjustment:
  increase_factor: 1.5  # +50% instead of +25%
  cooldown_period: 3600 # 1 hour instead of 30 minutes

# Modify service list
services:
  monitored:
    - traefik
    - postgres
    - my-custom-service
```

Then restart:
```bash
docker-compose -f compose/resource-manager.yml restart
```

## Monitoring

### Health Check Endpoint

```bash
# Check service health
curl http://localhost:8000/health

# Response
{
  "status": "healthy",
  "timestamp": "2025-10-17T12:00:00Z"
}
```

### Metrics Endpoint

```bash
# View Prometheus metrics
curl http://localhost:8000/metrics
```

Exported metrics:
- `resource_manager_total_adjustments` - Total adjustments performed
- `resource_manager_successful_adjustments` - Successful adjustments
- `resource_manager_failed_adjustments` - Failed adjustments
- `resource_manager_blue_green_deployments` - Blue-Green deployments
- `resource_manager_rollbacks` - Rollback operations

### Logs

View detailed logs:
```bash
# Container logs
docker logs resource-manager -f

# Log file
tail -f /workspaces/jacker/data/resource-manager/logs/resource-manager.log

# Blue-Green deployment logs
tail -f /var/log/jacker/blue-green.log
```

## Traefik Integration

The Resource Manager web interface is exposed via Traefik:

- **URL**: `https://resource-manager.yourdomain.com`
- **Authentication**: OAuth2 (via chain-oauth middleware)
- **Health Check**: `/health` endpoint
- **Metrics**: `/metrics` endpoint (Prometheus scraping)

## Limitations and Considerations

### ⚠️ Important Limitations

1. **Stateful Services**: Blue-Green deployment is NOT suitable for:
   - Databases (postgres)
   - Caches with persistence (redis)
   - Single-point services (socket-proxy)
   - Use rolling restart or maintenance windows instead

2. **Metric Accuracy**:
   - Requires accurate Prometheus metrics
   - 5-minute analysis window may miss short spikes
   - Container restart resets metric history

3. **Resource Bounds**:
   - Cannot exceed configured max limits (8 CPU, 8GB RAM)
   - Cannot go below configured minimums (0.1 CPU, 64MB RAM)
   - Critical services respect baseline allocations

4. **Deployment Constraints**:
   - Requires health checks for safe deployments
   - Services must support multiple replicas
   - Traefik integration recommended for load balancing

5. **Network Dependencies**:
   - Requires access to Prometheus
   - Requires Docker socket proxy
   - Network interruptions pause monitoring

### 🔧 Troubleshooting

**Manager not starting:**
```bash
# Check Prometheus connectivity
curl http://prometheus:9090/-/ready

# Check Docker socket proxy
curl http://docker-socket-proxy:2375/version

# View manager logs
docker logs resource-manager
```

**No adjustments happening:**
```bash
# Enable debug logging
docker-compose -f compose/resource-manager.yml exec resource-manager \
  sh -c "export LOG_LEVEL=debug"

# Check service metrics in Prometheus
curl 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total'

# Verify service is in monitored list
grep "monitored:" /workspaces/jacker/config/resource-manager/config.yml
```

**Blue-Green deployment fails:**
```bash
# Check service health
docker-compose ps <service>

# Verify health check configuration
docker-compose config | grep -A 10 "<service>:" | grep -A 5 "healthcheck:"

# Test manual deployment
./scripts/blue-green-deploy.sh <service> <cpu> <memory> --dry-run

# Check deployment logs
tail -f /var/log/jacker/blue-green.log
```

### 🎯 Best Practices

1. **Start Conservative**:
   - Use higher thresholds initially (e.g., 85% instead of 80%)
   - Increase consecutive_checks (e.g., 5 instead of 3)
   - Longer cooldown periods (e.g., 1 hour)

2. **Monitor Closely**:
   - Watch logs during first week
   - Review adjustment patterns
   - Tune thresholds based on actual usage

3. **Test Thoroughly**:
   - Always use `--dry-run` first
   - Test on non-critical services
   - Verify rollback procedures work

4. **Gradual Rollout**:
   - Start with optional services (jaeger, portainer)
   - Move to normal services (grafana, loki)
   - Finally enable for critical services

5. **Backup Strategy**:
   - Keep docker-compose backups
   - Document baseline configurations
   - Test manual rollback procedures

## Security Considerations

- **Read-Only Root**: Container runs with read-only root filesystem
- **Non-Root User**: Runs as resourcemgr user (UID 1000)
- **No New Privileges**: Security option enabled
- **Socket Proxy**: Uses Docker socket proxy (not direct socket access)
- **OAuth Protection**: Web interface requires OAuth2 authentication
- **Secret Management**: No secrets in environment variables

## Advanced Features (Future)

### Machine Learning Predictions
```yaml
advanced:
  ml_predictions:
    enabled: true
    model_path: "/config/models/resource-predictor.pkl"
```

### Cost Optimization
```yaml
advanced:
  cost_optimization:
    enabled: true
    target_utilization: 0.7  # 70% target
```

### Multi-Cluster Support
```yaml
advanced:
  multi_cluster:
    enabled: true
    clusters:
      - name: production
        prometheus_url: http://prom-prod:9090
      - name: staging
        prometheus_url: http://prom-staging:9090
```

## Contributing

To enhance the Resource Manager:

1. Edit `manager.py` for core logic changes
2. Update `config.yml` for new configuration options
3. Modify `Dockerfile` for dependency changes
4. Update this README with new features

## Support

For issues or questions:
- Check logs: `/workspaces/jacker/data/resource-manager/logs/`
- Review Prometheus metrics: `http://prometheus:9090`
- Verify Traefik routing: `http://traefik:8080/dashboard/`
- Check Blue-Green script: `./scripts/blue-green-deploy.sh --help`

---

**Version**: 1.0.0
**Last Updated**: 2025-10-17
**Maintainer**: Jacker Team
