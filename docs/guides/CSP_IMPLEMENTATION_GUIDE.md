# Content Security Policy (CSP) Implementation Guide

## Overview

This guide explains the CSP hardening implemented in the Jacker infrastructure and provides guidance on implementing secure CSP policies for your services.

## What Changed?

### Before (INSECURE)
```yaml
contentSecurityPolicy: |
  script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net;
```

### After (SECURE - Default)
```yaml
contentSecurityPolicy: |
  script-src 'self' https://cdn.jsdelivr.net https://unpkg.com;
  style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
```

**Key Improvements:**
- ✅ **Removed `'unsafe-inline'` from script-src** - Prevents XSS via inline scripts
- ✅ **Removed `'unsafe-eval'` from script-src** - Prevents code injection via eval()
- ⚠️  **Kept `'unsafe-inline'` for style-src only** - Common pattern, lower security risk

---

## CSP Security Levels

We now provide three CSP middleware profiles to balance security with compatibility:

### 1. `secure-headers-strict` - Maximum Security
**Use for:** APIs, static sites, modern SPAs with bundled JavaScript

**CSP Configuration:**
```yaml
script-src 'self' https://cdn.jsdelivr.net https://unpkg.com;
style-src 'self' https://fonts.googleapis.com https://cdn.jsdelivr.net;
```

**NO unsafe directives at all** - Maximum XSS protection

**Compatible with:**
- REST APIs
- Static websites
- React/Vue/Angular apps with bundled JS
- Services with no inline scripts

**NOT compatible with:**
- Legacy admin panels (Grafana, Portainer)
- Services using inline scripts
- Applications using eval() or new Function()

### 2. `secure-headers` (Default) - Balanced Security
**Use for:** Most modern web applications

**CSP Configuration:**
```yaml
script-src 'self' https://cdn.jsdelivr.net https://unpkg.com;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
```

**Only `'unsafe-inline'` for styles** - Good balance of security and compatibility

**Compatible with:**
- Modern web applications
- Applications using external scripts
- Applications with inline CSS (common pattern)

**NOT compatible with:**
- Applications with inline JavaScript in HTML
- Applications using eval() or Function()

### 3. `secure-headers-relaxed` - Legacy Support
**Use for:** Grafana, Homepage, legacy applications

**CSP Configuration:**
```yaml
script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net;
style-src 'self' 'unsafe-inline' https://fonts.googleapis.com;
```

**⚠️ WARNING:** Includes `'unsafe-inline'` and `'unsafe-eval'`

**Compatible with:**
- Grafana (dashboard rendering uses eval)
- Homepage (inline widget scripts)
- Legacy admin panels
- Applications that cannot be refactored

**Security Trade-off:** Reduced XSS protection

---

## Middleware Chain Selection

### Available Chains

#### Strict CSP Chains
```yaml
# For OAuth-protected services with strict CSP
- chain-oauth-strict

# For public services with strict CSP
- chain-public-strict

# For APIs with strict CSP
- chain-api-strict
```

#### Default CSP Chains (Current)
```yaml
# OAuth-protected with balanced CSP
- chain-oauth

# Public with balanced CSP
- chain-public

# API with balanced CSP
- chain-api
```

#### Relaxed CSP Chains
```yaml
# OAuth-protected with relaxed CSP (for Grafana, Homepage)
- chain-oauth-relaxed

# Public with relaxed CSP (for legacy apps)
- chain-public-relaxed
```

---

## Migration Guide

### Step 1: Identify Your Service Type

**Modern Application (Recommended: `chain-oauth` or `chain-oauth-strict`)**
- Bundled JavaScript (Webpack, Vite, Parcel)
- No inline scripts in HTML
- No use of eval() or new Function()

**Legacy Application (Use: `chain-oauth-relaxed`)**
- Inline JavaScript in HTML
- Uses eval() or new Function()
- Third-party admin panels (Grafana, Portainer)

### Step 2: Update Service Configuration

#### Example: Switch Grafana to Relaxed CSP

**Current configuration (compose/grafana.yml):**
```yaml
labels:
  - "traefik.http.routers.grafana.middlewares=chain-oauth@file"
```

**Updated configuration:**
```yaml
labels:
  - "traefik.http.routers.grafana.middlewares=chain-oauth-relaxed@file"
```

#### Example: Use Strict CSP for API

