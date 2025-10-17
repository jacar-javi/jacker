# Jacker Resource Tuning System

## Overview

The Jacker Resource Tuning System automatically detects system capabilities and calculates optimal resource allocations for all Docker services. This ensures efficient resource utilization while preventing over-allocation.

## Features

- **Automatic Detection**: Detects CPU, RAM, disk, and system load
- **Performance Scoring**: Calculates a 0-100 performance score based on system capabilities
- **Tier Classification**: Assigns system to one of 5 tiers (minimal to high-performance)
- **Smart Allocation**: Calculates optimal CPU and memory limits per service
- **Safety Validation**: Ensures allocations don't exceed available resources
- **Override Generation**: Creates `docker-compose.override.yml` with calculated limits
- **Colorized Output**: Clear, visual summary of allocations

## System Tiers

### Tier 1: Minimal (Score 0-30)
- **Hardware**: 1-2 CPU cores, <4GB RAM, HDD
- **Host Reserve**: 50%
- **Services**: Critical services only (Traefik, PostgreSQL, Redis, Socket-proxy)
- **Strategy**: Disable heavy services (Jaeger, VSCode, Loki, monitoring stack)
- **Use Case**: Development on low-resource systems

### Tier 2: Basic (Score 31-50)
- **Hardware**: 2-4 CPU cores, 4-6GB RAM, HDD/SSD
- **Host Reserve**: 40%
- **Services**: Critical + essential monitoring
- **Strategy**: Light monitoring, disable optional services
- **Use Case**: Small production deployments, testing

### Tier 3: Standard (Score 51-70)
- **Hardware**: 4-8 CPU cores, 8-12GB RAM, SSD
- **Host Reserve**: 30%
- **Services**: Full stack except heavy optional services
- **Strategy**: Full monitoring, essential tools
- **Use Case**: Standard production deployments

### Tier 4: Performance (Score 71-85)
- **Hardware**: 8-12 CPU cores, 16-32GB RAM, SSD
- **Host Reserve**: 25%
- **Services**: All services with generous limits
- **Strategy**: 1.25x CPU, 1.2x memory multipliers
- **Use Case**: High-traffic production environments

### Tier 5: High-Performance (Score 86-100)
- **Hardware**: 12+ CPU cores, 32GB+ RAM, NVMe SSD
- **Host Reserve**: 20%
- **Services**: All services with maximum limits
- **Strategy**: 1.5x CPU, 1.5x memory multipliers
- **Use Case**: Enterprise deployments, heavy workloads

## Performance Scoring

The performance score (0-100) is calculated from:

| Component | Max Points | Criteria |
|-----------|------------|----------|
| CPU | 30 | Based on logical CPU threads |
| RAM | 30 | Based on total RAM in GB |
| Disk | 20 | Based on size + SSD bonus |
| Network | 10 | Based on network interfaces |
| Health | 10 | Based on load average vs CPU capacity |

### CPU Score (0-30 points)
- 16+ threads: 30 points
- 12+ threads: 28 points
- 8+ threads: 25 points
- 6+ threads: 20 points
- 4+ threads: 15 points
- 2+ threads: 10 points
- 1 thread: 5 points

### RAM Score (0-30 points)
- 32GB+: 30 points
- 16GB+: 28 points
- 12GB+: 25 points
- 8GB+: 20 points
- 6GB+: 15 points
- 4GB+: 10 points
- <4GB: 5 points

### Disk Score (0-20 points)
- Size: 5-15 points (based on capacity)
- SSD Bonus: +5 points
- Maximum: 20 points

## Service Categories

Services are classified by priority:

### Critical Services (Must Run)
- **traefik**: Reverse proxy (2.0 CPU, 1024M)
- **postgres**: Database (2.0 CPU, 2048M)
- **redis**: Cache (1.0 CPU, 1024M)
- **socket-proxy**: Docker API proxy (0.25 CPU, 128M)

### High Priority Services (Essential Monitoring)
- **prometheus**: Metrics storage (2.0 CPU, 2048M)
- **grafana**: Dashboards (1.0 CPU, 1024M)
- **loki**: Log aggregation (2.0 CPU, 2048M)
- **promtail**: Log collector (0.5 CPU, 512M)

### Medium Priority Services (Security & Monitoring)
- **crowdsec**: Security (1.0 CPU, 512M)
- **alertmanager**: Alerts (0.5 CPU, 512M)
- **node-exporter**: System metrics (0.5 CPU, 256M)
- **blackbox-exporter**: Probing (0.5 CPU, 256M)
- **cadvisor**: Container metrics (1.0 CPU, 512M)

### Low Priority Services (Utilities)
- **oauth2-proxy**: Authentication (0.5 CPU, 256M)
- **postgres-exporter**: DB metrics (0.25 CPU, 128M)
- **redis-exporter**: Cache metrics (0.25 CPU, 128M)
- **pushgateway**: Batch metrics (0.5 CPU, 256M)

### Optional Services (Can Be Disabled)
- **jaeger**: Distributed tracing (1.0 CPU, 1024M)
- **vscode**: Web IDE (2.0 CPU, 2048M)
- **portainer**: Container management (0.5 CPU, 512M)
- **homepage**: Dashboard (0.25 CPU, 256M)
- **redis-commander**: Redis UI (0.25 CPU, 256M)

