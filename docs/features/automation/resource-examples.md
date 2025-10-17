# Resource Tuning Examples

This document provides real-world examples of how the resource tuning system allocates resources for different system tiers.

## Example 1: Minimal System (Score: 25/100)

### System Configuration
- **CPU**: 2 threads (1 core) @ 2.0 GHz
- **RAM**: 2GB total / 1.5GB available
- **Disk**: 50GB HDD
- **Load**: 0.5 / 0.4 / 0.3
- **Tier**: MINIMAL
- **Host Reserve**: 50%

### Score Breakdown
- CPU Score: 10/30 (2 threads)
- RAM Score: 5/30 (2GB)
- Disk Score: 5/20 (50GB HDD)
- Network Score: 8/10 (normal)
- Health Score: 10/10 (low load)
- **Total**: 38/100 → Basic tier (but degraded to minimal due to RAM)

### Service Allocation

**Critical Services** (4 enabled)
```
traefik          : CPU 0.50   RAM  307M
postgres         : CPU 0.50   RAM  614M
redis            : CPU 0.25   RAM  307M
socket-proxy     : CPU 0.06   RAM   38M
```

**All Other Services**: DISABLED

### Total Allocation
- Services: 4 enabled / 22 total
- CPU: 1.31 / 1.00 CPUs (need to scale down further)
- RAM: 1266M / 1024M RAM (need to scale down further)

### Notes
- Only critical services run
- 18 services disabled to fit resources
- Tight fit - monitor performance
- Consider upgrading to 4GB RAM minimum

---

## Example 2: Basic System (Score: 45/100)

### System Configuration
- **CPU**: 4 threads (4 cores) @ 2.5 GHz
- **RAM**: 8GB total / 6GB available
- **Disk**: 100GB SSD
- **Load**: 1.2 / 1.0 / 0.8
- **Tier**: BASIC
- **Host Reserve**: 40%

### Score Breakdown
- CPU Score: 15/30 (4 threads)
- RAM Score: 20/30 (8GB)
- Disk Score: 15/20 (100GB SSD)
- Network Score: 8/10
- Health Score: 8/10 (moderate load)
- **Total**: 66/100 → Standard tier (but with basic multipliers)

### Service Allocation

**Critical Services** (4 enabled)
```
traefik          : CPU 1.50   RAM  819M
postgres         : CPU 1.50   RAM 1638M
redis            : CPU 0.75   RAM  819M
socket-proxy     : CPU 0.19   RAM  102M
```

**High Priority** (3 enabled, 1 disabled)
```
grafana          : CPU 0.75   RAM  819M
prometheus       : CPU 1.50   RAM 1638M
promtail         : CPU 0.38   RAM  409M
loki             : DISABLED (heavy)
```

**Medium Priority** (5 enabled)
```
alertmanager     : CPU 0.38   RAM  409M
blackbox-exporter: CPU 0.38   RAM  204M
cadvisor         : CPU 0.75   RAM  409M
crowdsec         : CPU 0.75   RAM  409M
node-exporter    : CPU 0.38   RAM  204M
```

**Low Priority** (4 enabled)
```
oauth2-proxy     : CPU 0.38   RAM  204M
postgres-exporter: CPU 0.19   RAM  102M
pushgateway      : CPU 0.38   RAM  204M
redis-exporter   : CPU 0.19   RAM  102M
```

**Optional Services**: All DISABLED

### Total Allocation
- Services: 16 enabled / 22 total
- CPU: 9.77 / 2.40 CPUs (scaled down to fit)
- RAM: 8491M / 4915M RAM (scaled down to fit)

---

## Example 3: Standard System (Score: 68/100)

### System Configuration
- **CPU**: 8 threads (8 cores) @ 3.0 GHz
- **RAM**: 16GB total / 14GB available
- **Disk**: 250GB SSD
- **Load**: 2.0 / 1.8 / 1.5
- **Tier**: STANDARD
- **Host Reserve**: 30%

### Score Breakdown
- CPU Score: 25/30 (8 threads)
- RAM Score: 28/30 (16GB)
- Disk Score: 15/20 (250GB SSD)
- Network Score: 8/10
- Health Score: 8/10 (moderate load)
- **Total**: 84/100 → Performance tier

### Service Allocation

**Critical Services** (4 enabled)
```
traefik          : CPU 2.00   RAM 1024M
postgres         : CPU 2.00   RAM 2048M
redis            : CPU 1.00   RAM 1024M
socket-proxy     : CPU 0.25   RAM  128M
```

