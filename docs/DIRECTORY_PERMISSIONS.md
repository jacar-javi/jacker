# Directory Permissions Reference

This document provides a comprehensive reference for all directory permissions required by Jacker services.

## Table of Contents

- [Overview](#overview)
- [Permission Requirements by Service](#permission-requirements-by-service)
- [Why Services Need Specific Permissions](#why-services-need-specific-permissions)
- [Automatic Permission Setup](#automatic-permission-setup)
- [Manual Permission Fixes](#manual-permission-fixes)
- [Troubleshooting Permission Issues](#troubleshooting-permission-issues)

---

## Overview

Jacker services run as different users inside containers for security and compatibility. Docker creates host directories with `root:root` ownership by default, which causes permission issues when containers try to write to these directories.

### Key Concepts

- **PUID/PGID**: User/Group IDs from your system (typically `1000:1000`)
- **Container UID/GID**: User ID inside the container (varies by service)
- **Volume Mounts**: Directories on host mounted into containers
- **Ownership**: Must match container's UID:GID for write access

---

## Permission Requirements by Service

### Core Infrastructure

| Directory | Owner UID:GID | Permissions | Purpose | Notes |
|-----------|---------------|-------------|---------|-------|
| `data/traefik/acme` | PUID:PGID (1000:1000) | 755 (dir), 600 (files) | SSL certificates | acme.json must be 600 |
| `data/traefik/plugins-local` | PUID:PGID (1000:1000) | 755 | Traefik plugins | Download and cache plugins |
| `config/traefik` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Traefik configuration | Read-only for container |
| `data/postgres` | 70:70 or 999:999 | 700 | PostgreSQL data | Varies by image version |
| `config/postgres` | 70:70 or 999:999 | 755 (dir), 600 (files) | PostgreSQL config | Includes SSL certs |
| `data/redis` | 999:999 | 755 | Redis data | Managed by Redis image |
| `config/redis` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Redis configuration | Read-only for container |

### Monitoring & Observability

| Directory | Owner UID:GID | Permissions | Purpose | Notes |
|-----------|---------------|-------------|---------|-------|
| `data/loki` | 10001:10001 | 755 | Loki data storage | Fixed UID in Loki image |
| `config/loki` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Loki configuration | Read-only for container |
| `data/promtail` | PUID:PGID (1000:1000) | 755 | Promtail positions | Tracks log file positions |
| `data/prometheus` | 65534:65534 | 755 | Prometheus metrics | nobody:nobody user |
| `config/prometheus` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Prometheus config | Read-only for container |
| `data/grafana` | 472:472 | 755 | Grafana data | Fixed UID in Grafana image |
| `config/grafana` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Grafana config | Read-only for container |
| `data/jaeger/badger` | PUID:PGID (1000:1000) | 755 | Jaeger trace storage | BadgerDB files |
| `data/jaeger/tmp` | PUID:PGID (1000:1000) | 755 | Jaeger temp files | Temporary data |
| `data/alertmanager` | 65534:65534 | 755 | Alertmanager data | nobody:nobody user |
| `config/alertmanager` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Alertmanager config | Read-only for container |

### Security & Authentication

| Directory | Owner UID:GID | Permissions | Purpose | Notes |
|-----------|---------------|-------------|---------|-------|
| `data/crowdsec/data` | PUID:PGID (1000:1000) | 755 | CrowdSec decisions | IP ban decisions |
| `data/crowdsec/hub` | PUID:PGID (1000:1000) | 755 | CrowdSec collections | Parsers and scenarios |
| `data/crowdsec/db` | PUID:PGID (1000:1000) | 755 | CrowdSec database | SQLite database |
| `config/crowdsec` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | CrowdSec config | Configuration files |
| `config/oauth2-proxy` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | OAuth config | OAuth2 Proxy settings |
| `data/authentik` | PUID:PGID (1000:1000) | 755 | Authentik data | Media and templates |
| `secrets` | PUID:PGID (1000:1000) | 700 | Docker secrets | Sensitive credentials |

### Management Tools

| Directory | Owner UID:GID | Permissions | Purpose | Notes |
|-----------|---------------|-------------|---------|-------|
| `data/homepage` | PUID:PGID (1000:1000) | 755 | Homepage data | Icons and cache |
| `config/homepage` | PUID:PGID (1000:1000) | 755 (dir), 644 (files) | Homepage config | Service definitions |
| `data/portainer` | PUID:PGID (1000:1000) | 755 | Portainer data | Container data |
| `data/vscode` | PUID:PGID (1000:1000) | 755 | VS Code settings | IDE configuration |
| `data/redis-commander` | PUID:PGID (1000:1000) | 755 | Redis Commander | UI state |

### Logs

| Directory | Owner UID:GID | Permissions | Purpose | Notes |
|-----------|---------------|-------------|---------|-------|
| `logs` | PUID:PGID (1000:1000) | 755 | Application logs | Centralized logging |
| `data/loki/logs` | 10001:10001 | 755 | Loki logs | Loki service logs |

---

## Why Services Need Specific Permissions

### User ID Variations

Different Docker images use different UIDs for security and historical reasons:

#### System Users (PUID:PGID - Default 1000:1000)

**Services**: Traefik, CrowdSec, Jaeger, Homepage, Portainer, VS Code

**Reason**: These services are configured to run as the host user to simplify file access and permissions. They inherit PUID/PGID from environment variables.

**Benefits**:
- Easy file management (same owner as host user)
- No permission conflicts
- Can edit config files without sudo

#### Fixed UIDs

##### Loki (10001:10001)

**Reason**: Hardcoded in the official Loki image for security isolation.

**Why not PUID**: Loki runs as a dedicated user to prevent privilege escalation and ensure consistent security across deployments.

##### Grafana (472:472)

**Reason**: Standard Grafana user UID defined in official image.

**Why not PUID**: Historical compatibility and multi-platform support. UID 472 is recognized across different systems.

##### PostgreSQL (70:70 or 999:999)

**Reason**: Varies by image version. Alpine-based uses 70, Debian-based uses 999.

**Why not PUID**: Database security requires dedicated user. Different base images have different conventions.

##### Prometheus/Alertmanager (65534:65534)

**Reason**: Runs as `nobody:nobody` user for maximum security.

**Why not PUID**: Principle of least privilege. Service only needs read access to config and write to data.

##### Redis (999:999)

**Reason**: Standard Redis user in official image.

**Why not PUID**: Database service requires isolated user for security.

### Security Implications

1. **Principle of Least Privilege**: Each service runs with minimum required permissions
2. **Isolation**: Services cannot access each other's files
3. **Attack Surface**: If one service is compromised, attacker can't easily access other data
4. **Multi-tenancy**: Different UIDs allow running multiple instances safely

---

## Automatic Permission Setup

### During Installation

The `./jacker init` command automatically:

1. Creates all required directories
2. Sets correct ownership (UID:GID)
3. Sets appropriate permissions (755/644/600)
4. Handles special cases (acme.json, secrets)

```bash
# Automatic setup (recommended)
./jacker init
```

### What Gets Configured

The setup process runs these operations:

```bash
# Data directories
mkdir -p data/{traefik,loki,jaeger,crowdsec,prometheus,grafana,postgres,redis}
mkdir -p config/{traefik,loki,prometheus,grafana,crowdsec,oauth2-proxy}
mkdir -p secrets logs

# Traefik permissions
chown -R 1000:1000 data/traefik
chmod 755 data/traefik/plugins-local
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json

# Loki permissions (UID 10001)
chown -R 10001:10001 data/loki
chmod 755 data/loki

# Jaeger permissions
chown -R 1000:1000 data/jaeger
chmod 755 data/jaeger/{badger,tmp}

# CrowdSec permissions
chown -R 1000:1000 data/crowdsec
chmod 755 data/crowdsec/{data,hub,db}

# PostgreSQL permissions (varies by image)
chown -R 70:70 data/postgres config/postgres
chmod 700 data/postgres

# Secrets permissions
chown -R 1000:1000 secrets
chmod 700 secrets
chmod 600 secrets/*

# Config files read-only
find config -type f -exec chmod 644 {} \;
find config -type d -exec chmod 755 {} \;
```

---

## Manual Permission Fixes

If automatic setup fails or you need to fix specific services:

### Fix All Permissions

```bash
#!/bin/bash
# Run this script to fix all directory permissions

DATADIR="./data"
CONFIGDIR="./config"
SECRETSDIR="./secrets"
PUID=$(id -u)
PGID=$(id -g)

# Core infrastructure
sudo chown -R ${PUID}:${PGID} ${DATADIR}/traefik
sudo chmod 755 ${DATADIR}/traefik/plugins-local
sudo chmod 600 ${DATADIR}/traefik/acme/*.json

sudo chown -R 70:70 ${DATADIR}/postgres ${CONFIGDIR}/postgres
sudo chmod 700 ${DATADIR}/postgres

sudo chown -R 999:999 ${DATADIR}/redis

# Monitoring
sudo chown -R 10001:10001 ${DATADIR}/loki
sudo chmod 755 ${DATADIR}/loki

sudo chown -R ${PUID}:${PGID} ${DATADIR}/promtail

sudo chown -R 65534:65534 ${DATADIR}/prometheus
sudo chmod 755 ${DATADIR}/prometheus

sudo chown -R 472:472 ${DATADIR}/grafana
sudo chmod 755 ${DATADIR}/grafana

sudo chown -R ${PUID}:${PGID} ${DATADIR}/jaeger
sudo chmod -R 755 ${DATADIR}/jaeger

sudo chown -R 65534:65534 ${DATADIR}/alertmanager
sudo chmod 755 ${DATADIR}/alertmanager

# Security
sudo chown -R ${PUID}:${PGID} ${DATADIR}/crowdsec
sudo chmod -R 755 ${DATADIR}/crowdsec

# Management
sudo chown -R ${PUID}:${PGID} ${DATADIR}/homepage
sudo chown -R ${PUID}:${PGID} ${DATADIR}/portainer
sudo chown -R ${PUID}:${PGID} ${DATADIR}/vscode

# Secrets
sudo chown -R ${PUID}:${PGID} ${SECRETSDIR}
sudo chmod 700 ${SECRETSDIR}
sudo chmod 600 ${SECRETSDIR}/*

# Config files (read-only)
sudo find ${CONFIGDIR} -type d -exec chmod 755 {} \;
sudo find ${CONFIGDIR} -type f -exec chmod 644 {} \;
sudo chown -R ${PUID}:${PGID} ${CONFIGDIR}

# Logs
sudo chown -R ${PUID}:${PGID} logs
sudo chmod 755 logs

echo "Permissions fixed!"
```

### Fix Individual Services

#### Traefik

```bash
# Fix Traefik plugin directory
sudo chown -R $(id -u):$(id -g) data/traefik/plugins-local
chmod 755 data/traefik/plugins-local

# Fix acme.json for SSL certificates
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json
sudo chown $(id -u):$(id -g) data/traefik/acme/acme.json

# Restart to apply
docker compose restart traefik
```

#### Loki

```bash
# Loki requires specific UID 10001
sudo chown -R 10001:10001 data/loki
sudo chmod 755 data/loki
docker compose restart loki
```

#### Jaeger

```bash
# Option 1: Use the provided script
./scripts/fix-jaeger-permissions.sh

# Option 2: Manual fix
mkdir -p data/jaeger/{badger,tmp}
sudo chown -R $(id -u):$(id -g) data/jaeger
chmod -R 755 data/jaeger
docker compose restart jaeger
```

#### CrowdSec

```bash
# Fix CrowdSec hub and data directories
mkdir -p data/crowdsec/{data,hub,db}
sudo chown -R $(id -u):$(id -g) data/crowdsec
sudo chmod -R 755 data/crowdsec
docker compose restart crowdsec
```

#### PostgreSQL

```bash
# Option 1: Use the provided script (recommended)
./scripts/set-postgres-permissions.sh

# Option 2: Manual fix (try UID 70 first, then 999)
sudo chown -R 70:70 data/postgres config/postgres
sudo chmod 700 data/postgres
docker compose restart postgres

# If that fails, try UID 999:
sudo chown -R 999:999 data/postgres config/postgres
docker compose restart postgres
```

#### Grafana

```bash
# Grafana uses UID 472
sudo chown -R 472:472 data/grafana
sudo chmod 755 data/grafana
docker compose restart grafana
```

#### Prometheus

```bash
# Prometheus uses nobody:nobody (65534:65534)
sudo chown -R 65534:65534 data/prometheus
sudo chmod 755 data/prometheus
docker compose restart prometheus
```

#### Secrets

```bash
# Secrets directory should be locked down
sudo chown -R $(id -u):$(id -g) secrets
sudo chmod 700 secrets
sudo chmod 600 secrets/*

# Verify
ls -la secrets/
# Should show: drwx------ (700) for directory
#             -rw------- (600) for files
```

---

## Troubleshooting Permission Issues

### Identifying Permission Problems

```bash
# Check directory ownership
ls -la data/
ls -la config/

# Check specific service directory
ls -la data/traefik/
ls -la data/loki/

# Check container user
docker exec service-name id
# Shows: uid=1000(user) gid=1000(group) or similar

# Check what user owns the directory inside container
docker exec service-name ls -la /path/to/volume

# View container logs for permission errors
docker logs service-name 2>&1 | grep -i "permission denied"
```

### Common Issues and Fixes

#### "Permission denied" in logs

```bash
# Identify the service and its required UID
# Check this table in "Permission Requirements by Service" section
# Then fix ownership:
sudo chown -R UID:GID data/service-name
```

#### "mkdir: cannot create directory"

```bash
# Directory doesn't exist or has wrong owner
mkdir -p data/service-name/subdir
sudo chown -R UID:GID data/service-name
```

#### "Operation not permitted" for chown

```bash
# Need sudo to change ownership
sudo chown -R UID:GID data/service-name
```

#### Service starts but can't write files

```bash
# Check permissions
ls -ld data/service-name
# Should show: drwxr-xr-x (755)

# Fix if needed
chmod 755 data/service-name
```

#### "acme.json" permissions too open

```bash
# Traefik requires exact 600 permissions
chmod 600 data/traefik/acme/acme.json

# Restart Traefik
docker compose restart traefik
```

### Verification After Fixes

```bash
# Check directory ownership matches requirements
ls -la data/ | grep -E "loki|jaeger|postgres|grafana"

# Expected output:
# drwxr-xr-x  loki-uid   loki-gid     data/loki
# drwxr-xr-x  1000       1000         data/jaeger
# drwx------  70         70           data/postgres
# drwxr-xr-x  472        472          data/grafana

# Check container logs for errors
docker logs service-name 2>&1 | grep -i error

# Check service is running properly
docker compose ps
# All services should show "Up" and "healthy"

# Test service functionality
docker exec service-name sh -c "touch /data/test && rm /data/test"
# Should succeed without errors
```

### When to Use sudo

You need `sudo` when:
- Changing ownership to different UID than current user
- Modifying root-owned directories
- Installing system packages

You don't need `sudo` when:
- Working with files you own
- Running Docker commands (if in docker group)
- Reading files (unless restricted)

---

## Quick Reference Commands

### Create All Directories

```bash
# Run once during setup
mkdir -p data/{traefik/{acme,plugins-local},loki,jaeger/{badger,tmp},crowdsec/{data,hub,db},prometheus,grafana,postgres,redis,alertmanager,portainer,homepage,vscode}
mkdir -p config/{traefik,loki,prometheus,grafana,crowdsec,oauth2-proxy,homepage,alertmanager}
mkdir -p secrets logs
```

### Check Permissions

```bash
# View all data directory permissions
ls -la data/

# Check specific service
ls -la data/service-name/

# Check from inside container
docker exec service-name ls -la /path/to/mount
```

### Reset Permissions (Emergency)

```bash
# CAUTION: This will reset ALL permissions
# Only use if you want to start fresh

# Stop all services
docker compose down

# Reset to default PUID:PGID
sudo chown -R $(id -u):$(id -g) data config secrets logs

# Then run specific fixes for services with different UIDs
sudo chown -R 10001:10001 data/loki
sudo chown -R 472:472 data/grafana
sudo chown -R 70:70 data/postgres config/postgres
sudo chown -R 999:999 data/redis
sudo chown -R 65534:65534 data/prometheus data/alertmanager

# Fix secrets
chmod 700 secrets
chmod 600 secrets/*

# Fix acme.json
chmod 600 data/traefik/acme/*.json

# Restart services
docker compose up -d
```

---

## Related Documentation

- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Production deployment best practices
- [Docker Security](https://docs.docker.com/engine/security/) - Docker security documentation

---

## Support

If you're still experiencing permission issues after following this guide:

1. Check service logs: `docker logs service-name`
2. Verify UID/GID: `docker exec service-name id`
3. Compare with requirements in this document
4. Ask for help: [GitHub Issues](https://github.com/jacar-javi/jacker/issues)