**For a new API service:**
```yaml
labels:
  - "traefik.http.routers.myapi.middlewares=chain-api-strict@file"
```

### Step 3: Test for CSP Violations

1. **Open browser DevTools Console**
2. **Look for CSP violations:**
   ```
   Refused to execute inline script because it violates CSP directive...
   Refused to evaluate a string as JavaScript because 'unsafe-eval'...
   ```

3. **If violations occur:**
   - **Option A (Recommended):** Refactor code to comply with CSP
   - **Option B (Temporary):** Switch to relaxed CSP chain
   - **Option C (Advanced):** Implement nonce-based CSP (see below)

---

## Advanced: Nonce-Based CSP

For applications that need inline scripts but want to maintain security, implement nonce-based CSP.

### What is a Nonce?

A nonce is a random value that's:
1. Generated server-side for each request
2. Added to the CSP header
3. Added to each inline script tag

### Implementation Example

**Server-side (Node.js/Express):**
```javascript
const crypto = require('crypto');

app.use((req, res, next) => {
  // Generate random nonce
  const nonce = crypto.randomBytes(16).toString('base64');

  // Set CSP header with nonce
  res.setHeader('Content-Security-Policy',
    `script-src 'self' 'nonce-${nonce}' https://cdn.jsdelivr.net;`
  );

  // Make nonce available to templates
  res.locals.nonce = nonce;
  next();
});
```

**HTML Template:**
```html
<!-- Allowed: Has matching nonce -->
<script nonce="<%= nonce %>">
  console.log('This script is allowed');
</script>

<!-- Blocked: No nonce -->
<script>
  console.log('This script is blocked');
</script>
```

### Traefik Configuration for Nonce-Based CSP

You can override CSP at the service level:

```yaml
labels:
  - "traefik.http.middlewares.my-service-csp.headers.customResponseHeaders.Content-Security-Policy=default-src 'self'; script-src 'self' 'nonce-{NONCE_PLACEHOLDER}';"
  - "traefik.http.routers.my-service.middlewares=my-service-csp,chain-oauth@file"
```

**Note:** Your application server must replace `{NONCE_PLACEHOLDER}` with actual nonces.

---

## Service-Specific Recommendations

### Grafana
```yaml
# Use relaxed CSP - Grafana requires eval() for dashboard rendering
- "traefik.http.routers.grafana.middlewares=chain-oauth-relaxed@file"
```

### Homepage
```yaml
# Use relaxed CSP - Homepage uses inline scripts for widgets
- "traefik.http.routers.homepage.middlewares=chain-oauth-relaxed@file"
```

### Prometheus/Alertmanager
```yaml
# Can use default or strict CSP - mostly static content
- "traefik.http.routers.prometheus.middlewares=chain-oauth@file"
# Or for maximum security:
- "traefik.http.routers.prometheus.middlewares=chain-oauth-strict@file"
```

### Custom React/Vue/Angular Apps
```yaml
# Use strict CSP - modern frameworks bundle JS
- "traefik.http.routers.myapp.middlewares=chain-oauth-strict@file"
```

### REST APIs
```yaml
# Use strict CSP - APIs don't serve HTML
- "traefik.http.routers.api.middlewares=chain-api-strict@file"
```

---

## Testing Your CSP

### 1. Report-Only Mode (Testing)

Before enforcing CSP, test it in report-only mode:

```yaml
customResponseHeaders:
  Content-Security-Policy-Report-Only: "default-src 'self'; script-src 'self';"
