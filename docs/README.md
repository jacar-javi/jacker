# Jacker Documentation

This directory contains comprehensive documentation for the Jacker platform.

## Directory Structure

### `/architecture/`

System architecture and design documentation:

- **[OVERVIEW.md](architecture/OVERVIEW.md)** - Complete platform architecture
  - System architecture diagrams
  - Network topology (7 networks with IPAM)
  - Service dependency graphs
  - Monitoring coverage matrix
  - Security layer descriptions
  - Data flow diagrams
  - Deployment architecture
  - Performance characteristics

### `/guides/`

Operational guides and how-to documentation:

- **[SSL_CONFIGURATION.md](guides/SSL_CONFIGURATION.md)** - SSL certificate setup and troubleshooting
- **[VPS_COMMANDS.md](guides/VPS_COMMANDS.md)** - Common VPS management commands

### `/archive/`

Historical documentation and phase reports:

**Init Script Improvements:**
- **[INIT_ANALYSIS.md](archive/INIT_ANALYSIS.md)** - Initial analysis of init script issues
- **[INIT_IMPROVEMENTS.md](archive/INIT_IMPROVEMENTS.md)** - Init script enhancement summary
- **[INIT_FIX_SUMMARY.md](archive/INIT_FIX_SUMMARY.md)** - Complete fix summary for init script

**Phase Reports:**
- **[PHASE2_DEPLOYMENT_GUIDE.md](archive/PHASE2_DEPLOYMENT_GUIDE.md)** - Monitoring expansion (40% → 96%)
- **[PHASE3_CODE_QUALITY.md](archive/PHASE3_CODE_QUALITY.md)** - Code quality improvements (B+ → A++)

---

## Quick Links

### Getting Started
- [Main README](../README.md) - Project overview and quick start
- [Installation Guide](../README.md#quick-start) - Setup instructions
- [validate.sh](../validate.sh) - Pre-deployment validation script

### Configuration
- [.env.defaults](../env.defaults) - Default environment variables
- [Configuration Files](../config/README.md) - Service configuration documentation

### Operations
- [CHANGELOG.md](../CHANGELOG.md) - Version history and changes
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Contribution guidelines
- [Services Documentation](../compose/README.md) - All 26 services documented

### Architecture & Design
- [Architecture Overview](architecture/OVERVIEW.md) - Complete system architecture
- [Network Topology](architecture/OVERVIEW.md#network-topology) - 7 networks with IPAM
- [Security Layers](architecture/OVERVIEW.md#security-layers) - Defense-in-depth security
- [Monitoring Coverage](architecture/OVERVIEW.md#monitoring-coverage-map) - 96% coverage matrix

---

## Documentation Standards

### File Naming
- Use descriptive names: `FEATURE_DESCRIPTION.md`
- Use uppercase for top-level docs: `README.md`, `CHANGELOG.md`
- Use sentence case for guides: `SSL_CONFIGURATION.md`

### Document Structure
- Include last updated date
- Use clear section headers
- Include table of contents for long documents
- Add cross-references to related docs
- Provide code examples where applicable

### Markdown Format
- Use fenced code blocks with language hints
- Include diagrams using ASCII art or Mermaid
- Use tables for structured data
- Add badges for status indicators

---

## Project Phases

The Jacker platform has completed 3 major improvement phases:

### Phase 1: Security Hardening (INIT Improvements)
**Status:** ✅ Complete (2025-10-14)

- Fixed 3 CRITICAL security vulnerabilities
- Added DNS validation before SSL certificate requests
- Enhanced init script with SSL certificate waiting
- Improved user feedback with color-coded status
- See: [INIT_FIX_SUMMARY.md](archive/INIT_FIX_SUMMARY.md)

### Phase 2: Monitoring Expansion
**Status:** ✅ Complete (2025-10-14)

- Increased monitoring coverage: 40% → 96%
- Added Blackbox Exporter for endpoint monitoring
- Enabled cAdvisor for per-container metrics
- Expanded service coverage to 25 of 26 services
- See: [PHASE2_DEPLOYMENT_GUIDE.md](archive/PHASE2_DEPLOYMENT_GUIDE.md)

### Phase 3: Code Quality Improvements
**Status:** ✅ Complete (2025-10-14)

- Hardened 7,960 lines of shell scripts
- Added network IPAM configurations (4 networks)
- Created pre-deployment validation script
- Improved code quality: B+ → A++
- See: [PHASE3_CODE_QUALITY.md](archive/PHASE3_CODE_QUALITY.md)

---

## Contributing to Documentation

When contributing documentation:

1. **Check Existing Docs**: Search before creating new files
2. **Follow Standards**: Use the format and structure above
3. **Update Cross-References**: Link related documents
4. **Test Code Examples**: Ensure all examples work
5. **Update This README**: Add new docs to appropriate sections

See [CONTRIBUTING.md](../CONTRIBUTING.md) for full guidelines.

---

## External Documentation

- **Official Website**: [jacker.jacar.es](https://jacker.jacar.es)
- **GitHub Repository**: [github.com/jacar-javi/jacker](https://github.com/jacar-javi/jacker)
- **Issue Tracker**: [GitHub Issues](https://github.com/jacar-javi/jacker/issues)
- **Discussions**: [GitHub Discussions](https://github.com/jacar-javi/jacker/discussions)

---

**Last Updated:** 2025-10-14
**Documentation Version:** 1.0.0
