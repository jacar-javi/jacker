# Trivy Container Vulnerability Scanner - Deployment Guide

## Overview

Trivy is a comprehensive and versatile security scanner that detects:
- **Vulnerabilities (CVEs)** in OS packages and application dependencies
- **Exposed secrets** (API keys, passwords, tokens)
- **Misconfigurations** in container images and IaC files
- **License compliance** issues

This deployment integrates Trivy into Jacker's security infrastructure with automated scanning, alerting, and reporting.

## Architecture

### Components

1. **Trivy Server** (`compose/trivy.yml`)
   - Runs in server mode for continuous availability
   - Accesses Docker via socket-proxy (secure, no direct socket mount)
   - Exposes web UI via Traefik with OAuth protection

2. **Scanning Script** (`scripts/trivy-scan.sh`)
   - Automated container vulnerability scanning
   - Parses results and sends alerts to Alertmanager
   - Generates JSON and human-readable reports

3. **Configuration** (`config/trivy/`)
   - `trivy.yaml` - Main configuration
   - `.trivyignore` - Excluded vulnerabilities

4. **Integration Points**
   - **Socket Proxy**: Secure Docker API access
   - **Alertmanager**: Alert routing for critical findings
   - **Prometheus**: Metrics scraping
   - **Traefik**: Reverse proxy with OAuth
   - **Homepage**: Dashboard integration

## Installation

### Prerequisites

```bash
# Ensure required services are running
docker ps | grep -E "socket-proxy|alertmanager|traefik"
```

### Step 1: Deploy Trivy Service

```bash
# Create data directories
mkdir -p data/trivy/{cache,reports}
mkdir -p config/trivy

# Deploy Trivy
docker compose -f compose/trivy.yml up -d

# Verify deployment
docker logs trivy
docker exec trivy trivy version
```

### Step 2: Configure Environment Variables

Edit `.env` file:

```bash
# Trivy Configuration
TRIVY_PORT=8081
TRIVY_SEVERITY=CRITICAL,HIGH,MEDIUM
TRIVY_CRITICAL_THRESHOLD=1
TRIVY_HIGH_THRESHOLD=5
TRIVY_SECRETS_THRESHOLD=1
TRIVY_TIMEOUT=10m
TRIVY_RETENTION_DAYS=30
```

### Step 3: Test Initial Scan

```bash
# Update vulnerability database
docker exec trivy trivy image --download-db-only

# Scan a test image
docker exec trivy trivy image alpine:latest

# Run automated scan script
./scripts/trivy-scan.sh --help
./scripts/trivy-scan.sh
```

### Step 4: Schedule Automated Scans

#### Option A: Cron (Recommended)

Add to system crontab:

```bash
# Edit crontab
crontab -e

# Add daily scan at 2 AM
0 2 * * * /path/to/jacker/scripts/trivy-scan.sh >> /path/to/jacker/logs/trivy-scan.log 2>&1

# Add hourly quick scans (optional)
0 * * * * /path/to/jacker/scripts/trivy-scan.sh >> /path/to/jacker/logs/trivy-scan.log 2>&1
```

#### Option B: Systemd Timer

Create systemd service:

```bash
# /etc/systemd/system/trivy-scan.service
[Unit]
Description=Trivy Container Vulnerability Scan
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=YOUR_USER
WorkingDirectory=/path/to/jacker
ExecStart=/path/to/jacker/scripts/trivy-scan.sh
StandardOutput=append:/path/to/jacker/logs/trivy-scan.log
StandardError=append:/path/to/jacker/logs/trivy-scan.log

[Install]
WantedBy=multi-user.target
```

Create systemd timer:

```bash
# /etc/systemd/system/trivy-scan.timer
[Unit]
Description=Trivy Container Vulnerability Scan Timer
Requires=trivy-scan.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable trivy-scan.timer
sudo systemctl start trivy-scan.timer
sudo systemctl status trivy-scan.timer
```

#### Option C: Docker Events (Real-time)

For scanning on container start:

```bash
# Monitor Docker events and trigger scans
docker events --filter 'event=start' --format '{{.Actor.Attributes.name}}' | \
  while read container; do
    ./scripts/trivy-scan.sh --container "$container"
  done
```

## Usage

### Manual Scanning

```bash
# Scan all running containers
./scripts/trivy-scan.sh

# Scan specific container
./scripts/trivy-scan.sh --container traefik

# Clean up old reports only
./scripts/trivy-scan.sh --cleanup-only

# View help
./scripts/trivy-scan.sh --help
```

### Server Mode (Client Access)