```

Violations are logged to browser console without blocking content.

### 2. Browser DevTools

**Chrome/Edge:**
1. Open DevTools (F12)
2. Go to Console tab
3. Look for CSP violation warnings

**Firefox:**
1. Open DevTools (F12)
2. Go to Console tab
3. Filter by "CSP"

### 3. CSP Evaluator

Use Google's CSP Evaluator to check your policy:
https://csp-evaluator.withgoogle.com/

### 4. Observatory by Mozilla

Scan your site's security headers:
https://observatory.mozilla.org/

---

## Common CSP Violations and Solutions

### Violation: Inline Script Blocked
```
Refused to execute inline script because it violates CSP directive "script-src 'self'"
```

**Solutions:**
1. **Move script to external file** (Recommended)
   ```html
   <!-- Before -->
   <script>
     function myFunction() { }
   </script>

   <!-- After -->
   <script src="/js/myFunction.js"></script>
   ```

2. **Use event listeners instead of inline handlers**
   ```html
   <!-- Before -->
   <button onclick="myFunction()">Click</button>

   <!-- After -->
   <button id="myButton">Click</button>
   <script src="/js/handler.js"></script>
   ```

3. **Implement nonce-based CSP** (See Advanced section)

4. **Use relaxed CSP temporarily** (Not recommended long-term)

### Violation: eval() Blocked
```
Refused to evaluate a string as JavaScript because 'unsafe-eval' is not an allowed source
```

**Solutions:**
1. **Replace eval() with safer alternatives**
   ```javascript
   // Before (Unsafe)
   const result = eval(userInput);

   // After (Safe)
   const result = JSON.parse(userInput);
   ```

2. **Use Function constructor alternatives**
   ```javascript
   // Before (Unsafe)
   const fn = new Function('a', 'b', 'return a + b');

   // After (Safe)
   const fn = (a, b) => a + b;
   ```

3. **For templating, use safer libraries**
   - Handlebars (with CSP support)
   - Mustache
   - Lit-html

### Violation: External Script Blocked
```
Refused to load the script 'https://example.com/script.js' because it violates CSP directive
```

**Solution:** Add the domain to allowlist

**Update middleware:**
```yaml
contentSecurityPolicy: |
  script-src 'self' https://cdn.jsdelivr.net https://example.com;
```

---

## CSP Directives Reference

### Core Directives

| Directive | Purpose | Recommended Value |
|-----------|---------|-------------------|
| `default-src` | Fallback for all directives | `'self'` |
| `script-src` | JavaScript sources | `'self' https://cdn.jsdelivr.net` |
| `style-src` | CSS sources | `'self' 'unsafe-inline'` |
| `img-src` | Image sources | `'self' data: blob: https:` |
| `font-src` | Font sources | `'self' data: https://fonts.gstatic.com` |
| `connect-src` | AJAX, WebSocket sources | `'self' wss: https:` |
| `frame-src` | iframe sources | `'self'` |
| `object-src` | Plugin sources | `'none'` |

### Security Directives

| Directive | Purpose | Recommended Value |
|-----------|---------|-------------------|
| `frame-ancestors` | Who can embed this page | `'self'` |
| `base-uri` | Restrict <base> tag | `'self'` |
| `form-action` | Form submission targets | `'self'` |
| `upgrade-insecure-requests` | Upgrade HTTP to HTTPS | (no value) |
| `block-all-mixed-content` | Block HTTP on HTTPS page | (no value) |

### Source Values

| Value | Meaning |
|-------|---------|
| `'self'` | Same origin (domain + port + protocol) |
| `'none'` | Block all sources |
| `'unsafe-inline'` | ⚠️ Allow inline scripts/styles |
| `'unsafe-eval'` | ⚠️ Allow eval() and Function() |
| `https:` | Any HTTPS URL |
| `data:` | data: URIs |
| `blob:` | blob: URIs |
| `'nonce-ABC123'` | Allow with matching nonce |
| `'sha256-ABC123'` | Allow with matching hash |

---

## Monitoring CSP Violations

### Setup CSP Reporting

Add reporting endpoint to CSP:

```yaml
contentSecurityPolicy: |
  default-src 'self';
  script-src 'self' https://cdn.jsdelivr.net;
  report-uri /csp-report;
  report-to csp-endpoint;
```

### Create Reporting Endpoint

**Example with Express.js:**
```javascript
app.post('/csp-report', express.json({ type: 'application/csp-report' }), (req, res) => {
  console.log('CSP Violation:', req.body);
  // Log to monitoring system (Prometheus, Grafana)
  res.status(204).end();
});
```

### Integrate with Monitoring

**Prometheus Counter:**
```javascript
const cspViolations = new prometheus.Counter({
  name: 'csp_violations_total',
  help: 'Total CSP violations',
  labelNames: ['directive', 'blocked_uri']
});

app.post('/csp-report', (req, res) => {
  const violation = req.body['csp-report'];
  cspViolations.inc({
    directive: violation['violated-directive'],
    blocked_uri: violation['blocked-uri']
  });
  res.status(204).end();
});
```

---

## Security Best Practices

### 1. Start Strict, Relax if Needed
Always start with `secure-headers-strict` and only relax if necessary.

### 2. Never Use `'unsafe-inline'` for Scripts
This defeats the primary purpose of CSP - XSS protection.

