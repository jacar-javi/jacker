# Security Policy

## Supported Versions

We actively maintain and provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 3.x.x   | :white_check_mark: |
| main    | :white_check_mark: |
| develop | :white_check_mark: |
| < 3.0   | :x:                |

Version 3.0.0 introduced the unified Jacker CLI. The `main` branch represents the latest stable release, while `develop` contains features under active development.

## Reporting a Vulnerability

We take security seriously and appreciate responsible disclosure of vulnerabilities.

### How to Report

**DO NOT** open public GitHub issues for security vulnerabilities.

Instead, please report security issues via email to:

**security@jacker.jacar.es**

Include the following information:

1. **Description** of the vulnerability
2. **Steps to reproduce** the issue
3. **Potential impact** and severity assessment
4. **Affected versions** (if known)
5. **Suggested fix** (if available)
6. **Your contact information** for follow-up

### Response Timeline

- **Initial Response**: Within 48 hours
- **Status Update**: Within 7 days
- **Fix Timeline**: Depends on severity
  - Critical: 24-72 hours
  - High: 7-14 days
  - Medium: 30 days
  - Low: Best effort

### Disclosure Policy

We follow responsible disclosure practices:

1. We acknowledge receipt of your report within 48 hours
2. We investigate and confirm the vulnerability
3. We develop and test a fix
4. We release a security update
5. We publicly disclose the issue after the fix is deployed (with credit to reporter, if desired)

## Security Features

Jacker includes multiple security layers:

### Network Security

- **Traefik v3** - Secure reverse proxy with automatic HTTPS
- **Let's Encrypt** - Free SSL/TLS certificates with auto-renewal
- **HTTP to HTTPS** - Automatic redirection
- **Security Headers** - HSTS, CSP, X-Frame-Options, etc.

### Access Control

- **OAuth2 Authentication** - Google OAuth or self-hosted Authentik
- **Forward Authentication** - Middleware-based access control
- **IP Whitelisting** - Restrict access by IP ranges
- **Traefik Middleware** - Configurable authentication chains

### Intrusion Prevention

- **CrowdSec IPS/IDS** - Collaborative security with real-time threat intelligence
- **Community Blocklists** - Automatic blocking of known malicious IPs
- **Traefik Bouncer** - Real-time IP blocking at proxy level
- **PostgreSQL Backend** - Persistent threat database

### Container Security

- **Socket Proxy** - Restricted Docker socket access
- **Read-Only Filesystems** - Where applicable
- **No New Privileges** - Security option for containers
- **User Namespaces** - Non-root container execution (recommended)
- **Health Checks** - Monitor container health status

### System Security

- **UFW Firewall** - Host-level firewall configuration
- **Fail2Ban Integration** - SSH brute-force protection
- **System Hardening** - Sysctl optimizations and kernel parameters
- **Log Monitoring** - Loki aggregation with alerting

### Secrets Management

- **Environment Variables** - Configuration via `.env` file
- **Docker Secrets** - Sensitive credentials (where supported)
- **File Permissions** - Strict permissions on config files (600)
- **No Hardcoded Secrets** - All secrets externalized

## Security Best Practices

### Installation

1. **Review `.env` file** - Ensure strong passwords and secrets
2. **Configure OAuth** - Set up authentication before exposing to internet
3. **Enable UFW** - Configure firewall rules
4. **Update system** - Keep OS and packages up to date
5. **Secure SSH** - Use key-based authentication, disable root login

### Operation

1. **Regular Updates** - Run `./jacker update` to pull latest images
2. **Monitor Logs** - Check Grafana dashboards regularly
3. **Review Alerts** - Configure Alertmanager notifications
4. **Backup Regularly** - Run `./jacker backup` before major changes
5. **Audit Access** - Review OAuth whitelist and authentication logs

### Network Configuration

1. **Use Real Domain** - Don't expose `example.com` to internet
2. **Configure DNS Properly** - Ensure A/AAAA records point to server
3. **Enable HTTPS** - Set valid `LETSENCRYPT_EMAIL`
4. **Restrict SSH** - Use `UFW_ALLOW_SSH` to limit SSH access
5. **Whitelist IPs** - Use `LOCAL_IPS` for sensitive services