## Usage

### Automatic (Recommended)

The resource tuning system is automatically invoked during setup:

```bash
./jacker setup
```

### Manual Tuning

Re-calculate and apply resource limits:

```bash
# Source the library
source assets/lib/resources.sh

# Run full tuning
apply_resource_tuning

# Or run step-by-step
detect_all_resources
calculate_performance_score
calculate_resource_allocations
generate_resource_override "docker-compose.override.yml"
show_resource_summary
```

### Testing Different Scenarios

Use the test script to simulate different system tiers:

```bash
./test-resources.sh
```

## Generated Files

### docker-compose.override.yml

Auto-generated file containing:
- Resource limits (CPU and memory)
- Resource reservations (guaranteed minimums)
- Service replica counts (0 for disabled services)
- Generation metadata (timestamp, system info)

Example entry:

```yaml
services:
  traefik:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 1024M
        reservations:
          cpus: '0.5'
          memory: 256M
```

**Important**: Do not edit this file manually - it will be regenerated.

## Resource Allocation Logic

### 1. Detection Phase
- Detect CPU cores, threads, frequency, architecture
- Detect total/available RAM and swap
- Detect disk space and type (SSD/HDD)
- Detect system load average

### 2. Scoring Phase
- Calculate component scores (CPU, RAM, disk, network, health)
- Sum to overall performance score (0-100)
- Classify into tier (minimal/basic/standard/performance/high-performance)

### 3. Allocation Phase
- Determine which services to enable based on tier
- Calculate tier-based multipliers (0.5x to 1.5x)
- Apply multipliers to base resource requirements
- Scale down if total exceeds available resources
- Calculate reservations (20-25% of limits)

### 4. Validation Phase
- Check total CPU allocation vs available
- Check total memory allocation vs available
- Warn if utilization >90%
- Error if over-allocation detected

### 5. Generation Phase
- Create docker-compose.override.yml
- Set resource limits and reservations
- Disable services (replicas: 0) if needed
- Add metadata comments

## Edge Cases Handled

### Low Resources
- Automatically disables optional services
- Scales down all allocations proportionally
- Reserves more for host OS (up to 50%)
- Warns about reduced functionality

### High Resources
- Enables all services
- Applies generous multipliers (up to 1.5x)
- Reduces host reserve (down to 20%)
- Maximizes available capacity

### Over-Allocation
- Automatically scales down all services proportionally
- Maintains relative priorities
- Ensures no service gets below minimum
- Warns about tight resources

### High Load
- Reduces health score
- May lower tier classification
- Accounts for current system stress

## Integration Points

### Setup Script
Called during initial setup in `setup.sh`:

```bash
source "${LIB_DIR}/resources.sh"

# Between prepare_system() and initialize_services()
apply_resource_tuning "${JACKER_ROOT}/docker-compose.override.yml"
```

### Maintenance
Can be re-run when:
- Hardware changes
- Service requirements change
- System performance issues occur

### Monitoring
Performance score and tier can be tracked over time:
- Store in monitoring database
- Alert on tier degradation
- Track resource utilization trends

## Limitations

1. **Static Allocation**: Limits are fixed at setup time, don't auto-adjust
2. **No Auto-Scaling**: Services don't scale up/down based on load
3. **Conservative Estimates**: Errs on side of caution (may under-utilize)
4. **No GPU Detection**: Only detects CPU, RAM, disk
5. **No Network Bandwidth**: Network score is simplified

## Best Practices

1. **Re-tune After Hardware Changes**: Run tuning after RAM/CPU upgrades
2. **Monitor Resource Usage**: Check actual vs allocated with `docker stats`
3. **Adjust for Workload**: Override specific services if needed
4. **Keep Host Reserve**: Don't reduce below 20% on production systems
5. **Test Before Production**: Validate on staging with similar hardware

## Troubleshooting

### Services Disabled Unexpectedly
- Check system tier: `grep "System Tier" docker-compose.override.yml`
- Review performance score in override file
- Consider upgrading hardware or reducing services

### Over-Allocation Warnings
- System detected tight resources
- Some services scaled down automatically
- Monitor with `docker stats` to verify
- Consider disabling optional services manually

### High Resource Utilization
- System allocated >90% of available resources
- Monitor system performance carefully
- Consider upgrading hardware
- Manually disable non-essential services

### Services Won't Start
- Check `docker-compose logs <service>`
- Verify resource limits aren't too low
- Check host has enough free resources
- Review docker-compose.override.yml

## Future Enhancements

Potential improvements:
- Dynamic resource adjustment based on metrics
- Auto-scaling for supported services
- GPU detection and allocation
- Network bandwidth detection
- Integration with Kubernetes HPA
- Machine learning for optimal allocation
- Historical performance tracking
- Automatic tier upgrades on hardware changes

## Related Documentation

- [System Requirements](SYSTEM_REQUIREMENTS.md)
- [Performance Monitoring](MONITORING.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/deploy/)