```bash
# Scan image via Trivy server
docker exec trivy trivy client --remote http://localhost:8080 alpine:latest

# Scan from external client
trivy client --remote https://trivy.yourdomain.com alpine:latest
```

### Report Viewing

```bash
# Latest reports are in:
ls -lht data/trivy/reports/

# View JSON report
cat data/trivy/reports/traefik_20241017_020000.json | jq

# View human-readable summary
cat data/trivy/reports/traefik_20241017_020000_summary.txt
```

## Alert Configuration

### Alertmanager Integration

Trivy sends alerts to Alertmanager when:
- CRITICAL vulnerabilities ≥ 1
- HIGH vulnerabilities ≥ 5 (configurable)
- Secrets found ≥ 1

Alert format:

```json
{
  "labels": {
    "alertname": "TrivyVulnerabilitiesDetected",
    "severity": "critical",
    "service": "trivy",
    "container": "container-name"
  },
  "annotations": {
    "summary": "Container has X CRITICAL, Y HIGH vulnerabilities",
    "description": "Trivy scan detected issues...",
    "critical_count": "X",
    "high_count": "Y",
    "secrets_count": "Z",
    "report_path": "/path/to/report.json"
  }
}
```

### Customizing Alert Thresholds

Edit `.env`:

```bash
# Alert if any CRITICAL vulnerability
TRIVY_CRITICAL_THRESHOLD=1

# Alert if 10+ HIGH vulnerabilities
TRIVY_HIGH_THRESHOLD=10

# Alert if any secret found
TRIVY_SECRETS_THRESHOLD=1
```

## Configuration Options

### Trivy Server Configuration

`compose/trivy.yml` environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TRIVY_SEVERITY` | `CRITICAL,HIGH,MEDIUM` | Severity levels to scan |
| `TRIVY_SCANNERS` | `vuln,secret,config` | Scanner types |
| `TRIVY_TIMEOUT` | `10m` | Scan timeout |
| `TRIVY_DEBUG` | `false` | Enable debug logging |
| `TRIVY_NO_PROGRESS` | `true` | Disable progress bar |

### Scanning Script Configuration

`scripts/trivy-scan.sh` environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `TRIVY_CONTAINER` | `trivy` | Trivy container name |
| `TRIVY_SEVERITY` | `CRITICAL,HIGH,MEDIUM` | Severity filter |
| `TRIVY_FORMAT` | `json` | Report format |
| `TRIVY_RETENTION_DAYS` | `30` | Report retention |
| `TRIVY_EXCLUDE_PATTERN` | `^(trivy\|socket-proxy)$` | Excluded containers |
| `ALERTMANAGER_URL` | `http://localhost:9093` | Alertmanager endpoint |

### Configuration File

`config/trivy/trivy.yaml` - Main configuration:

```yaml
scan:
  security-checks:
    - vuln
    - secret
    - config
  severity:
    - CRITICAL
    - HIGH
    - MEDIUM

db:
  repository: ghcr.io/aquasecurity/trivy-db
  skip-update: false

vulnerability:
  ignore-file: /config/.trivyignore
```

### Ignore File

`config/trivy/.trivyignore` - Exclude specific CVEs:

```bash
# Temporary exclusions
CVE-2023-12345  # Fixed in next release

# False positives
CVE-2024-67890  # Not applicable to our use case
```

## Web UI Access

Access Trivy web UI via Traefik:

```
https://trivy.yourdomain.com
```

Features:
- OAuth authentication required
- View scan history
- Download reports
- Trigger manual scans
- Server API access

## Monitoring

### Prometheus Metrics

Trivy exposes metrics at `/metrics`:

```yaml
# Prometheus scrape config (auto-configured via labels)
- job_name: trivy
  static_configs:
    - targets: ['trivy:8080']
```

Key metrics:
- `trivy_vulnerabilities_total` - Total vulnerabilities by severity
- `trivy_scan_duration_seconds` - Scan duration
- `trivy_db_age_seconds` - Vulnerability DB age

### Health Checks

```bash
# Container health
docker ps | grep trivy

# Service health
curl http://localhost:8081/healthz

# Database status
docker exec trivy trivy --version
```

## Troubleshooting

### Issue: Database Update Fails

```bash
# Manual database update
docker exec trivy trivy image --download-db-only

# Check network connectivity
docker exec trivy ping ghcr.io

# Use offline mode (if internet limited)
# Edit compose/trivy.yml:
TRIVY_SKIP_DB_UPDATE=true
```

### Issue: Scan Timeout

```bash
# Increase timeout
# Edit .env:
TRIVY_TIMEOUT=30m

# Restart Trivy
docker compose -f compose/trivy.yml restart trivy
```

