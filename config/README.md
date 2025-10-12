# Config Directory

This directory contains configuration files for all Jacker services. These configurations are mounted into containers as Docker configs or bind mounts.

## Directory Structure

```
config/
├── alertmanager/       # Alert routing and notification settings
├── crowdsec/          # Security rules and parsers
├── grafana/           # Dashboards and data sources
├── homepage/          # Dashboard configuration
├── jaeger/            # Tracing configuration
├── loki/              # Log aggregation settings
├── node-exporter/     # System metrics configuration
├── oauth2-proxy/      # OAuth proxy settings
├── postgres/          # Database configuration
├── prometheus/        # Metrics and alerting rules
├── redis/             # Cache configuration
└── traefik/           # Reverse proxy settings
```

## Service Configurations

### Alertmanager
- `alertmanager.yml` - Alert routing and receiver configuration
- `templates/` - Notification templates

### CrowdSec
- `config.yaml.local` - Local API configuration
- `acquis.yaml` - Log acquisition sources
- `parsers/` - Custom log parsers
- `scenarios/` - Detection scenarios

### Grafana
- `provisioning/dashboards/` - Pre-configured dashboards
- `provisioning/datasources/` - Data source definitions
- `provisioning/alerting/` - Alert rules
- `grafana.ini` - Main configuration (if customized)

### Homepage
- `settings.yaml` - General settings
- `services.yaml` - Service definitions (auto-generated)
- `widgets.yaml` - Widget configuration
- `bookmarks.yaml` - Quick links

### Loki
- `loki-config.yml` - Loki server configuration
- `promtail-config.yml` - Log shipper configuration
- `rules/` - Alerting rules for logs

### OAuth2-Proxy
- `oauth2-proxy.cfg` - Proxy configuration
- `templates/` - Custom login page templates

### PostgreSQL
- `postgresql.conf` - Database tuning parameters
- `pg_hba.conf` - Authentication configuration
- `init/` - Initialization scripts

### Prometheus
- `prometheus.yml` - Main configuration
- `rules/` - Recording and alerting rules
- `targets.d/` - Service discovery targets
- `file_sd/` - File-based service discovery

### Redis
- `redis.conf` - Cache configuration
- `users.acl` - User access control lists

### Traefik
- `traefik.yml` - Main static configuration
- `dynamic/` - Dynamic configuration files
- `certs/` - Custom SSL certificates

## Configuration Management

### Using Docker Configs

Most services use Docker configs for immutable configuration:

```yaml
configs:
  prometheus_yml:
    file: ./config/prometheus/prometheus.yml

services:
  prometheus:
    configs:
      - source: prometheus_yml
        target: /etc/prometheus/prometheus.yml
```

### Environment Variable Substitution

Templates in `assets/templates/` are processed with `envsubst`:

```bash
envsubst < assets/templates/loki-config.yml.template > config/loki/loki-config.yml
```

### Updating Configurations

1. **Edit configuration file** in this directory
2. **Restart the service** to apply changes:
   ```bash
   ./jacker restart <service>
   ```
3. **Verify changes** in service logs:
   ```bash
   ./jacker logs <service>
   ```

## Best Practices

### Version Control
- Track all configuration files in git
- Use `.gitignore` for sensitive data
- Comment complex configurations

### Security
- Never store passwords in configs (use Docker secrets)
- Restrict file permissions (644 for configs)
- Use environment variables for sensitive values

### Organization
- Keep service configs in their own directories
- Use descriptive filenames
- Document custom configurations

### Validation
- Validate YAML syntax before applying
- Test configurations in development first
- Keep backups of working configs

## Common Configurations

### Adding Prometheus Targets

Edit `config/prometheus/prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['my-service:9090']
```

### Adding Grafana Dashboards

Place dashboard JSON in `config/grafana/provisioning/dashboards/`:
```json
{
  "dashboard": {
    "title": "My Dashboard",
    ...
  }
}
```

### Configuring CrowdSec Whitelist

Edit `config/crowdsec/parsers/s02-enrich/whitelist.yaml`:
```yaml
name: whitelist
description: "Whitelist trusted IPs"
whitelist:
  reason: "internal network"
  ip:
    - "192.168.1.0/24"
```

### Setting Alertmanager Receivers

Edit `config/alertmanager/alertmanager.yml`:
```yaml
receivers:
  - name: 'email'
    email_configs:
      - to: 'admin@example.com'
        from: 'alerts@example.com'
```

## Troubleshooting

### Configuration Not Loading
1. Check file syntax (YAML/JSON validation)
2. Verify file permissions
3. Check container logs for errors
4. Ensure config is properly mounted

### Service Won't Start
1. Validate configuration syntax
2. Check for missing required fields
3. Review service documentation
4. Test with minimal config

### Changes Not Taking Effect
1. Ensure service was restarted
2. Check if config uses caching
3. Verify correct file is mounted
4. Clear any config caches

## Related Documentation

- [Compose Services](../compose/README.md) - Service definitions
- [Assets](../assets/README.md) - Configuration templates
- [Main README](../README.md) - Project overview