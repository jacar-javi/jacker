# Jacker Base Stack Template

This is the enhanced base template for creating new Jacker stacks. It includes all the necessary files and structure to build a production-ready, well-documented stack.

## 📋 Template Structure

```
base_stack/
├── README.md                       # Stack documentation template
├── Makefile                        # Management commands (40+ commands)
├── docker-compose.yml              # Main compose file
├── .env.sample                     # Environment configuration template
├── .gitignore                      # Git ignore rules
├── stack.yml                       # Stack metadata for Jacker
├── compose/                        # Service definitions
│   ├── service1.yml               # Example service template
│   └── .gitkeep
├── data/                           # Persistent data (gitignored)
│   └── .gitkeep
├── systemd/                        # Systemd service template
│   └── stack.service.template
├── assets/                         # Scripts and assets
│   └── .gitkeep
├── scripts/                        # Management scripts
│   └── .gitkeep
└── secrets/                        # Secrets (gitignored)
    └── .gitkeep
```

## 🚀 Creating a New Stack

### Step 1: Copy Template

```bash
# Copy template to new stack location
cp -r templates/base_stack jacker-stacks/{category}/{stack-name}
cd jacker-stacks/{category}/{stack-name}
```

### Step 2: Replace Placeholders

Replace all placeholders in the template files:

#### Placeholders to Replace

- `{STACK_NAME}` - Stack display name (e.g., "WordPress", "Nextcloud")
- `{stack-name}` - Stack identifier (lowercase with hyphens, e.g., "wordpress", "nextcloud")
- `{STACK_DESCRIPTION}` - Brief description of the stack
- `{category}` - Stack category (cms, tools, security, etc.)
- `{service-name}` - Main service name
- `{SERVICE_NAME}` - Service name in caps
- `{image:tag}` - Docker image with tag
- `{DOCS_URL}` - Documentation URL
- `{STACK_URL}` - Official website URL
- `{version}` - Stack version
- `{license}` - License type

#### Files to Update

1. **README.md** - Complete documentation
   - Replace all placeholders with actual values
   - Fill in feature lists
   - Add specific configuration details
   - Update troubleshooting section

2. **Makefile** - Management commands
   - Replace `{STACK_NAME}` and `{stack-name}`
   - Replace `{SERVICE_NAME}` with actual service name
   - Update database commands if applicable
   - Remove unused sections

3. **stack.yml** - Metadata
   - Update all metadata fields
   - Configure dependencies
   - Define services
   - Set environment variables
   - Configure monitoring and security

4. **docker-compose.yml** - Main compose file
   - Update service includes
   - Configure networks and volumes
   - Add any secrets

5. **.env.sample** - Environment template
   - Add stack-specific variables
   - Update service configuration
   - Configure database if needed
   - Remove unused sections

6. **compose/service1.yml** - Service definitions
   - Rename to actual service name
   - Configure image and environment
   - Set up volumes and networks
   - Configure Traefik labels
   - Add healthcheck if supported

7. **systemd/stack.service.template** - Systemd service
   - Update stack name and paths
   - Configure service description

### Step 3: Create Service Compose Files

Create individual compose files for each service in the `compose/` directory:

```bash
# Create service compose file
cp compose/service1.yml compose/{actual-service-name}.yml
# Edit the file to configure the service
```

### Step 4: Test the Stack

```bash
# Copy environment file
cp .env.sample .env

# Edit environment variables
nano .env

# Validate configuration
docker compose config

# Start stack
make up

# Check status
make status

# View logs
make logs
```

### Step 5: Document Everything

Ensure the README.md includes:
- ✅ Comprehensive overview
- ✅ Feature list
- ✅ Installation instructions
- ✅ Configuration guide
- ✅ Management commands
- ✅ Troubleshooting section
- ✅ Integration examples

## 📝 Template Features

### README.md Template Includes:

- **Badges** - License, version, compatibility badges
- **Overview** - Comprehensive introduction
- **Features** - Categorized feature lists
- **Quick Start** - Step-by-step installation
- **Configuration** - Environment variables and settings
- **Management** - Docker Compose and Makefile commands
- **Monitoring** - Health checks, logs, and metrics
- **Troubleshooting** - Common issues and solutions
- **Integration** - Homepage, Prometheus examples
- **Directory Structure** - Clear file organization
- **Documentation Links** - Official and Jacker docs
- **Support** - Help resources
- **License** - License information
- **Changelog** - Version history
- **Advanced Configuration** - OAuth, resources, networking
- **Performance** - Resource usage and optimization
- **Security** - Security features and best practices
- **Quick Commands** - Command reference
- **Use Cases** - Practical examples
- **Tips & Tricks** - Helpful hints