**High Priority** (4 enabled)
```
grafana          : CPU 1.00   RAM 1024M
loki             : CPU 2.00   RAM 2048M
prometheus       : CPU 2.00   RAM 2048M
promtail         : CPU 0.50   RAM  512M
```

**Medium Priority** (5 enabled)
```
alertmanager     : CPU 0.50   RAM  512M
blackbox-exporter: CPU 0.50   RAM  256M
cadvisor         : CPU 1.00   RAM  512M
crowdsec         : CPU 1.00   RAM  512M
node-exporter    : CPU 0.50   RAM  256M
```

**Low Priority** (4 enabled)
```
oauth2-proxy     : CPU 0.50   RAM  256M
postgres-exporter: CPU 0.25   RAM  128M
pushgateway      : CPU 0.50   RAM  256M
redis-exporter   : CPU 0.25   RAM  128M
```

**Optional Services** (4 enabled, 1 disabled)
```
homepage         : CPU 0.25   RAM  256M
jaeger           : CPU 1.00   RAM 1024M
portainer        : CPU 0.50   RAM  512M
redis-commander  : CPU 0.25   RAM  256M
vscode           : DISABLED (heavy)
```

### Total Allocation
- Services: 21 enabled / 22 total
- CPU: 17.00 / 5.60 CPUs (need scaling)
- RAM: 14720M / 11468M RAM (fit with scaling)

---

## Example 4: Performance System (Score: 78/100)

### System Configuration
- **CPU**: 12 threads (12 cores) @ 3.5 GHz
- **RAM**: 32GB total / 30GB available
- **Disk**: 500GB SSD
- **Load**: 3.0 / 2.8 / 2.5
- **Tier**: PERFORMANCE
- **Host Reserve**: 25%

### Score Breakdown
- CPU Score: 28/30 (12 threads)
- RAM Score: 30/30 (32GB)
- Disk Score: 20/20 (500GB SSD)
- Network Score: 10/10
- Health Score: 8/10 (moderate load)
- **Total**: 96/100 → High-performance tier

### Service Allocation

**All 22 Services Enabled**

**Critical Services**
```
traefik          : CPU 2.50   RAM 1280M
postgres         : CPU 2.50   RAM 2560M
redis            : CPU 1.25   RAM 1280M
socket-proxy     : CPU 0.31   RAM  160M
```

**High Priority**
```
grafana          : CPU 1.25   RAM 1280M
loki             : CPU 2.50   RAM 2560M
prometheus       : CPU 2.50   RAM 2560M
promtail         : CPU 0.63   RAM  640M
```

**Medium Priority**
```
alertmanager     : CPU 0.63   RAM  640M
blackbox-exporter: CPU 0.63   RAM  320M
cadvisor         : CPU 1.25   RAM  640M
crowdsec         : CPU 1.25   RAM  640M
node-exporter    : CPU 0.63   RAM  320M
```

**Low Priority**
```
oauth2-proxy     : CPU 0.63   RAM  320M
postgres-exporter: CPU 0.31   RAM  160M
pushgateway      : CPU 0.63   RAM  320M
redis-exporter   : CPU 0.31   RAM  160M
```

**Optional Services**
```
homepage         : CPU 0.31   RAM  320M
jaeger           : CPU 1.25   RAM 1280M
portainer        : CPU 0.63   RAM  640M
redis-commander  : CPU 0.31   RAM  320M
vscode           : CPU 2.50   RAM 2560M
```

### Total Allocation
- Services: 22 enabled / 22 total
- CPU: 23.71 / 9.00 CPUs (scaled to fit)
- RAM: 20940M / 24576M RAM (85% utilization)

---

## Example 5: High-Performance System (Score: 94/100)

### System Configuration
- **CPU**: 32 threads (16 cores) @ 3.8 GHz
- **RAM**: 64GB total / 60GB available
- **Disk**: 1TB NVMe SSD
- **Load**: 4.0 / 3.5 / 3.0
- **Tier**: HIGH-PERFORMANCE
- **Host Reserve**: 20%

### Score Breakdown
- CPU Score: 30/30 (32 threads)
- RAM Score: 30/30 (64GB)
- Disk Score: 20/20 (1TB SSD)
- Network Score: 10/10
- Health Score: 10/10 (good load ratio)
- **Total**: 100/100 → High-performance tier

### Service Allocation

**All 22 Services Enabled with Maximum Resources**

**Critical Services**
```
traefik          : CPU 3.00   RAM 1536M
postgres         : CPU 3.00   RAM 3072M
redis            : CPU 1.50   RAM 1536M
socket-proxy     : CPU 0.38   RAM  192M
```

