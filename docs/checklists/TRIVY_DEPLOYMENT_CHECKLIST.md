# Trivy Deployment Checklist

## Pre-Deployment Verification

- [ ] Docker Compose is installed and running
- [ ] Socket-proxy service is healthy: `docker ps | grep socket-proxy`
- [ ] Alertmanager service is healthy: `docker ps | grep alertmanager`
- [ ] Traefik service is healthy: `docker ps | grep traefik`
- [ ] Prometheus service is healthy: `docker ps | grep prometheus`

## Environment Configuration

- [ ] Copy `.env.sample` to `.env` if not already done
- [ ] Add Trivy configuration to `.env`:
  ```bash
  TRIVY_PORT=8081
  TRIVY_SEVERITY=CRITICAL,HIGH,MEDIUM
  TRIVY_CRITICAL_THRESHOLD=1
  TRIVY_HIGH_THRESHOLD=5
  TRIVY_SECRETS_THRESHOLD=1
  TRIVY_TIMEOUT=10m
  TRIVY_RETENTION_DAYS=30
  ```
- [ ] Verify `PUBLIC_FQDN` is set correctly in `.env`
- [ ] Verify `DATADIR` and `CONFIGDIR` paths are set

## Directory Structure

- [ ] Create Trivy data directory:
  ```bash
  mkdir -p data/trivy/{cache,reports}
  ```
- [ ] Create Trivy config directory:
  ```bash
  mkdir -p config/trivy
  ```
- [ ] Create logs directory:
  ```bash
  mkdir -p logs
  ```
- [ ] Verify permissions:
  ```bash
  chmod 755 data/trivy data/trivy/cache data/trivy/reports
  chmod 755 config/trivy
  ```

## Configuration Files

- [ ] Verify `config/trivy/trivy.yaml` exists
- [ ] Verify `config/trivy/.trivyignore` exists
- [ ] Review and customize `trivy.yaml` if needed
- [ ] Review severity levels in configuration

## Deployment

- [ ] Deploy Trivy service:
  ```bash
  docker compose -f compose/trivy.yml up -d
  ```
- [ ] Wait for container to start (30-60 seconds)
- [ ] Check container status:
  ```bash
  docker ps | grep trivy
  ```
- [ ] Check container logs:
  ```bash
  docker logs trivy
  ```
- [ ] Verify health:
  ```bash
  docker exec trivy trivy version
  ```

## Initial Testing

- [ ] Update vulnerability database:
  ```bash
  docker exec trivy trivy image --download-db-only
  ```
- [ ] Test scan on Alpine image:
  ```bash
  docker exec trivy trivy image alpine:latest
  ```
- [ ] Verify database cache created:
  ```bash
  ls -lh data/trivy/cache/
  ```

## Scanning Script

- [ ] Verify script is executable:
  ```bash
  ls -l scripts/trivy-scan.sh
  ```
- [ ] Test script help:
  ```bash
  ./scripts/trivy-scan.sh --help
  ```
- [ ] Run first automated scan:
  ```bash
  ./scripts/trivy-scan.sh
  ```
- [ ] Verify reports generated:
  ```bash
  ls -lht data/trivy/reports/ | head -10
  ```
- [ ] Review scan results:
  ```bash
  cat data/trivy/reports/*_summary.txt
  ```

## Alertmanager Integration

- [ ] Verify Alertmanager is reachable:
  ```bash
  curl http://localhost:9093/api/v2/alerts
  ```
- [ ] Test alert sending (if vulnerabilities found):
  ```bash
  # Check Alertmanager UI for Trivy alerts
  ```
- [ ] Verify `ALERTMANAGER_URL` environment variable

## Prometheus Integration

- [ ] Verify Prometheus target file exists:
  ```bash
  cat config/prometheus/config/targets.d/security/trivy.json
  ```
- [ ] Verify alert rules exist:
  ```bash
  cat config/prometheus/config/alerts/trivy.yml
  ```
- [ ] Restart Prometheus to load new configuration:
  ```bash
  docker compose restart prometheus
  ```
- [ ] Check Prometheus targets:
  ```bash
  curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="trivy")'
  ```
- [ ] Verify metrics endpoint:
  ```bash
  curl http://localhost:8081/metrics
  ```

## Web UI Access

- [ ] Verify Traefik route:
  ```bash
  docker exec traefik cat /etc/traefik/traefik.yml | grep trivy
  ```
- [ ] Test local access:
  ```bash
  curl -I http://localhost:8081/healthz
  ```
- [ ] Test OAuth-protected access:
  ```
  https://trivy.yourdomain.com
  ```
- [ ] Login with OAuth provider
- [ ] Verify web UI loads

## Scheduled Scanning

Choose one option:

### Option A: Cron (Recommended)

- [ ] Edit crontab:
  ```bash
  crontab -e
  ```
- [ ] Add daily scan entry:
  ```
  0 2 * * * /path/to/jacker/scripts/trivy-scan.sh >> /path/to/jacker/logs/trivy.log 2>&1
  ```
