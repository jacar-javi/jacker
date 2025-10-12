---
name: Security vulnerability
about: Report a security issue (for non-critical issues only; critical issues should be reported privately)
title: '[SECURITY] '
labels: 'security'
assignees: ''

---

<!--
⚠️ IMPORTANT: If this is a CRITICAL security vulnerability that could be exploited,
DO NOT create a public issue. Instead, please report it privately via:
- Email to the maintainers
- GitHub Security Advisories (if enabled)
- Other private communication channels

Only use this template for:
- Non-critical security improvements
- Security configuration issues
- Best practice recommendations
-->

## Security Issue Type
- [ ] Configuration weakness
- [ ] Outdated dependency
- [ ] Permission issue
- [ ] Authentication/Authorization issue
- [ ] Network security
- [ ] Other: [specify]

## Affected Components
- [ ] Traefik configuration
- [ ] OAuth/Authentication setup
- [ ] CrowdSec rules
- [ ] Docker socket exposure
- [ ] SSL/TLS configuration
- [ ] Service isolation
- [ ] Other: [specify]

## Description
<!-- Describe the security issue -->

## Risk Assessment

### Severity
- [ ] Low - Minor issue with minimal impact
- [ ] Medium - Could potentially be exploited under specific conditions
- [ ] High - Should be fixed soon (remember: critical issues should be reported privately)

### Impact
<!-- What could happen if this issue is exploited? -->

### Likelihood
- [ ] Low - Requires significant effort or specific conditions
- [ ] Medium - Could be exploited with moderate effort
- [ ] High - Easy to exploit

## Steps to Reproduce
<!-- Only if safe to disclose publicly -->
1.
2.
3.

## Recommended Fix
<!-- Your suggestions for fixing this issue -->

## Workaround
<!-- Any temporary measures to mitigate the issue -->

## References
<!-- Links to CVEs, security advisories, or documentation -->

## Environment
- Jacker version: [commit hash]
- Affected service versions: [e.g., Traefik v3.0.0]
- Configuration: [relevant settings]