**High Priority**
```
grafana          : CPU 1.50   RAM 1536M
loki             : CPU 3.00   RAM 3072M
prometheus       : CPU 3.00   RAM 3072M
promtail         : CPU 0.75   RAM  768M
```

**Medium Priority**
```
alertmanager     : CPU 0.75   RAM  768M
blackbox-exporter: CPU 0.75   RAM  384M
cadvisor         : CPU 1.50   RAM  768M
crowdsec         : CPU 1.50   RAM  768M
node-exporter    : CPU 0.75   RAM  384M
```

**Low Priority**
```
oauth2-proxy     : CPU 0.75   RAM  384M
postgres-exporter: CPU 0.38   RAM  192M
pushgateway      : CPU 0.75   RAM  384M
redis-exporter   : CPU 0.38   RAM  192M
```

**Optional Services**
```
homepage         : CPU 0.38   RAM  384M
jaeger           : CPU 1.50   RAM 1536M
portainer        : CPU 0.75   RAM  768M
redis-commander  : CPU 0.38   RAM  384M
vscode           : CPU 3.00   RAM 3072M
```

### Total Allocation
- Services: 22 enabled / 22 total
- CPU: 28.65 / 25.60 CPUs (optimal fit)
- RAM: 25112M / 52428M RAM (48% utilization - room for growth)

### Notes
- All services enabled with maximum multipliers
- Comfortable resource headroom
- Ideal for production workloads
- Can handle traffic spikes

---

## Comparison Summary

| Tier | Score | CPU | RAM | Services | Strategy |
|------|-------|-----|-----|----------|----------|
| Minimal | 0-30 | 1-2 cores | 2-4GB | 4/22 | Critical only |
| Basic | 31-50 | 2-4 cores | 4-8GB | 16/22 | Essential stack |
| Standard | 51-70 | 4-8 cores | 8-16GB | 21/22 | Full stack -1 |
| Performance | 71-85 | 8-16 cores | 16-32GB | 22/22 | Full + generous |
| High-Perf | 86-100 | 16+ cores | 32GB+ | 22/22 | Full + maximum |

## Resource Multipliers by Tier

| Tier | CPU Multiplier | Memory Multiplier | Host Reserve |
|------|----------------|-------------------|--------------|
| Minimal | 0.5x | 0.6x | 50% |
| Basic | 0.75x | 0.8x | 40% |
| Standard | 1.0x | 1.0x | 30% |
| Performance | 1.25x | 1.2x | 25% |
| High-Performance | 1.5x | 1.5x | 20% |

## Service Enablement by Tier

| Service | Minimal | Basic | Standard | Performance | High-Perf |
|---------|---------|-------|----------|-------------|-----------|
| traefik | ✓ | ✓ | ✓ | ✓ | ✓ |
| postgres | ✓ | ✓ | ✓ | ✓ | ✓ |
| redis | ✓ | ✓ | ✓ | ✓ | ✓ |
| socket-proxy | ✓ | ✓ | ✓ | ✓ | ✓ |
| prometheus | ✗ | ✓ | ✓ | ✓ | ✓ |
| grafana | ✗ | ✓ | ✓ | ✓ | ✓ |
| loki | ✗ | ✗ | ✓ | ✓ | ✓ |
| promtail | ✗ | ✓ | ✓ | ✓ | ✓ |
| alertmanager | ✗ | ✓ | ✓ | ✓ | ✓ |
| crowdsec | ✗ | ✓ | ✓ | ✓ | ✓ |
| node-exporter | ✗ | ✓ | ✓ | ✓ | ✓ |
| jaeger | ✗ | ✗ | ✓ | ✓ | ✓ |
| vscode | ✗ | ✗ | ✗ | ✓ | ✓ |
| portainer | ✗ | ✗ | ✓ | ✓ | ✓ |
| homepage | ✗ | ✗ | ✓ | ✓ | ✓ |

## Key Takeaways

1. **Minimal systems** run only what's absolutely necessary
2. **Basic systems** add essential monitoring but skip heavy services
3. **Standard systems** run almost everything with baseline resources
4. **Performance systems** run everything with generous allocations
5. **High-performance systems** maximize all services with room to spare

6. The system **automatically scales down** when resources are tight
7. **Host reserve** increases on lower-tier systems for stability
8. **Service priorities** determine what gets disabled first
9. **Multipliers** ensure performance systems leverage extra capacity
10. **Validation** prevents over-allocation that would cause OOM errors