### 3. Avoid `'unsafe-eval'`
Most use cases for eval() can be replaced with safer alternatives.

### 4. Use Subresource Integrity (SRI)
For external scripts, use SRI hashes:
```html
<script
  src="https://cdn.jsdelivr.net/npm/library@1.0.0/dist/lib.min.js"
  integrity="sha384-ABC123..."
  crossorigin="anonymous">
</script>
```

### 5. Keep Allowlists Minimal
Only allow trusted CDNs and domains you control.

### 6. Test Thoroughly
Always test CSP changes in staging before production.

### 7. Monitor Violations
Set up CSP reporting to catch issues early.

### 8. Document Exceptions
If you must use relaxed CSP, document why in your service config.

---

## Troubleshooting

### Service Not Loading After CSP Update

**Symptoms:**
- Blank page
- JavaScript not executing
- Console errors about CSP violations

**Diagnosis:**
1. Open browser DevTools Console
2. Look for CSP violation messages
3. Note which resources are blocked

**Resolution:**
```yaml
# Temporary: Switch to relaxed CSP
- "traefik.http.routers.myservice.middlewares=chain-oauth-relaxed@file"

# Then: Refactor application to comply with strict CSP
# Finally: Switch back to strict CSP
- "traefik.http.routers.myservice.middlewares=chain-oauth-strict@file"
```

### Inline Styles Not Working

**Solution:** `'unsafe-inline'` is allowed for styles in default and relaxed profiles.

If using strict profile, move styles to external CSS:
```html
<!-- Before -->
<div style="color: red;">Text</div>

<!-- After -->
<div class="red-text">Text</div>
<!-- In external CSS file -->
```

### Third-Party Widgets Blocked

**Example:** Google Analytics, social media widgets

**Solution:** Add widget domains to CSP:
```yaml
script-src 'self' https://www.google-analytics.com https://www.googletagmanager.com;
```

### WebSocket Connections Blocked

**Solution:** Allow WebSocket in `connect-src`:
```yaml
connect-src 'self' wss: https:;
```

---

## Migration Timeline

### Phase 1: Assessment (Week 1)
- [ ] Review all services using secure-headers middleware
- [ ] Test each service with default CSP (browser console)
- [ ] Document which services have CSP violations

### Phase 2: Categorization (Week 1)
- [ ] Categorize services as: Strict Compatible, Default Compatible, Needs Relaxed
- [ ] Create migration plan for each service

### Phase 3: Implementation (Week 2-3)
- [ ] Update services to use appropriate CSP level
- [ ] Refactor services where possible to comply with stricter CSP
- [ ] Test all services thoroughly

### Phase 4: Hardening (Week 4+)
- [ ] Migrate relaxed CSP services to nonce-based CSP
- [ ] Replace eval() usage with safer alternatives
- [ ] Move inline scripts to external files
- [ ] Gradually tighten CSP policies

---

## Resources

### Tools
- **CSP Evaluator:** https://csp-evaluator.withgoogle.com/
- **Mozilla Observatory:** https://observatory.mozilla.org/
- **Security Headers:** https://securityheaders.com/

### Documentation
- **MDN CSP Reference:** https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
- **W3C CSP Spec:** https://www.w3.org/TR/CSP/
- **OWASP CSP Guide:** https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html

### Browser Support
- **Can I Use CSP:** https://caniuse.com/contentsecuritypolicy2

---

## Summary

**What We Fixed:**
- ✅ Removed `'unsafe-inline'` from script-src in default profile
- ✅ Removed `'unsafe-eval'` from script-src in default profile
- ✅ Created three CSP security levels (strict, default, relaxed)
- ✅ Created middleware chains for each security level
- ✅ Maintained backward compatibility with aliases

**Security Impact:**
- **High**: Significantly reduces XSS attack surface
- **Medium**: Prevents code injection via eval()
- **Low**: Still allows inline styles (common pattern, lower risk)

**Compatibility:**
- Most services work with default profile (balanced)
- Legacy services can use relaxed profile
- Modern services should use strict profile

**Action Required:**
1. Test services after updating Traefik configuration
2. Check browser console for CSP violations
3. Update service labels to use appropriate CSP level
4. Plan migration from relaxed to stricter CSP over time

---

**Last Updated:** 2025-10-16
**Jacker Version:** 3.x
**Security Level:** High