- [ ] Save and exit
- [ ] Verify crontab entry:
  ```bash
  crontab -l | grep trivy
  ```

### Option B: Systemd Timer

- [ ] Create service file: `/etc/systemd/system/trivy-scan.service`
- [ ] Create timer file: `/etc/systemd/system/trivy-scan.timer`
- [ ] Reload systemd:
  ```bash
  sudo systemctl daemon-reload
  ```
- [ ] Enable timer:
  ```bash
  sudo systemctl enable trivy-scan.timer
  ```
- [ ] Start timer:
  ```bash
  sudo systemctl start trivy-scan.timer
  ```
- [ ] Verify timer status:
  ```bash
  sudo systemctl status trivy-scan.timer
  ```

## Monitoring

- [ ] Check Homepage integration:
  ```
  Visit Homepage dashboard and verify Trivy widget
  ```
- [ ] Verify Prometheus scraping:
  ```
  http://prometheus:9090/targets (search for "trivy")
  ```
- [ ] Check Grafana (if configured):
  ```
  Create Trivy vulnerability dashboard
  ```
- [ ] Review Alertmanager rules:
  ```
  http://alertmanager:9093/#/alerts
  ```

## Documentation Review

- [ ] Read deployment guide: `docs/TRIVY_DEPLOYMENT.md`
- [ ] Read quick start: `docs/guides/TRIVY_QUICKSTART.md`
- [ ] Review integration summary: `TRIVY_INTEGRATION_SUMMARY.md`
- [ ] Bookmark official docs: https://trivy.dev

## Post-Deployment Tasks

- [ ] Configure `.trivyignore` for known false positives
- [ ] Customize alert thresholds in `.env`
- [ ] Set up alert routing in Alertmanager
- [ ] Create Grafana dashboard for vulnerability trends
- [ ] Document custom configurations
- [ ] Train team on Trivy usage
- [ ] Establish vulnerability remediation workflow

## Security Verification

- [ ] Confirm no direct Docker socket mount:
  ```bash
  docker inspect trivy | grep -i "/var/run/docker.sock"
  # Should return nothing
  ```
- [ ] Verify socket-proxy connection:
  ```bash
  docker logs trivy | grep "socket-proxy"
  ```
- [ ] Confirm OAuth protection on web UI
- [ ] Verify read-only config mounts:
  ```bash
  docker inspect trivy | grep -A 5 "/config"
  ```
- [ ] Check resource limits:
  ```bash
  docker stats trivy --no-stream
  ```

## Backup and Recovery

- [ ] Document database cache location: `data/trivy/cache/`
- [ ] Document reports location: `data/trivy/reports/`
- [ ] Set up automated backups (if needed)
- [ ] Test restore procedure (if needed)

## Performance Tuning

- [ ] Monitor initial scan performance
- [ ] Adjust timeout if needed
- [ ] Tune resource limits based on usage
- [ ] Configure parallel scanning (optional)
- [ ] Review report retention policy

## Compliance and Audit

- [ ] Review compliance scanning options
- [ ] Document vulnerability remediation SLAs
- [ ] Set up audit logging (if required)
- [ ] Configure compliance reports (if needed)

## Troubleshooting Preparation

- [ ] Verify log collection:
  ```bash
  docker logs trivy > trivy-initial.log
  ```
- [ ] Test manual database update
- [ ] Test manual container scan
- [ ] Test cleanup script
- [ ] Document common issues and solutions

## Final Verification

- [ ] All services healthy:
  ```bash
  docker ps | grep -E "trivy|socket-proxy|alertmanager|prometheus"
  ```
- [ ] Vulnerability database up-to-date:
  ```bash
  docker exec trivy trivy image --download-db-only
  ```
- [ ] At least one successful scan completed
- [ ] Reports visible in reports directory
- [ ] Metrics available in Prometheus
- [ ] Alerts configured in Alertmanager
- [ ] Web UI accessible via domain
- [ ] Scheduled scans configured
- [ ] Documentation complete

## Sign-Off

| Task | Status | Date | Notes |
|------|--------|------|-------|
| Pre-deployment verification | ☐ | | |
| Environment configuration | ☐ | | |
| Service deployment | ☐ | | |
| Initial testing | ☐ | | |
| Alertmanager integration | ☐ | | |
| Prometheus integration | ☐ | | |
| Scheduled scanning | ☐ | | |
| Web UI access | ☐ | | |
| Monitoring setup | ☐ | | |
| Documentation review | ☐ | | |
| Security verification | ☐ | | |
| Final verification | ☐ | | |

**Deployment Completed By**: ________________

**Date**: ________________

**Sign-off**: ________________

---

## Next Steps After Deployment

1. **Week 1**: Monitor scan results daily, tune alert thresholds
2. **Week 2**: Establish vulnerability remediation workflow
3. **Month 1**: Review compliance, optimize performance
4. **Ongoing**: Regular scans, continuous improvement

---

**Document Version**: 1.0
**Last Updated**: 2024-10-17
**Status**: Production Ready
