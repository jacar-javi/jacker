# SSL Certificate Configuration - Let's Encrypt

## Overview

The Jacker platform uses Traefik v3 with Let's Encrypt ACME protocol to automatically obtain and renew SSL/TLS certificates for all services.

## Current Status

✅ **Staging certificates configured and working**
- All 12 services have valid Let's Encrypt staging certificates
- No rate limiting issues
- Certificates valid for 3 months

## Configuration Files

### 1. Traefik Static Configuration
**File**: `config/traefik/traefik.yml`

Contains three certificate resolvers:
- `http` - Production Let's Encrypt (HTTP-01 challenge)
- `staging` - Staging Let's Encrypt (for testing, no rate limits)
- `dns-cloudflare` - DNS challenge (commented out)

### 2. Environment Variables
**File**: `.env`

Key variables:
```bash
LETSENCRYPT_EMAIL=javi@jacar.es
LETSENCRYPT_STAGING=true  # Set to false for production certificates
```

### 3. Docker Compose Configuration
**File**: `compose/traefik.yml`

Traefik service passes environment variables to configure ACME:
```yaml
environment:
  TRAEFIK_CERTIFICATESRESOLVERS_http_ACME_EMAIL: ${LETSENCRYPT_EMAIL}
```

## Switching Between Staging and Production

### Current Limitation
The default certificate resolver is hardcoded in `config/traefik/traefik.yml`:
```yaml
entryPoints:
  websecure:
    http:
      tls:
        certresolver: staging  # Currently set to staging
```

### Manual Process to Switch to Production

**⚠️ IMPORTANT**: Only switch to production when you're confident the configuration is correct, to avoid Let's Encrypt rate limits (5 certificates per week per domain).

#### Step 1: Update Traefik Configuration
Edit `config/traefik/traefik.yml` line 70:
```yaml
certresolver: http  # Change from 'staging' to 'http'
```

#### Step 2: Update Environment Variable
Edit `.env`:
```bash
LETSENCRYPT_STAGING=false
```

#### Step 3: Reset Certificate Storage
```bash
# On VPS
cd /home/ubuntu/jacker
rm -f data/traefik/acme/acme.json
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json
```

#### Step 4: Restart Traefik
```bash
docker compose restart traefik
```

#### Step 5: Monitor Certificate Acquisition
```bash
# Watch logs for successful certificate issuance
docker compose logs traefik -f | grep -i certificate

# Check acme.json is populated
ls -lh data/traefik/acme/acme.json

# Verify certificate issuer (should be "Let's Encrypt" not "STAGING")
echo | openssl s_client -connect vps1.jacarsystems.net:443 -servername vps1.jacarsystems.net 2>/dev/null | openssl x509 -noout -issuer
```

## Rate Limits

### Let's Encrypt Production
- **5 certificates per exact set of domains per week**
- **50 certificates per registered domain per week**
- **5 failed validations per account per hour**

If rate limited, you'll see errors like:
```
error: 429 :: urn:ietf:params:acme:error:rateLimited :: too many certificates
```

### Let's Encrypt Staging
- **NO rate limits**
- Use for testing configuration changes
- Certificates show as "STAGING" in browser

## Troubleshooting

### Issue: "unable to parse email address"

**Symptom**: Traefik logs show:
```
error: invalidContact :: Error validating contact(s) :: unable to parse email address
```

**Cause**: Traefik static configuration doesn't support `${VARIABLE}` substitution

**Solution**: Use actual email address in `traefik.yml`, not environment variable placeholder:
```yaml
email: javi@jacar.es  # Not: ${LETSENCRYPT_EMAIL}
```

### Issue: Certificate acquisition fails

**Possible causes**:
1. **DNS not configured** - Ensure domain points to VPS IP
   ```bash
   dig +short vps1.jacarsystems.net
   ```

2. **Port 80 blocked** - HTTP challenge requires port 80 accessible
   ```bash
   curl -I http://vps1.jacarsystems.net
   ```

3. **Rate limited** - Switch to staging to test

4. **CAA records** - Check DNS CAA records allow Let's Encrypt
   ```bash
   dig CAA jacarsystems.net
   ```

### Issue: Browser shows "TRAEFIK DEFAULT CERT"

**Cause**: Certificate acquisition failed or pending

**Solution**:
1. Check Traefik logs for ACME errors
2. Verify DNS configuration
3. Ensure acme.json has correct permissions (600)
4. Wait a few minutes for certificate acquisition

## Services with SSL Certificates

Current deployment has certificates for:
1. vps1.jacarsystems.net (Homepage)
2. traefik.vps1.jacarsystems.net (Traefik Dashboard)
3. grafana.vps1.jacarsystems.net (Grafana)
4. prometheus.vps1.jacarsystems.net (Prometheus)
5. alertmanager.vps1.jacarsystems.net (Alertmanager)
6. portainer.vps1.jacarsystems.net (Portainer)
7. oauth.vps1.jacarsystems.net (OAuth2-Proxy)
8. code.vps1.jacarsystems.net (VS Code)
9. crowdsec.vps1.jacarsystems.net (CrowdSec)
10. redis.vps1.jacarsystems.net (Redis Commander)
11. jaeger.vps1.jacarsystems.net (Jaeger)
12. pushgateway.vps1.jacarsystems.net (Pushgateway)

## Future Improvements

### 1. Dynamic Resolver Selection
Implement environment variable-based resolver selection:
```yaml
certresolver: ${LETSENCRYPT_STAGING:+staging}${LETSENCRYPT_STAGING:-http}
```
**Status**: Not supported by Traefik static configuration

**Alternative**: Use `./jacker` CLI command to switch:
```bash
./jacker ssl staging  # Enable staging mode
./jacker ssl production  # Enable production mode
```

### 2. Wildcard Certificates
Use DNS challenge for wildcard certificates:
```yaml
dns-cloudflare:
  acme:
    email: javi@jacar.es
    storage: /acme/acme-dns.json
    dnsChallenge:
      provider: cloudflare
```

Benefits:
- Single certificate for `*.vps1.jacarsystems.net`
- No need for HTTP port 80
- Works behind firewalls

### 3. Certificate Monitoring
Add Blackbox Exporter to monitor:
- Certificate expiry dates
- Certificate validity
- Automatic renewal status

Alert before certificates expire (30 days warning).

## References

- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Traefik v3 ACME Documentation](https://doc.traefik.io/traefik/https/acme/)
- [Let's Encrypt Staging Environment](https://letsencrypt.org/docs/staging-environment/)

## Quick Commands

```bash
# Check certificate issuer
echo | openssl s_client -connect vps1.jacarsystems.net:443 -servername vps1.jacarsystems.net 2>/dev/null | openssl x509 -noout -issuer -dates

# List all obtained certificates
cat data/traefik/acme/acme-staging.json | jq -r '.staging.Certificates[].domain.main'

# Watch certificate acquisition in real-time
docker compose logs traefik -f | grep -i "certificate\|acme"

# Verify DNS configuration
for subdomain in "" traefik grafana prometheus portainer; do
  [ -z "$subdomain" ] && host="vps1.jacarsystems.net" || host="$subdomain.vps1.jacarsystems.net"
  echo "$host: $(dig +short $host)"
done
```

## Last Updated
2025-10-14 - Staging certificates successfully configured
