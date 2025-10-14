# Jacker Platform Architecture Overview

**Last Updated:** 2025-10-14
**Version:** 1.0.0

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Network Topology](#network-topology)
3. [Service Dependency Graph](#service-dependency-graph)
4. [Monitoring Coverage Map](#monitoring-coverage-map)
5. [Security Layers](#security-layers)
6. [Data Flow](#data-flow)
7. [Deployment Architecture](#deployment-architecture)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Internet / External                         │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   Ports 80/443  │
                    │   Traefik v3    │
                    │  Reverse Proxy  │
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
     ┌──────▼──────┐  ┌─────▼─────┐  ┌──────▼──────┐
     │  CrowdSec   │  │  OAuth2/  │  │ Applications│
     │   IPS/IDS   │  │ Authentik │  │  & Services │
     └──────┬──────┘  └─────┬─────┘  └──────┬──────┘
            │                │                │
            └────────────────┼────────────────┘
                             │
            ┌────────────────┴────────────────┐
            │                                 │
     ┌──────▼──────┐              ┌──────────▼─────────┐
     │  Monitoring │              │   Data Storage     │
     │   Stack     │              │  PostgreSQL/Redis  │
     │ Prometheus  │              └────────────────────┘
     │  Grafana    │
     │   Loki      │
     └─────────────┘
```

### Service Layers

#### Layer 1: Edge / Ingress
- **Traefik v3**: Entry point for all HTTP/HTTPS traffic
- **CrowdSec**: Real-time threat detection and IP blocking
- **Traefik Bouncer**: Integrates CrowdSec decisions with Traefik

#### Layer 2: Authentication
- **OAuth2-Proxy**: Google OAuth authentication (default)
- **Authentik**: Self-hosted identity provider (optional)
- **Authentik PostgreSQL**: Dedicated database for Authentik
- **Redis**: Session storage for OAuth

#### Layer 3: Application Services
- **Homepage**: Unified dashboard
- **Portainer**: Docker management UI
- **VS Code Server**: Browser-based IDE
- **Redis Commander**: Redis management UI

#### Layer 4: Monitoring & Observability
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Promtail**: Log collection agent
- **Alertmanager**: Alert routing and notifications (HA setup)
- **Jaeger**: Distributed tracing
- **Blackbox Exporter**: Endpoint and SSL monitoring
- **cAdvisor**: Container metrics
- **Node Exporter**: System metrics
- **Postgres Exporter**: Database metrics
- **Redis Exporter**: Cache metrics
- **Pushgateway**: Batch job metrics

#### Layer 5: Data Storage
- **PostgreSQL**: Main relational database
- **Redis**: Main cache and session store
- **Authentik PostgreSQL**: Identity provider database

#### Layer 6: Infrastructure
- **Socket Proxy**: Secure Docker socket access

---

## Network Topology

Jacker uses **7 isolated Docker networks** with predictable IPAM configurations for security and organization.

### Network Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│                   default (192.168.69.0/24)                         │
│  Gateway: 192.168.69.1                                              │
│  Services: General application containers                           │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│               socket_proxy (192.168.70.0/24)                        │
│  Gateway: 192.168.70.1                                              │
│  Services: Socket Proxy (isolated Docker socket access)             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│              traefik_proxy (192.168.71.0/24)                        │
│  Gateway: 192.168.71.1                                              │
│  Services: Traefik, OAuth2-Proxy, Authentik, CrowdSec, Apps         │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                 database (192.168.72.0/24)                          │
│  Gateway: 192.168.72.1                                              │
│  Services: PostgreSQL, Authentik PostgreSQL, Postgres Exporter      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                monitoring (192.168.73.0/24)                         │
│  Gateway: 192.168.73.1                                              │
│  Services: Prometheus, Grafana, Loki, Alertmanager, Exporters       │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                   cache (192.168.74.0/24)                           │
│  Gateway: 192.168.74.1                                              │
│  Services: Redis, Redis Commander, Redis Exporter                   │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                  backup (192.168.75.0/24)                           │
│  Gateway: 192.168.75.1                                              │
│  Services: Backup utilities and data synchronization                │
└─────────────────────────────────────────────────────────────────────┘
```

### Network Membership Matrix

| Service | default | socket_proxy | traefik_proxy | database | monitoring | cache | backup |
|---------|---------|--------------|---------------|----------|------------|-------|--------|
| Traefik | ✓ | ✓ | ✓ | | | | |
| OAuth2-Proxy | | | ✓ | | | ✓ | |
| Authentik Server | | | ✓ | ✓ | | ✓ | |
| Authentik Worker | | | | ✓ | | ✓ | |
| CrowdSec | | | ✓ | | | | |
| PostgreSQL | | | | ✓ | | | |
| Redis | | | | | | ✓ | |
| Prometheus | | | | | ✓ | | |
| Grafana | | | ✓ | | ✓ | | |
| Loki | | | | | ✓ | | |
| Promtail | | | | | ✓ | | |
| Alertmanager | | | | | ✓ | | |
| Node Exporter | | | | | ✓ | | |
| Blackbox Exporter | | | ✓ | | ✓ | | |
| cAdvisor | | ✓ | | | ✓ | | |
| Jaeger | | | ✓ | | ✓ | | |
| Homepage | | | ✓ | | | | |
| Portainer | | ✓ | ✓ | | | | |
| Socket Proxy | | ✓ | | | | | |

---

## Service Dependency Graph

### Critical Dependencies

```
PostgreSQL
  ├── Authentik Server
  ├── Authentik Worker
  └── Postgres Exporter

Redis (Main)
  ├── OAuth2-Proxy (session storage)
  ├── Authentik Server (cache)
  ├── Authentik Worker (cache)
  └── Redis Exporter

Authentik PostgreSQL
  ├── Authentik Server
  └── Authentik Worker

Traefik
  ├── All web-accessible services
  └── CrowdSec Bouncer

Socket Proxy
  ├── Traefik (Docker API access)
  ├── cAdvisor (container stats)
  └── Portainer (container management)

Prometheus
  ├── Grafana (data source)
  ├── Alertmanager (query evaluation)
  └── All Exporters (metrics scraping)

Loki
  ├── Grafana (log visualization)
  └── Promtail (log ingestion)
```

### Startup Order

1. **Databases**: PostgreSQL, Authentik PostgreSQL, Redis
2. **Infrastructure**: Socket Proxy
3. **Edge**: Traefik, CrowdSec
4. **Authentication**: OAuth2-Proxy, Authentik
5. **Monitoring Foundation**: Prometheus, Loki
6. **Exporters**: Node Exporter, cAdvisor, Blackbox, DB Exporters
7. **Visualization**: Grafana, Jaeger
8. **Applications**: Homepage, Portainer, VS Code Server
9. **Alerting**: Alertmanager, Promtail

---

## Monitoring Coverage Map

**Total Services:** 26
**Monitored Services:** 25 (96% coverage)
**Unmonitored:** 1 (alertmanager-secondary - intentional HA backup)

### Monitoring Matrix

| Service | Metrics | Logs | Traces | Health Checks |
|---------|---------|------|--------|---------------|
| **Traefik** | ✓ | ✓ | ✓ | ✓ |
| **OAuth2-Proxy** | ✓ | ✓ | | ✓ |
| **Authentik Server** | ✓ | ✓ | | ✓ |
| **Authentik Worker** | ✓ | ✓ | | ✓ |
| **CrowdSec** | ✓ | ✓ | | ✓ |
| **PostgreSQL** | ✓ | ✓ | | ✓ |
| **Redis** | ✓ | ✓ | | ✓ |
| **Prometheus** | ✓ | ✓ | | ✓ |
| **Grafana** | ✓ | ✓ | | ✓ |
| **Loki** | ✓ | ✓ | | ✓ |
| **Promtail** | ✓ | ✓ | | ✓ |
| **Alertmanager** | ✓ | ✓ | | ✓ |
| **Node Exporter** | ✓ | ✓ | | ✓ |
| **Blackbox Exporter** | ✓ | ✓ | | ✓ |
| **cAdvisor** | ✓ | ✓ | | ✓ |
| **Jaeger** | ✓ | ✓ | ✓ | ✓ |
| **Postgres Exporter** | ✓ | ✓ | | ✓ |
| **Redis Exporter** | ✓ | ✓ | | ✓ |
| **Pushgateway** | ✓ | ✓ | | ✓ |
| **Homepage** | ✓ | ✓ | | ✓ |
| **Portainer** | ✓ | ✓ | | ✓ |
| **VS Code Server** | ✓ | ✓ | | ✓ |
| **Redis Commander** | ✓ | ✓ | | ✓ |
| **Socket Proxy** | ✓ | ✓ | | ✓ |
| **Authentik PostgreSQL** | ✓ | ✓ | | ✓ |
| **Alertmanager Secondary** | | | | ✓ |

### Metrics Sources

- **Application Metrics**: Direct `/metrics` endpoints (Prometheus format)
- **Container Metrics**: cAdvisor (CPU, memory, network, filesystem)
- **System Metrics**: Node Exporter (host-level metrics)
- **Endpoint Health**: Blackbox Exporter (HTTPS probes, SSL expiry)
- **Database Metrics**: Postgres Exporter, Redis Exporter
- **Trace Data**: Jaeger (OpenTelemetry compatible)

---

## Security Layers

Jacker implements defense-in-depth with multiple security layers:

### Layer 1: Network Perimeter

```
Internet → Firewall (ufw) → Ports 80/443 → Traefik
```

- UFW firewall blocks all ports except 80, 443, 22
- Fail2ban monitors SSH access
- CrowdSec analyzes all HTTP traffic

### Layer 2: Reverse Proxy & IPS

```
Traefik → CrowdSec Bouncer → IP Decision (Allow/Block)
```

- **Traefik**: TLS termination, automatic SSL certificates
- **CrowdSec**: Real-time threat detection, community blocklists
- **Bouncer**: Enforces CrowdSec decisions at edge

### Layer 3: Authentication

```
Request → OAuth2-Proxy → Email Domain Validation → Service
```

- **OAuth2-Proxy**: Google OAuth integration
  - Email domain restriction enforced
  - Session cookies (encrypted, httpOnly)
- **Authentik** (optional): Self-hosted IdP
  - MFA support
  - SSO/SAML integration
  - User/group management

### Layer 4: Application Security

- **Traefik Middlewares**:
  - `secure-headers`: Security headers (CSP, HSTS, X-Frame-Options)
  - `rate-limit`: Rate limiting (50 req/s default)
  - `compress`: Response compression
  - `cors`: CORS policy enforcement

- **Service Isolation**:
  - Network segmentation (7 isolated networks)
  - Least privilege network access
  - No direct database access from internet

### Layer 5: Data Security

- **Secrets Management**:
  - Docker secrets for sensitive data
  - File permissions: 600 (secrets), 700 (secrets dir)
  - No secrets in environment variables
  - OAuth credentials in separate files

- **Database Security**:
  - PostgreSQL on isolated network
  - No external exposure
  - Access via exporters only

### Layer 6: Container Security

- **Socket Proxy**:
  - Restricted Docker API access
  - Read-only socket mount
  - Filters allowed API endpoints

- **User Mapping**:
  - Services run as non-root (PUID/PGID)
  - Loki: UID 10001
  - Jaeger: UID 10001

---

## Data Flow

### Request Flow (Web Access)

```
1. User Browser
   ↓ HTTPS (443)
2. Traefik (TLS termination)
   ↓
3. CrowdSec Bouncer (IP validation)
   ↓
4. OAuth2-Proxy (authentication)
   ↓ (if authenticated)
5. Middleware Chain
   - Secure Headers
   - Rate Limiting
   - Compression
   ↓
6. Backend Service (Homepage, Grafana, etc.)
   ↓
7. Response (compressed, headers added)
   ↑
8. User Browser (HTML/JSON)
```

### Metrics Flow

```
1. Service exposes /metrics endpoint
   ↓
2. Prometheus scrapes metrics (15s interval)
   ↓
3. Prometheus stores time-series data
   ↓
4. Grafana queries Prometheus
   ↓
5. User views dashboard
```

### Log Flow

```
1. Container writes to stdout/stderr
   ↓
2. Docker captures container logs
   ↓
3. Promtail reads Docker logs
   ↓
4. Promtail sends to Loki
   ↓
5. Loki indexes and stores logs
   ↓
6. Grafana queries Loki
   ↓
7. User searches logs in Grafana
```

### Trace Flow

```
1. Application creates spans (OpenTelemetry)
   ↓
2. Spans sent to Jaeger collector
   ↓
3. Jaeger stores traces
   ↓
4. User queries traces in Jaeger UI
```

---

## Deployment Architecture

### File Structure

```
jacker/
├── docker-compose.yml          # Main compose file with includes
├── .env                        # Environment configuration
├── validate.sh                 # Pre-deployment validation
├── jacker                      # Unified CLI
│
├── compose/                    # Modular service definitions
│   ├── traefik.yml
│   ├── oauth.yml
│   ├── prometheus.yml
│   └── ... (23 more)
│
├── config/                     # Service configurations
│   ├── traefik/
│   ├── prometheus/
│   ├── grafana/
│   └── ...
│
├── data/                       # Persistent data
│   ├── traefik/acme/
│   ├── postgres/
│   ├── grafana/
│   └── ...
│
├── secrets/                    # Docker secrets
│   ├── oauth-client-id
│   ├── oauth-client-secret
│   └── ...
│
└── assets/                     # Scripts and libraries
    ├── lib/                    # Shell script libraries
    └── templates/              # Configuration templates
```

### Configuration Management

1. **Environment Variables**: `.env` file (600 permissions)
2. **Docker Secrets**: `secrets/` directory (700 permissions)
3. **Service Configs**: `config/` directory templates
4. **Validation**: `validate.sh` checks before deployment

### Deployment Process

```
1. DNS Configuration
   └── A records for domain and wildcard

2. Pre-Deployment Validation
   └── ./validate.sh (12 checks)

3. Init Script
   ├── DNS validation
   ├── Directory creation
   ├── Configuration generation
   ├── Docker installation
   ├── Service startup
   └── SSL certificate wait

4. Post-Deployment Verification
   ├── Service health checks
   ├── SSL certificate validation
   ├── Monitoring target verification
   └── OAuth functionality test
```

---

## Scalability & High Availability

### Current HA Features

1. **Alertmanager**: Dual instance (primary + secondary)
2. **Database Backups**: Automated via `jacker backup`
3. **Multi-source Public IP**: Fallback IP detection
4. **Health Checks**: All services have health endpoints

### Future Scalability Options

1. **PostgreSQL**: Could add read replicas or Patroni cluster
2. **Redis**: Could add Redis Sentinel or Redis Cluster
3. **Prometheus**: Could implement federation or Thanos
4. **Loki**: Could add S3 backend for distributed storage
5. **Traefik**: Multiple instances with shared storage (acme.json on NFS)

---

## Performance Characteristics

### Resource Requirements

| Component | CPU | Memory | Disk |
|-----------|-----|--------|------|
| Traefik | 0.1 | 128MB | 1GB |
| Prometheus | 0.5 | 1.5-2GB | 20GB |
| Grafana | 0.2 | 512MB | 2GB |
| Loki | 0.3 | 512MB | 10GB |
| PostgreSQL | 0.3 | 512MB | 5GB |
| All Others | 0.6 | 2GB | 5GB |
| **Total** | **2-3 cores** | **5-6GB** | **40GB+** |

### Recommended Hardware

- **Minimum**: 2 CPU cores, 4GB RAM, 40GB disk
- **Recommended**: 4 CPU cores, 8GB RAM, 100GB SSD
- **Optimal**: 8 CPU cores, 16GB RAM, 200GB NVMe SSD

---

## Documentation References

- **Installation**: `/README.md`
- **Services**: `/compose/README.md`
- **Phase Reports**: `/docs/archive/`
- **Configuration**: `/config/*/README.md`
- **Changelog**: `/CHANGELOG.md`

---

**Version History:**
- 1.0.0 (2025-10-14): Initial architecture documentation
