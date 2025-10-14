# Blackbox Exporter Configuration

## Overview
Blackbox Exporter probes HTTP/HTTPS/SSL endpoints to monitor availability, response times, and SSL certificate expiry.

## Configuration Location
- **Service Definition**: `/workspaces/jacker/compose/blackbox-exporter.yml`
- **Probe Configuration**: `/workspaces/jacker/config/blackbox-exporter/blackbox.yml`
- **Prometheus Targets**: `/workspaces/jacker/config/prometheus/config/targets.d/exporters/blackbox-probes.json`

## Probe Modules

### HTTP/HTTPS Probes
- **http_2xx**: Standard HTTP endpoint monitoring (allows 200, 401, 403)
- **https_2xx**: Secure HTTPS with TLS verification
- **https_2xx_no_redirect**: For OAuth-protected endpoints (allows redirects)
- **http_post_2xx**: API health check with POST requests

### SSL Certificate Monitoring
- **ssl_expiry**: TCP probe with TLS to monitor certificate validity
- Use this to get alerts before certificates expire

### Additional Probes
- **tcp_connect**: Basic port connectivity check
- **icmp**: Network layer ping test
- **dns_tcp/dns_udp**: DNS resolution verification

## Monitored Endpoints

Current targets (configured in `blackbox-probes.json`):
- Traefik Dashboard: https://traefik.vps1.jacarsystems.net
- Grafana: https://grafana.vps1.jacarsystems.net
- Prometheus: https://prometheus.vps1.jacarsystems.net
- Blackbox Exporter: https://blackbox.vps1.jacarsystems.net
- Alertmanager: https://alertmanager.vps1.jacarsystems.net
- Portainer: https://portainer.vps1.jacarsystems.net
- Homepage: https://homepage.vps1.jacarsystems.net

## Adding New Endpoints

To monitor additional endpoints:

1. Edit `/workspaces/jacker/config/prometheus/config/targets.d/exporters/blackbox-probes.json`
2. Add the URL to the appropriate targets array:
   - HTTPS monitoring: Add to first targets array
   - SSL monitoring: Add to second targets array (format: `hostname:443`)
3. Prometheus will automatically pick up changes within 60 seconds

## Prometheus Integration

Blackbox Exporter is scraped by Prometheus with two job configurations:

### Job: blackbox-https
- **Purpose**: Monitor HTTP/HTTPS endpoint availability
- **Module**: https_2xx_no_redirect
- **Metrics**: Response time, status code, SSL info
- **Scrape Interval**: 60s

### Job: blackbox-ssl
- **Purpose**: Monitor SSL certificate expiry
- **Module**: ssl_expiry
- **Metrics**: Certificate expiry time, validity
- **Scrape Interval**: 60s

## Key Metrics

Monitor these metrics in Prometheus/Grafana:

```promql
# Probe success (1 = up, 0 = down)
probe_success{job="blackbox-https"}

# HTTP response duration
probe_http_duration_seconds{job="blackbox-https"}

# SSL certificate expiry (seconds until expiry)
probe_ssl_earliest_cert_expiry{job="blackbox-ssl"}

# HTTP status code
probe_http_status_code{job="blackbox-https"}
```

## Alerting Rules

Consider creating alerts for:
- Endpoint down: `probe_success == 0`
- SSL expiry < 30 days: `probe_ssl_earliest_cert_expiry < 2592000`
- Slow response: `probe_http_duration_seconds > 2`
- Invalid status code: `probe_http_status_code >= 500`

## Access

Blackbox Exporter dashboard is available at:
- **URL**: https://blackbox.vps1.jacarsystems.net
- **Protection**: OAuth (chain-oauth@file)
- **Port**: 9115 (container), 127.0.0.1:9115 (host)

## Troubleshooting

### Test a probe manually
```bash
# From host
curl "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net&module=https_2xx"

# From within container
docker exec blackbox-exporter wget -qO- "http://localhost:9115/probe?target=https://grafana.vps1.jacarsystems.net&module=https_2xx"
```

### View configuration
```bash
curl http://localhost:9115/config
```

### Check health
```bash
curl http://localhost:9115/health
```

## Resource Limits
- CPU: 0.5 cores (limit), 0.1 cores (reserved)
- Memory: 256MB (limit), 64MB (reserved)
- Read-only filesystem: Yes
- User: nobody (65534:65534)

## Security Features
- No new privileges
- AppArmor profile: unconfined
- Seccomp: unconfined
- Read-only root filesystem
- OAuth protection via Traefik
- TLS verification enabled (not skipping certificate checks)
