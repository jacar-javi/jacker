---
name: Bug report
about: Report an issue with Jacker Docker stack
title: '[BUG] '
labels: 'bug'
assignees: ''

---

## Bug Description
<!-- A clear and concise description of the bug -->

## Environment Information

**Installation Method:**
- [ ] Fresh install via `./jacker init`
- [ ] Upgraded from previous version
- [ ] Manual setup

**Host System:**
- OS: [e.g., Ubuntu 22.04, Debian 12]
- Docker version: [run `docker --version`]
- Docker Compose version: [run `docker compose version`]
- Jacker version: [run `./jacker version`]

**Configuration:**
- Domain configured: [yes/no]
- OAuth configured: [Google/Authentik/None]
- Services affected: [e.g., Traefik, Grafana, Loki]

## To Reproduce

Steps to reproduce the behavior:
1. Run command '...'
2. Access service at '...'
3. Observe error '...'

## Expected Behavior
<!-- What you expected to happen -->

## Actual Behavior
<!-- What actually happened -->

## Logs and Error Messages

<details>
<summary>Docker Compose Logs</summary>

```
# Paste output of: ./jacker logs <affected-service>
```
</details>

<details>
<summary>Container Status</summary>

```
# Paste output of: ./jacker status
```
</details>

<details>
<summary>Configuration Check</summary>

```
# Paste output of: ./jacker config validate
```
</details>

<details>
<summary>Health Check</summary>

```
# Paste output of: ./jacker health
```
</details>

## Additional Context

**Have you made any modifications to:**
- [ ] docker-compose.yml
- [ ] Any compose/*.yml files
- [ ] .env file (beyond setup values)
- [ ] Traefik rules
- [ ] Other configuration files

**Network Setup:**
- [ ] Behind NAT
- [ ] Using reverse proxy
- [ ] Firewall rules configured
- [ ] Ports 80/443 accessible

## Possible Solution
<!-- If you have suggestions on how to fix the bug -->

## Screenshots
<!-- If applicable, add screenshots to help explain your problem -->