### Makefile Includes 40+ Commands:

#### Docker Compose
- `up`, `down`, `restart`, `logs`, `status`, `pull`, `update`

#### Health & Monitoring
- `health`, `stats`, `top`, `inspect`

#### Database (if applicable)
- `db-shell`, `db-backup`, `db-restore`

#### Backup & Restore
- `backup`, `backup-list`, `restore`

#### Maintenance
- `clean`, `clean-all`, `prune`

#### Systemd Service
- `systemd-create`, `systemd-enable`, `systemd-disable`
- `systemd-start`, `systemd-stop`, `systemd-restart`
- `systemd-status`, `systemd-logs`, `systemd-remove`

#### Development
- `shell`, `bash`, `root-shell`
- `config`, `version`, `networks`, `volumes`

#### Logs & Debugging
- `logs-tail`, `logs-service`, `logs-error`, `logs-export`

#### Security
- `fix-permissions`, `scan`

#### Utilities
- `quick-start`, `env-check`, `info`

### stack.yml Metadata Includes:

- **Basic Info** - Name, version, category, description
- **Requirements** - Jacker, Docker versions
- **Dependencies** - Traefik, OAuth, CrowdSec
- **Services** - Service definitions with ports
- **Environment** - Required and optional variables
- **Systemd** - Service configuration
- **Health** - Healthcheck settings
- **Monitoring** - Prometheus, Grafana, Loki, Jaeger
- **Security** - OAuth, CrowdSec, rate limiting
- **Network** - External and internal networks
- **Volumes** - Persistent storage
- **Ports** - Exposed ports
- **Backup** - Backup configuration
- **Firewall** - UFW rules
- **Resources** - CPU and memory limits
- **Maintenance** - Auto-update settings
- **Notes** - Important information
- **Changelog** - Version history

### .env.sample Template Includes:

- **General Settings** - PUID, PGID, TZ
- **Domain Configuration** - FQDN, subdomain
- **Paths** - Data, config, secrets directories
- **Service Configuration** - Service-specific settings
- **Database** - Connection settings (if needed)
- **Redis/Cache** - Cache configuration (if needed)
- **SMTP/Email** - Email settings (if needed)
- **Authentication** - Admin credentials, API keys
- **Networking** - Docker networks (if custom)
- **Traefik** - Router, middleware, TLS settings
- **Security** - OAuth, CrowdSec, secrets
- **Backup** - Backup configuration
- **Logging & Monitoring** - Log level, metrics
- **Advanced Settings** - Feature flags, performance
- **Development** - Debug settings

## 🎯 Best Practices

### Documentation
1. **Be comprehensive** - Include all necessary information
2. **Use examples** - Provide real-world examples
3. **Keep it updated** - Update docs with code changes
4. **Structure well** - Use clear sections and headings

### Configuration
1. **Use environment variables** - Never hardcode values
2. **Provide defaults** - Sensible default values
3. **Document everything** - Explain each variable
4. **Security first** - Strong passwords, OAuth by default

### Code Organization
1. **Modular compose files** - One service per file
2. **Clear naming** - Descriptive service names
3. **Consistent structure** - Follow the template
4. **Version control** - Use git properly

### Testing
1. **Test installation** - Fresh installation testing
2. **Test updates** - Update process testing
3. **Test backups** - Backup and restore testing
4. **Test scaling** - Resource usage testing

## 📚 Examples

### Good Stack Examples

Check these existing stacks as references:
- **wordpress** - CMS with database
- **it-tools** - Simple single-service stack
- **nextcloud** - Multi-service collaboration platform
- **wireadguard** - Complex networking stack
- **jacker-pms** - Media server with multiple services

## 🔄 Template Version

**Version:** 2.0.0
**Date:** 2025-01-10
**Status:** Production Ready

### Template Changelog

#### Version 2.0.0 (2025-01-10)
- ✨ Enhanced README template (580+ lines)
- ✨ Comprehensive Makefile (40+ commands)
- ✨ Complete stack.yml metadata
- ✨ Enhanced .env.sample template
- ✨ Systemd service template
- ✨ Example service compose file
- ✨ .gitignore template
- ✅ Removed old shell scripts
- ✅ Added comprehensive documentation

#### Version 1.0.0 (2024-XX-XX)
- ✅ Initial base template
- ✅ Basic structure
- ✅ Shell scripts

---

## 📞 Support

For questions or issues with the template:
- **Documentation:** [Jacker Docs](https://jacker.jacar.es)
- **Issues:** [GitHub Issues](https://github.com/jacar-javi/jacker/issues)

---

**🚀 Happy Stack Building!**
