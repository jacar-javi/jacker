# Blackbox Exporter Deployment Guide

## Pre-Deployment Checklist

- [x] Service definition created: `/workspaces/jacker/compose/blackbox-exporter.yml`
- [x] Configuration file created: `/workspaces/jacker/config/blackbox-exporter/blackbox.yml`
- [x] Prometheus targets configured: `/workspaces/jacker/config/prometheus/config/targets.d/exporters/blackbox-probes.json`
- [x] Prometheus scrape config updated: `/workspaces/jacker/config/prometheus/config/prometheus.yml`
- [x] Service added to docker-compose includes
- [x] Exporters list updated with blackbox-exporter

## Deployment Steps

### 1. Deploy Blackbox Exporter

```bash
# Navigate to project directory
cd /workspaces/jacker

# Pull the latest image
docker compose pull blackbox-exporter

# Start the service
docker compose up -d blackbox-exporter

# Verify the service is running
docker compose ps blackbox-exporter
docker compose logs blackbox-exporter
```

### 2. Verify Blackbox Exporter Health

```bash
# Check health endpoint
curl http://localhost:9115/health

# Expected output: Blackbox exporter is healthy.

# Check configuration
curl http://localhost:9115/config | head -20

# Test a probe manually
curl "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net&module=https_2xx"
```

### 3. Reload Prometheus Configuration

```bash
# Method 1: Hot reload (if web.enable-lifecycle is enabled)
curl -X POST http://localhost:9090/-/reload

# Method 2: Restart Prometheus
docker compose restart prometheus

# Verify Prometheus picked up the new targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.job | contains("blackbox"))'
```

### 4. Verify Prometheus Scraping

Access Prometheus web UI: https://prometheus.vps1.jacarsystems.net

Check targets:
- Navigate to Status → Targets
- Look for jobs: `blackbox-https` and `blackbox-ssl`
- Verify all endpoints show as "UP"

Query metrics:
```promql
# Check probe success
probe_success{job=~"blackbox-.*"}

# Check SSL certificate expiry (days remaining)
(probe_ssl_earliest_cert_expiry - time()) / 86400

# Check HTTP response time
probe_http_duration_seconds{job="blackbox-https"}
```

### 5. Access Blackbox Exporter Dashboard

- **URL**: https://blackbox.vps1.jacarsystems.net
- **Authentication**: Google OAuth (via OAuth2-Proxy)
- **Note**: First access will require OAuth authentication

### 6. Create Grafana Dashboard (Optional)

Import a Blackbox Exporter dashboard:
1. Go to Grafana: https://grafana.vps1.jacarsystems.net
2. Navigate to Dashboards → Import
3. Use dashboard ID: **7587** (Prometheus Blackbox Exporter)
4. Select Prometheus as the data source
5. Import

Or use dashboard ID: **13659** (Blackbox Exporter Overview)

## Post-Deployment Verification

### Test All Probe Modules

```bash
# Test HTTPS probe
curl "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net&module=https_2xx" | grep probe_success

# Test SSL expiry
curl "http://localhost:9115/probe?target=grafana.vps1.jacarsystems.net:443&module=ssl_expiry" | grep probe_ssl_earliest_cert_expiry

# Test HTTP POST
curl "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net/api/health&module=http_post_2xx"
```

### Verify Metrics in Prometheus

```bash
# Query via Prometheus API
curl -s 'http://localhost:9090/api/v1/query?query=probe_success' | jq '.data.result[] | {instance: .metric.instance, value: .value[1]}'

# Check SSL certificates expiry
curl -s 'http://localhost:9090/api/v1/query?query=probe_ssl_earliest_cert_expiry' | jq '.data.result[] | {instance: .metric.instance, days: ((.value[1] | tonumber) - now) / 86400 | floor}'
```

## Monitoring & Alerts

### Recommended Alert Rules

Create alert rules in `/workspaces/jacker/config/prometheus/config/rules/blackbox-alerts.yml`:

```yaml
groups:
  - name: blackbox_alerts
    interval: 30s
    rules:
      - alert: EndpointDown
        expr: probe_success == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Endpoint {{ $labels.instance }} is down"
          description: "{{ $labels.instance }} has been unreachable for more than 5 minutes."

      - alert: SSLCertificateExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expiring soon for {{ $labels.instance }}"
          description: "SSL certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}."

      - alert: SlowEndpointResponse
        expr: probe_http_duration_seconds > 2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Slow response from {{ $labels.instance }}"
          description: "{{ $labels.instance }} responded in {{ $value }}s, which is above the 2s threshold."
```

