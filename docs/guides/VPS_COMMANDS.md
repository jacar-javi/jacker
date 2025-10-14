# VPS Validation & Fix Commands

**VPS:** vps1.jacarsystems.net
**Goal:** Validate current deployment and fix SSL if needed

---

## Quick Start: Run the Validation Script

```bash
cd /workspaces/jacker
chmod +x validation-test.sh
./validation-test.sh
```

This will check:
- ✓ Configuration files
- ✓ DNS resolution
- ✓ Port accessibility
- ✓ acme.json status
- ✓ SSL certificates
- ✓ Service accessibility

---

## Manual Validation (Step by Step)

### 1. Check DNS Configuration

```bash
# Load your configuration
cd /workspaces/jacker
source .env

# Check DNS resolution
echo "Checking DNS for ${PUBLIC_FQDN}..."
host "${PUBLIC_FQDN}"

# Should show your VPS IP address
# If it doesn't, SSL will NOT work
```

### 2. Check Ports

```bash
# Check if ports 80 and 443 are listening
sudo netstat -tuln | grep -E ':80 |:443 '

# Should show both ports listening
```

### 3. Check SSL Certificate Status

```bash
# Check acme.json file
ls -lh data/traefik/acme/acme.json

# Check size (should be > 100 bytes if certificates issued)
stat -c "%s" data/traefik/acme/acme.json

# View acme.json content
cat data/traefik/acme/acme.json | jq .
```

### 4. Check Traefik Logs

```bash
# Check for ACME activity
./jacker logs traefik --tail=100 | grep -i acme

# Look for:
# ✓ "certificate obtained" = GOOD
# ✗ "acme: error" = BAD
# ✗ "Unable to obtain" = BAD

# Check for default certificate warning
./jacker logs traefik --tail=100 | grep -i "TRAEFIK DEFAULT CERT"
# If found = SSL NOT working
```

### 5. Test SSL Certificate

```bash
# Check what certificate is being served
echo | openssl s_client -servername "${PUBLIC_FQDN}" -connect "${PUBLIC_FQDN}:443" 2>/dev/null | openssl x509 -noout -issuer

# Should show:
# issuer=C = US, O = Let's Encrypt, CN = R3

# If shows "TRAEFIK DEFAULT CERT" = SSL NOT working
```

### 6. Test Service Access

```bash
# Try accessing your services
curl -I "https://homepage.${DOMAINNAME}"
curl -I "https://traefik.${DOMAINNAME}"

# Look for:
# HTTP/2 200 = Working!
# HTTP/2 401/403 = Auth required (service is working)
```

---

## Fix: If SSL Not Working

### Option A: Quick Reset (Recommended)

```bash
cd /workspaces/jacker

# Stop services
./jacker stop

# Backup current acme.json (if it exists)
cp data/traefik/acme/acme.json data/traefik/acme/acme.json.bak 2>/dev/null || true

# Remove corrupted acme.json
rm -f data/traefik/acme/acme.json

# Recreate with correct permissions
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json

# Verify traefik.yml has your email
grep "email:" config/traefik/traefik.yml

# Start services
./jacker start

# Monitor certificate acquisition (wait 30-60 seconds)
./jacker logs traefik -f | grep -i acme
```

**What to look for in logs:**
```
✓ "Trying to solve HTTP-01"
✓ "The server validated our request"
✓ "certificate obtained for [vps1.jacarsystems.net]"
```

### Option B: Restart Just Traefik

```bash
# Restart Traefik only
./jacker restart traefik

# Monitor logs
./jacker logs traefik -f --tail=50

# Wait 30-60 seconds for certificate acquisition
```

### Option C: Full Restart

```bash
# Stop everything
./jacker stop

# Start everything
./jacker start

# Monitor
./jacker logs traefik -f | grep -i acme
```

---

## Verify Fix Worked

After restarting, wait 30-60 seconds then check:

```bash
# 1. Check acme.json size
stat -c "%s" data/traefik/acme/acme.json
# Should be > 100 bytes

# 2. Check logs for success
./jacker logs traefik --tail=50 | grep "certificate obtained"

# 3. Test SSL certificate
echo | openssl s_client -servername vps1.jacarsystems.net -connect vps1.jacarsystems.net:443 2>/dev/null | openssl x509 -noout -issuer
# Should show: issuer=...Let's Encrypt...

# 4. Access your services
curl -I https://homepage.jacarsystems.net
curl -I https://traefik.jacarsystems.net
```

---

## Troubleshooting

### Problem: "Unable to obtain ACME certificate"

**Cause:** DNS not resolving or port 80 not accessible

**Check:**
```bash
# Verify DNS from external source
host vps1.jacarsystems.net

# Check firewall
sudo ufw status
sudo iptables -L -n | grep -E "80|443"

# Test port 80 from another machine
# curl -v http://vps1.jacarsystems.net
```

### Problem: "acme: error: 429" (Rate Limited)

**Cause:** Too many certificate requests

**Fix:** Wait 1 hour before trying again, or use staging server temporarily

### Problem: Services still show TRAEFIK DEFAULT CERT

**Fix:**
```bash
# Check if Traefik is using old cached cert
./jacker stop traefik
rm -rf data/traefik/acme/*
touch data/traefik/acme/acme.json
chmod 600 data/traefik/acme/acme.json
./jacker start traefik
```

### Problem: OAuth redirect errors after SSL fixed

**Fix:**
```bash
# Restart OAuth2-Proxy
./jacker restart oauth
```

---

## Monitoring Commands

```bash
# View all Traefik logs
./jacker logs traefik -f

# View only ACME-related logs
./jacker logs traefik -f | grep -i acme

# View all service status
./jacker status

# Check if services are healthy
docker compose ps
```

---

## Expected Timeline

After running fix commands:

- **0-10 seconds:** Traefik starts, detects missing certificates
- **10-30 seconds:** ACME challenge initiated
- **30-60 seconds:** Certificate obtained from Let's Encrypt
- **60+ seconds:** Services accessible with valid SSL

If no success after 2 minutes, check logs for errors.

---

## Success Checklist

✅ acme.json file > 100 bytes
✅ Traefik logs show "certificate obtained"
✅ No "TRAEFIK DEFAULT CERT" in logs
✅ `openssl s_client` shows Let's Encrypt issuer
✅ Services accessible via HTTPS without errors
✅ No certificate warnings in browser

---

## Getting Help

If validation script shows failures:

1. Check DNS is configured correctly
2. Verify ports 80/443 are open
3. Check Traefik logs for specific errors
4. Try the Quick Reset fix above

For detailed analysis, see: `INIT_ANALYSIS.md`