### Issue: Too Many False Positives

```bash
# Add to config/trivy/.trivyignore
echo "CVE-2023-XXXXX  # False positive" >> config/trivy/.trivyignore

# Or ignore unfixed vulnerabilities
# Edit config/trivy/trivy.yaml:
vulnerability:
  ignore-unfixed: true
```

### Issue: Alerts Not Sent

```bash
# Check Alertmanager connectivity
curl -X POST http://localhost:9093/api/v2/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"test"}}]'

# Verify environment variable
echo $ALERTMANAGER_URL

# Check script logs
./scripts/trivy-scan.sh 2>&1 | tee trivy-debug.log
```

### Issue: High Memory Usage

```bash
# Reduce resource limits
# Edit compose/trivy.yml:
deploy:
  resources:
    limits:
      memory: 1G

# Or scan fewer containers at once
# Edit scripts/trivy-scan.sh to add delays between scans
```

## Security Considerations

### Best Practices

1. **Regular Scans**
   - Schedule daily full scans
   - Enable real-time scanning on container start
   - Review reports weekly

2. **Alert Tuning**
   - Start with CRITICAL only
   - Gradually add HIGH and MEDIUM
   - Use `.trivyignore` for known false positives

3. **Database Updates**
   - Update DB before each scan
   - Monitor DB age with Prometheus
   - Cache DB locally for faster scans

4. **Access Control**
   - OAuth authentication enabled by default
   - Restrict API access via Traefik
   - Secure report storage (limited retention)

5. **Integration**
   - Route alerts to appropriate teams
   - Integrate with ticketing systems
   - Dashboard visualization in Grafana

### Compliance

Trivy supports compliance scanning:

```bash
# Docker CIS benchmark
docker exec trivy trivy image --compliance docker-cis-1.6.0 nginx

# Custom compliance spec
# Edit config/trivy/trivy.yaml:
compliance:
  spec: docker-cis-1.6.0
```

## Performance Optimization

### Database Caching

```bash
# Pre-download databases
docker exec trivy trivy image --download-db-only

# Verify cache
ls -lh data/trivy/cache/
```

### Parallel Scanning

```bash
# Scan multiple containers in parallel (use with caution)
# Modify scripts/trivy-scan.sh to use GNU parallel or xargs
```

### Offline Mode

```bash
# For air-gapped environments
# 1. Download DB externally
# 2. Copy to data/trivy/cache/
# 3. Enable offline mode:
TRIVY_SKIP_DB_UPDATE=true
TRIVY_OFFLINE_SCAN=true
```

## Integration Examples

### CI/CD Pipeline

```yaml
# GitLab CI example
trivy_scan:
  stage: security
  script:
    - trivy client --remote https://trivy.yourdomain.com $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - trivy client --remote https://trivy.yourdomain.com --exit-code 1 --severity CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

### Slack Notifications

Configure Alertmanager to route Trivy alerts to Slack:

```yaml
# alertmanager.yml
route:
  routes:
    - match:
        service: trivy
      receiver: slack-security

receivers:
  - name: slack-security
    slack_configs:
      - api_url: YOUR_SLACK_WEBHOOK
        channel: '#security-alerts'
        title: 'Container Vulnerability Alert'
```

### Grafana Dashboard

Import Trivy dashboard:
- Use Prometheus metrics
- Visualize vulnerability trends
- Track scan coverage
- Monitor alert frequency

## Maintenance

### Daily Tasks
- None (automated scanning)

### Weekly Tasks
- Review scan reports
- Triage new vulnerabilities
- Update `.trivyignore` if needed

### Monthly Tasks
- Review alert thresholds
- Clean up old reports manually if needed
- Update Trivy container image
- Review compliance status

### Quarterly Tasks
- Audit excluded CVEs
- Review scanning coverage
- Optimize performance
- Update documentation

## References

- **Official Documentation**: https://trivy.dev
- **GitHub Repository**: https://github.com/aquasecurity/trivy
- **Vulnerability Database**: https://github.com/aquasecurity/trivy-db
- **Docker Hub**: https://hub.docker.com/r/aquasec/trivy

## Support

For issues or questions:
1. Check Trivy logs: `docker logs trivy`
2. Review script logs: `./scripts/trivy-scan.sh 2>&1 | tee debug.log`
3. Consult official documentation
4. Open GitHub issue: https://github.com/aquasecurity/trivy/issues

---

**Deployment Status**: ✅ Ready for Production

**Last Updated**: 2024-10-17

**Maintained By**: Jacker Security Team