### Key Metrics to Monitor

1. **Endpoint Availability**: `probe_success`
2. **Response Time**: `probe_http_duration_seconds`
3. **SSL Expiry**: `probe_ssl_earliest_cert_expiry`
4. **HTTP Status Codes**: `probe_http_status_code`
5. **DNS Resolution Time**: `probe_dns_lookup_time_seconds`
6. **TLS Handshake Time**: `probe_ssl_tls_connect_duration_seconds`

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker compose logs blackbox-exporter --tail=50

# Verify config file syntax
docker compose exec blackbox-exporter blackbox_exporter --config.check --config.file=/config/blackbox.yml

# Check file permissions
ls -la /workspaces/jacker/config/blackbox-exporter/
```

### Prometheus Not Scraping Targets

```bash
# Check Prometheus logs
docker compose logs prometheus --tail=50 | grep blackbox

# Verify Prometheus can reach blackbox-exporter
docker compose exec prometheus wget -qO- http://blackbox-exporter:9115/health

# Check Prometheus configuration
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

### Probes Failing

```bash
# Test probe manually
curl -v "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net&module=https_2xx&debug=true"

# Check blackbox-exporter logs
docker compose logs blackbox-exporter -f

# Verify network connectivity from container
docker compose exec blackbox-exporter wget -qO- https://grafana.vps1.jacarsystems.net
```

## Adding New Endpoints

To monitor additional endpoints:

1. Edit the targets file:
   ```bash
   nano /workspaces/jacker/config/prometheus/config/targets.d/exporters/blackbox-probes.json
   ```

2. Add the new endpoint to the appropriate targets array

3. Prometheus will automatically pick up changes within 60 seconds (no restart needed)

4. Verify in Prometheus UI: Status → Targets → blackbox-https or blackbox-ssl

## Updating Configuration

### Update Probe Modules

1. Edit the configuration:
   ```bash
   nano /workspaces/jacker/config/blackbox-exporter/blackbox.yml
   ```

2. Restart the service:
   ```bash
   docker compose restart blackbox-exporter
   ```

### Update Prometheus Scrape Config

1. Edit Prometheus configuration:
   ```bash
   nano /workspaces/jacker/config/prometheus/config/prometheus.yml
   ```

2. Reload Prometheus:
   ```bash
   curl -X POST http://localhost:9090/-/reload
   # or
   docker compose restart prometheus
   ```

## Backup & Recovery

### Backup Configuration

```bash
# Backup all blackbox-exporter configs
tar -czf blackbox-exporter-config-$(date +%Y%m%d).tar.gz \
  compose/blackbox-exporter.yml \
  config/blackbox-exporter/ \
  config/prometheus/config/targets.d/exporters/blackbox-probes.json
```

### Restore Configuration

```bash
# Extract backup
tar -xzf blackbox-exporter-config-YYYYMMDD.tar.gz

# Restart services
docker compose restart blackbox-exporter prometheus
```

## Performance Tuning

### Adjust Scrape Intervals

Edit `/workspaces/jacker/config/prometheus/config/prometheus.yml`:

```yaml
# For more frequent checks (15s instead of 60s)
file_sd_configs:
  - files:
    - '/etc/prometheus/targets.d/exporters/blackbox-probes.json'
    refresh_interval: 15s
```

### Resource Limits

If needed, adjust in `/workspaces/jacker/compose/blackbox-exporter.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: "1.0"      # Increase from 0.5
      memory: 512M     # Increase from 256M
```

## Security Considerations

- Blackbox Exporter runs as user `nobody` (65534:65534)
- Read-only root filesystem enabled
- No new privileges security option enabled
- OAuth protection via Traefik (chain-oauth@file)
- TLS certificate verification enabled (no insecure skip verify)
- Only localhost port binding (127.0.0.1:9115)

## Support & Resources

- Official Documentation: https://github.com/prometheus/blackbox_exporter
- Grafana Dashboards: https://grafana.com/grafana/dashboards/?search=blackbox
- Prometheus Queries: https://prometheus.io/docs/prometheus/latest/querying/basics/

## Version Information

- **Blackbox Exporter Version**: v0.25.0
- **Image**: prom/blackbox-exporter:v0.25.0
- **Repository**: https://hub.docker.com/r/prom/blackbox-exporter
