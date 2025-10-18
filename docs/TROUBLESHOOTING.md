# Troubleshooting Guide

This guide helps you diagnose and fix common issues with Jacker.

## Table of Contents

- [First Installation Issues](#first-installation-issues)
- [Service-Specific Issues](#service-specific-issues)
- [Network and Connectivity](#network-and-connectivity)
- [Authentication Problems](#authentication-problems)
- [Performance Issues](#performance-issues)
- [Database Issues](#database-issues)

---

## First Installation Issues

Common problems encountered during initial setup and how to resolve them.

### Permission Denied Errors

Permission errors typically occur when Docker containers cannot access their data directories. Different services run as different users inside containers and require specific ownership.

#### Symptoms

```bash
# Common error messages:
Permission denied: /badger/key
mkdir: cannot create directory '/loki': Permission denied
chown: changing ownership of '/plugins-local': Operation not permitted
Permission denied: /data/db
```

#### Services Affected

The following services commonly experience permission issues:

| Service | Container UID:GID | Directory | Symptoms |
|---------|------------------|-----------|----------|
| Traefik | 1000:1000 (PUID:PGID) | `data/traefik/plugins-local` | Cannot download plugins, 500 errors |
| Loki | 10001:10001 | `data/loki` | Cannot start, log aggregation fails |
| Jaeger | 1000:1000 (PUID:PGID) | `data/jaeger/badger`, `data/jaeger/tmp` | Cannot write traces, mkdir errors |
| CrowdSec | 1000:1000 (PUID:PGID) | `data/crowdsec/hub`, `data/crowdsec/data` | Cannot update collections |
| PostgreSQL | 70:70 or 999:999 | `data/postgres`, `config/postgres` | Database fails to initialize |

#### Solution: Run Initialization

The setup process should automatically fix permissions. If you skipped it or it failed:

```bash
# Re-run initialization (safe to run multiple times)
./jacker init

# Or manually fix specific directories:
sudo chown -R 1000:1000 data/traefik
sudo chown -R 10001:10001 data/loki
sudo chown -R 1000:1000 data/jaeger
sudo chown -R 1000:1000 data/crowdsec
sudo chown -R 70:70 data/postgres config/postgres
```

#### Manual Permission Fixes

If initialization doesn't work, fix permissions manually:

**Traefik Plugins:**
```bash
# Create directory if missing
mkdir -p data/traefik/plugins-local
sudo chown -R $(id -u):$(id -g) data/traefik/plugins-local
chmod 755 data/traefik/plugins-local

# Fix acme.json for SSL certificates
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json
```

**Loki:**
```bash
# Loki requires UID 10001
mkdir -p data/loki
sudo chown -R 10001:10001 data/loki
sudo chmod -R 755 data/loki
```

**Jaeger:**
```bash
# Use the fix script
./scripts/fix-jaeger-permissions.sh

# Or manually:
mkdir -p data/jaeger/{badger,tmp}
sudo chown -R $(id -u):$(id -g) data/jaeger
chmod -R 755 data/jaeger
```

**CrowdSec:**
```bash
mkdir -p data/crowdsec/{data,hub,db}
sudo chown -R $(id -u):$(id -g) data/crowdsec
chmod -R 755 data/crowdsec
```

**PostgreSQL:**
```bash
# Use the dedicated script
./scripts/set-postgres-permissions.sh

# Or manually:
sudo chown -R 70:70 data/postgres config/postgres
# Alternative UID if using different Postgres image:
# sudo chown -R 999:999 data/postgres config/postgres
```

For complete directory permission reference, see [docs/DIRECTORY_PERMISSIONS.md](DIRECTORY_PERMISSIONS.md).

### Web Endpoints Returning 404

#### Symptoms

- Accessing `https://service.yourdomain.com` returns 404 Not Found
- Traefik dashboard shows routes but they don't work
- Some services work, others don't

#### Common Causes

1. **Missing OAuth Middleware** - Service requires authentication but middleware isn't configured
2. **DNS not configured** - A records not pointing to your server
3. **Service not started** - Container is down or unhealthy
4. **Incorrect routing rules** - Traefik can't match the host

#### Diagnosis

```bash
# Check which services are running
docker ps

# Check Traefik logs for routing errors
docker logs traefik | grep -i error

# Verify DNS resolution
nslookup service.yourdomain.com

# Check Traefik dashboard for routes
# Visit: https://traefik.yourdomain.com/dashboard/

# Verify middleware configuration
docker exec traefik cat /etc/traefik/rules/middlewares-oauth.yml
```

#### Solutions

**DNS Issues:**
```bash
# Ensure A records exist for all services
# Example DNS records needed:
# yourdomain.com           -> Your_Server_IP
# *.yourdomain.com         -> Your_Server_IP (wildcard)
# traefik.yourdomain.com   -> Your_Server_IP
# grafana.yourdomain.com   -> Your_Server_IP

# Test with dig or nslookup:
dig +short grafana.yourdomain.com
```

**Missing Middleware:**
```bash
# Check if OAuth middleware exists
ls -la config/traefik/rules/middlewares-oauth.yml

# If missing, regenerate from template:
cp templates/traefik/middlewares-oauth.yml config/traefik/rules/
# Edit and set your OAUTH_COOKIE_SECRET

# Restart Traefik to load changes
docker compose restart traefik
```

**Service Not Running:**
```bash
# Check service status
docker compose ps

# Start specific service
docker compose up -d service-name

# View service logs
docker logs service-name
```

### Services Restarting Constantly

#### Symptoms

```bash
# docker ps shows services with "Restarting" status
docker ps
# Or services that keep going up/down
watch -n 1 docker ps
```

#### Common Causes

1. **Health check failures** - Service fails its health check
2. **Missing dependencies** - Database or cache not ready
3. **Configuration errors** - Invalid config files
4. **Resource limits** - Out of memory or CPU
5. **Port conflicts** - Port already in use

#### Diagnosis

```bash
# Check container logs (last 50 lines)
docker logs --tail 50 service-name

# Follow logs in real-time
docker logs -f service-name

# Check container health status
docker inspect service-name | jq '.[0].State.Health'

# Check resource usage
docker stats --no-stream

# Check for port conflicts
sudo netstat -tulpn | grep LISTEN
# Or with docker:
docker compose ps --all
```

#### Solutions

**Configuration Errors:**
```bash
# Validate Docker Compose files
docker compose config

# Validate environment variables
./jacker config validate

# Check for missing secrets
ls -la secrets/

# View detailed container info
docker inspect service-name
```

**Resource Issues:**
```bash
# Check available system resources
free -h
df -h

# Increase resource limits in compose file
# Edit compose/service-name.yml:
deploy:
  resources:
    limits:
      memory: 1G  # Increase if needed
```

**Dependency Issues:**
```bash
# Check if dependencies are healthy
docker compose ps

# Start dependencies first
docker compose up -d postgres redis
sleep 10
docker compose up -d

# View dependency order
docker compose config --services
```

### Checking Service Logs

Logs are your primary diagnostic tool. Here's how to use them effectively:

#### Basic Log Commands

```bash
# View last 100 lines from a service
docker logs --tail 100 service-name

# Follow logs in real-time
docker logs -f service-name

# View logs from last 10 minutes
docker logs --since 10m service-name

# View logs with timestamps
docker logs -t service-name

# View logs from all services
docker compose logs

# Search logs for specific pattern
docker logs service-name 2>&1 | grep -i error
```

#### Service-Specific Log Locations

Some services store logs in volumes:

```bash
# Traefik access logs
tail -f data/traefik/access.log

# CrowdSec logs
docker exec crowdsec tail -f /var/log/crowdsec.log

# PostgreSQL logs
docker logs postgres

# Loki (aggregated logs via Grafana)
# Visit: https://grafana.yourdomain.com
# Select "Loki" datasource and query: {container="service-name"}
```

#### Common Error Patterns

**Permission Errors:**
```bash
docker logs service-name 2>&1 | grep -i "permission denied"
```

**Connection Errors:**
```bash
docker logs service-name 2>&1 | grep -i "connection refused\|timeout\|unreachable"
```

**Authentication Errors:**
```bash
docker logs service-name 2>&1 | grep -i "auth\|unauthorized\|forbidden"
```

**Resource Errors:**
```bash
docker logs service-name 2>&1 | grep -i "out of memory\|oom\|killed"
```

### Pre-Deployment Validation

Run these checks before deploying to catch issues early:

#### Validation Script

```bash
# Run comprehensive validation
./scripts/validate.sh

# This checks:
# - Docker and Docker Compose versions
# - Environment file syntax
# - Secret file permissions
# - DNS configuration
# - SSL certificate files
# - Network configuration
# - Required directories
# - Configuration file syntax
```

#### Manual Validation Steps

```bash
# 1. Check Docker version
docker --version
# Requires: Docker 24.0+

# 2. Check Docker Compose version
docker compose version
# Requires: Docker Compose v2.20+

# 3. Validate Docker Compose files
docker compose config > /dev/null
echo $?  # Should output 0 (success)

# 4. Check environment file
cat .env | grep -v "^#" | grep -v "^$"
# Verify all required variables are set

# 5. Check secrets
ls -la secrets/
# Verify permissions are 600 or 400 (not world-readable)

# 6. Test DNS resolution
nslookup traefik.yourdomain.com
nslookup grafana.yourdomain.com

# 7. Check disk space
df -h
# Ensure at least 20GB free

# 8. Check memory
free -h
# Ensure at least 2GB available

# 9. Verify ports are free
sudo netstat -tulpn | grep -E ":(80|443|8080|9090|3000)\s"
# Should be empty if ports are available
```

#### Post-Deployment Health Checks

```bash
# Run health checks after deployment
./scripts/health-check.sh

# Or manually:
# 1. Check all containers are running
docker compose ps

# 2. Check container health status
docker ps --format "table {{.Names}}\t{{.Status}}"

# 3. Test web endpoints
curl -I https://traefik.yourdomain.com
curl -I https://grafana.yourdomain.com

# 4. Check service discovery
docker exec traefik wget -O- http://localhost:8080/api/http/routers
```

---

## Service-Specific Issues

### Traefik

**Issue: SSL Certificate Errors**

```bash
# Check acme.json exists and has correct permissions
ls -la data/traefik/acme/acme.json
# Should be: -rw------- (600)

# If missing or wrong permissions:
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json
docker compose restart traefik

# Check Let's Encrypt rate limits
docker logs traefik 2>&1 | grep -i "rate limit"
# If rate limited, use staging environment temporarily:
# Set TRAEFIK_ACME_ENV=staging in .env
```

**Issue: Plugin Download Failures**

```bash
# Check permissions on plugins directory
ls -la data/traefik/plugins-local/

# Fix permissions
sudo chown -R $(id -u):$(id -g) data/traefik/plugins-local
chmod -R 755 data/traefik/plugins-local

# Clear plugin cache and restart
docker compose down traefik
rm -rf data/traefik/plugins-local/*
docker compose up -d traefik
```

### CrowdSec

**Issue: Collections Not Updating**

```bash
# Check hub permissions
ls -la data/crowdsec/hub/

# Fix permissions
sudo chown -R $(id -u):$(id -g) data/crowdsec/hub
docker compose restart crowdsec

# Manually update collections
docker exec crowdsec cscli collections upgrade crowdsecurity/traefik
docker exec crowdsec cscli hub update
```

### PostgreSQL

**Issue: Database Connection Refused**

```bash
# Check if PostgreSQL is running
docker ps | grep postgres

# Check health status
docker inspect postgres | jq '.[0].State.Health'

# View logs
docker logs postgres

# Check connection from another container
docker exec oauth2-proxy pg_isready -h postgres -U jacker

# Verify password secret
cat secrets/postgres_password
# Should contain only the password, no extra whitespace
```

### OAuth2-Proxy

**Issue: Authentication Loop**

```bash
# Check cookie secret is set
docker exec oauth2-proxy env | grep COOKIE_SECRET

# Verify OAuth credentials
cat secrets/oauth_client_id
cat secrets/oauth_client_secret

# Check Redis connection
docker exec oauth2-proxy redis-cli -h redis ping

# Verify allowed email domains
docker exec oauth2-proxy env | grep WHITELIST
```

---

## Network and Connectivity

### DNS Resolution Issues

```bash
# Test DNS from host
nslookup service.yourdomain.com

# Test DNS from inside container
docker exec traefik nslookup service.yourdomain.com

# Check /etc/hosts for conflicts
grep yourdomain.com /etc/hosts

# Verify DNS propagation globally
# Visit: https://dnschecker.org
```

### Port Conflicts

```bash
# Check what's using common ports
sudo netstat -tulpn | grep -E ":(80|443|8080|9090|3000)\s"

# Or with lsof:
sudo lsof -i :80
sudo lsof -i :443

# Stop conflicting services
sudo systemctl stop apache2
sudo systemctl stop nginx
```

### Network Isolation

```bash
# List Docker networks
docker network ls

# Inspect specific network
docker network inspect jacker_traefik_proxy

# Verify container network connections
docker inspect service-name | jq '.[0].NetworkSettings.Networks'

# Test connectivity between containers
docker exec oauth2-proxy ping -c 3 postgres
docker exec traefik ping -c 3 redis
```

---

## Authentication Problems

### OAuth Not Working

**Google OAuth:**

```bash
# Verify credentials are correct
# Check Google Cloud Console:
# https://console.cloud.google.com/apis/credentials

# Ensure redirect URIs are configured:
# https://oauth.yourdomain.com/oauth2/callback

# Check OAuth2-Proxy logs
docker logs oauth2-proxy 2>&1 | grep -i error
```

### Locked Out of Services

```bash
# Bypass OAuth for emergency access
# Temporarily disable OAuth middleware:
# 1. Edit compose file for specific service
# 2. Comment out OAuth middleware in labels
# 3. Restart service

# Example for Grafana:
# Edit compose/grafana.yml:
# Comment: traefik.http.routers.grafana.middlewares=oauth@file

docker compose up -d grafana

# Don't forget to re-enable OAuth after fixing the issue!
```

---

## Performance Issues

### High CPU Usage

```bash
# Identify high CPU containers
docker stats --no-stream | sort -k 3 -h

# Check specific container
docker stats service-name --no-stream

# Reduce resource usage:
# 1. Tune resource limits in compose files
# 2. Disable unnecessary features
# 3. Optimize queries (for databases)
```

### High Memory Usage

```bash
# Check memory by container
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"

# Check for memory leaks
docker stats service-name

# Restart memory-hungry service
docker compose restart service-name

# Permanently limit memory in compose file:
deploy:
  resources:
    limits:
      memory: 512M
```

### Slow Response Times

```bash
# Check Traefik metrics
curl http://localhost:8080/metrics | grep http_request_duration

# View in Grafana
# Dashboard: Traefik Performance

# Check database performance
docker exec postgres pg_stat_activity

# Check Redis performance
docker exec redis redis-cli INFO stats
```

---

## Database Issues

### PostgreSQL Recovery

```bash
# Check database status
docker exec postgres pg_isready

# View active connections
docker exec postgres psql -U jacker -c "SELECT * FROM pg_stat_activity;"

# Backup database
docker exec postgres pg_dump -U jacker jacker > backup.sql

# Restore database
cat backup.sql | docker exec -i postgres psql -U jacker
```

### Redis Connection Issues

```bash
# Test Redis connection
docker exec redis redis-cli ping
# Should return: PONG

# Check Redis info
docker exec redis redis-cli INFO

# Monitor Redis commands
docker exec redis redis-cli MONITOR

# Check authentication
docker exec redis redis-cli -a "$(cat secrets/redis_password)" ping
```

---

## Getting Additional Help

If you're still experiencing issues:

1. **Check Logs**: Always start with `docker logs service-name`
2. **Search Issues**: [GitHub Issues](https://github.com/jacar-javi/jacker/issues)
3. **Documentation**: [Complete Documentation](https://jacker.jacar.es)
4. **Community**: [GitHub Discussions](https://github.com/jacar-javi/jacker/discussions)
5. **Support**: [support@jacker.jacar.es](mailto:support@jacker.jacar.es)

### Information to Include in Bug Reports

When reporting issues, include:

```bash
# System information
./jacker info

# Service status
docker compose ps

# Relevant logs (last 100 lines)
docker logs --tail 100 service-name

# Environment (sanitized)
cat .env | grep -v "SECRET\|PASSWORD\|KEY"

# Docker version
docker --version
docker compose version

# OS information
uname -a
```