### OAuth Security

**WARNING: TEST CREDENTIALS DETECTED**

The repository contains test OAuth credentials in both `.env` and `secrets/oauth_client_secret`. These are **ONLY for development/testing** and must be replaced before production deployment.

#### Required Actions Before Production:

1. **Generate Production OAuth Credentials from Google Console**:
   - Visit https://console.cloud.google.com/apis/credentials
   - Create or select your project
   - Create new OAuth 2.0 Client ID (Web application)
   - Add authorized redirect URIs:
     - `https://oauth.yourdomain.com/oauth2/callback`
     - `https://yourdomain.com/oauth2/callback`
   - Copy the Client ID and Client Secret

2. **Update Credentials**:
   ```bash
   # Update .env file
   OAUTH_CLIENT_ID=your-production-client-id.apps.googleusercontent.com
   OAUTH_CLIENT_SECRET=your-production-client-secret

   # Update secrets file
   echo "your-production-client-secret" > secrets/oauth_client_secret
   chmod 600 secrets/oauth_client_secret
   ```

3. **Security Best Practices**:
   - **Whitelist Users** - Configure `OAUTH_WHITELIST` with specific emails
   - **Rotate Secrets** - Periodically rotate OAuth credentials
   - **Use Strong Secrets** - Generate secure `OAUTH_SECRET` and `OAUTH_COOKIE_SECRET`
   - **Review Sessions** - Monitor active sessions via Redis
   - **Emergency Access** - Keep emergency access procedure documented

### CrowdSec

1. **Enroll in Console** - Register at https://app.crowdsec.net
2. **Enable Bouncers** - Configure Traefik and iptables bouncers
3. **Review Decisions** - Check blocked IPs regularly
4. **Update Scenarios** - Keep CrowdSec scenarios up to date
5. **Share Signals** - Contribute to community intelligence

## Known Security Considerations

### Docker Socket Access

The Socket Proxy container has access to the Docker socket. This is necessary for Traefik's Docker provider but is restricted using Tecnativa's socket-proxy with minimal permissions.

### OAuth Bypass

Emergency OAuth bypass is available for development environments only. **Never disable OAuth in production**. To temporarily disable for testing:
```bash
./jacker config oauth disable
```

Re-enable immediately after testing:
```bash
./jacker config oauth enable
```

### Default Credentials

The setup process generates strong random passwords for all services. To rotate secrets:
```bash
./jacker secrets rotate
```

### Network Exposure

By default, most services are accessible via Traefik with OAuth authentication. Review `data/traefik/rules/middlewares-*.yml` to ensure proper protection.

## Security Audit

The project undergoes:

- **Automated Scanning**: Trivy security scans via GitHub Actions
- **Secret Detection**: Automated checks for hardcoded credentials
- **Dependency Updates**: Dependabot for Docker image updates
- **Community Review**: Open-source transparency

## Compliance

Jacker helps with:

- **Encryption in Transit**: HTTPS/TLS for all external connections
- **Access Controls**: Authentication and authorization
- **Audit Logging**: Comprehensive logging via Loki
- **Intrusion Detection**: CrowdSec IPS/IDS

Note: Users are responsible for compliance with applicable regulations (GDPR, HIPAA, etc.) in their specific deployment context.

## Security Updates

Subscribe to security announcements:

- **GitHub Security Advisories**: Watch the repository
- **Release Notes**: Check for security fixes in releases
- **Email Notifications**: Contact us to join security mailing list

## Contact

For security concerns:

- **Email**: security@jacker.jacar.es
- **PGP Key**: Available upon request
- **Response Time**: Within 48 hours

## Acknowledgments

We thank security researchers who responsibly disclose vulnerabilities. Contributors will be credited (with permission) in:

- Security advisories
- Release notes
- Project security acknowledgments

---

**Last Updated**: 2025-10-12
**Jacker Version**: 3.0.0 (Unified CLI)

**Security is a shared responsibility**. This document outlines our commitment to security, but proper configuration and operational security depend on deployment-specific factors. Always review and customize security settings for your environment.
