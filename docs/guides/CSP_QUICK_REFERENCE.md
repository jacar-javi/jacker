# CSP Quick Reference Card

## TL;DR - What You Need to Know

### What Changed?
- ✅ **Removed `'unsafe-inline'` from script-src** (XSS protection)
- ✅ **Removed `'unsafe-eval'` from script-src** (Code injection protection)
- ⚠️  **Kept `'unsafe-inline'` for style-src** (Low risk, common pattern)

### Three Security Levels

| Level | Middleware | Use For | Security |
|-------|-----------|---------|----------|
| **STRICT** | `secure-headers-strict` | APIs, modern SPAs | 🔒🔒🔒 Maximum |
| **DEFAULT** | `secure-headers` | Most web apps | 🔒🔒 High |
| **RELAXED** | `secure-headers-relaxed` | Grafana, Homepage | 🔒 Moderate |

---

## Quick Middleware Chain Selection

### For Most Services (Recommended)
```yaml
traefik.http.routers.myservice.middlewares=chain-oauth@file
```
**Now uses hardened CSP (no unsafe-inline/unsafe-eval in scripts)**

### For Grafana, Homepage (Inline Scripts Required)
```yaml
traefik.http.routers.myservice.middlewares=chain-oauth-relaxed@file
```

### For Maximum Security (APIs, Static Sites)
```yaml
traefik.http.routers.myservice.middlewares=chain-oauth-strict@file
```

---

## Available Chains

### OAuth-Protected Chains
```yaml
chain-oauth@file              # Default: Hardened CSP, OAuth auth
chain-oauth-relaxed@file      # Relaxed: For Grafana, Homepage
chain-oauth-strict@file       # Strict: For maximum security
```

### Public Chains (No Auth)
```yaml
chain-public@file             # Default: Hardened CSP, public access
chain-public-relaxed@file     # Relaxed: For legacy apps
chain-public-strict@file      # Strict: For static sites
```

### API Chains
```yaml
chain-api@file                # Default: Hardened CSP, API config
chain-api-strict@file         # Strict: Maximum security
```

---

## CSP Directives Comparison

### Strict CSP
```yaml
script-src 'self' https://cdn.jsdelivr.net https://unpkg.com;
style-src 'self' https://fonts.googleapis.com https://cdn.jsdelivr.net;
```
- ✅ No unsafe directives at all
- ✅ Maximum XSS protection

### Default CSP (Hardened)
```yaml
script-src 'self' https://cdn.jsdelivr.net https://unpkg.com;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net;
```
- ✅ No unsafe-inline/unsafe-eval for scripts
- ⚠️  unsafe-inline allowed for CSS only

### Relaxed CSP (Legacy)
```yaml
script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://unpkg.com;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net;
```
- ⚠️  Includes unsafe-inline and unsafe-eval
- ⚠️  Use only when necessary

---

## Common Service Configurations

### Grafana
```yaml
labels:
  - "traefik.http.routers.grafana.middlewares=chain-oauth-relaxed@file"
```
**Reason:** Uses eval() for dashboard rendering

### Homepage
```yaml
labels:
  - "traefik.http.routers.homepage.middlewares=chain-oauth-relaxed@file"
```
**Reason:** Uses inline scripts for widgets

### Prometheus / Alertmanager
```yaml
labels:
  - "traefik.http.routers.prometheus.middlewares=chain-oauth@file"
```
**Reason:** Works with default hardened CSP

### Custom React/Vue/Angular App
```yaml
labels:
  - "traefik.http.routers.myapp.middlewares=chain-oauth-strict@file"
```
**Reason:** Modern frameworks use bundled JS

### REST API
```yaml
labels:
  - "traefik.http.routers.api.middlewares=chain-api-strict@file"
```
**Reason:** APIs don't serve HTML

---

## Troubleshooting

### Service Not Loading?

1. **Open browser DevTools (F12)**
2. **Check Console for CSP violations**
3. **Fix:**

```yaml
# Temporary: Use relaxed CSP
traefik.http.routers.myservice.middlewares=chain-oauth-relaxed@file

# Long-term: Refactor app to comply with strict CSP
```

### Common CSP Violations

#### Inline Script Blocked
```
Refused to execute inline script because it violates CSP directive "script-src 'self'"
```

**Quick Fix:**
```yaml
# Switch to relaxed CSP temporarily
middlewares=chain-oauth-relaxed@file
```

**Better Fix:** Move script to external file
```html
<!-- Before -->
<script>
  function myFunction() { }
</script>

<!-- After -->
<script src="/js/myFunction.js"></script>
```

#### eval() Blocked
```
Refused to evaluate a string as JavaScript because 'unsafe-eval' is not allowed
```

**Quick Fix:**
```yaml
# Switch to relaxed CSP temporarily
middlewares=chain-oauth-relaxed@file
```

**Better Fix:** Replace eval()
```javascript
// Before
const result = eval(userInput);

// After
const result = JSON.parse(userInput);
```

---

## Testing Commands

### Restart Traefik
```bash
docker compose restart traefik
```

### Check Traefik Logs
```bash
docker compose logs -f traefik
```

### Test Service
```bash
# Check HTTP headers
curl -I https://myservice.example.com

# Look for Content-Security-Policy header
```

---

## CSP Testing Tools

- **Browser Console:** F12 → Console tab (look for CSP violations)
- **CSP Evaluator:** https://csp-evaluator.withgoogle.com/
- **Mozilla Observatory:** https://observatory.mozilla.org/
- **Security Headers:** https://securityheaders.com/

---

## Decision Tree

```
Need to add a service?
│
├─ Is it a REST API with no HTML?
│  └─ Use: chain-api-strict@file
│
├─ Is it a modern SPA (React/Vue/Angular)?
│  └─ Use: chain-oauth-strict@file
│
├─ Is it Grafana or Homepage?
│  └─ Use: chain-oauth-relaxed@file
│
├─ Is it a legacy app with inline scripts?
│  └─ Use: chain-oauth-relaxed@file
│
└─ Not sure?
   └─ Use: chain-oauth@file (default, hardened)
      └─ If broken: Switch to chain-oauth-relaxed@file
      └─ If works: Consider upgrading to chain-oauth-strict@file
```

---

## Full Documentation

For comprehensive documentation, see:
- **Implementation Guide:** `/workspaces/jacker/docs/guides/CSP_IMPLEMENTATION_GUIDE.md`
- **Hardening Summary:** `/workspaces/jacker/docs/CSP_HARDENING_SUMMARY.md`

---

**Last Updated:** 2025-10-16
**Version:** 1.0
