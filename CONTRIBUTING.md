# Contributing to Jacker

Thank you for your interest in contributing to Jacker! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and collaborative environment for all contributors.

## How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. **Search existing issues** to avoid duplicates
2. **Open a new issue** with a clear title and description
3. **Include relevant information**:
   - Jacker version (run `./jacker version`)
   - Operating system and version
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Error messages and logs
   - Screenshots if applicable

### Suggesting Features

Feature requests are welcome! Please:

1. Check if the feature has already been requested
2. Clearly describe the use case and benefits
3. Consider implementation complexity
4. Be open to discussion and feedback

### Pull Requests

We actively welcome pull requests! Follow these steps:

#### 1. Fork and Clone

```bash
# Fork the repository on GitHub
git clone https://github.com/YOUR_USERNAME/jacker.git
cd jacker
```

#### 2. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

#### 3. Make Your Changes

- Follow the existing code style and conventions
- Write clear, descriptive commit messages
- Test your changes thoroughly
- Update documentation as needed

#### 4. Test Your Changes

```bash
# Run ShellCheck linting on the jacker CLI
shellcheck jacker assets/lib/*.sh

# Test installation (if applicable)
./jacker init

# Run health checks
./jacker health

# Test specific functionality
./jacker status
./jacker logs
```

#### 5. Commit Guidelines

Use conventional commit messages:

```
feat: add support for custom middleware chains
fix: resolve Loki permission issues
docs: update OAuth configuration guide
refactor: simplify backup script logic
test: add integration tests for stack manager
chore: update dependencies
```

**Format:**
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test additions or modifications
- `chore:` - Maintenance tasks
- `perf:` - Performance improvements
- `style:` - Code style changes (formatting, etc.)

#### 6. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Then create a pull request on GitHub with:

- Clear title describing the change
- Detailed description of what and why
- Reference to related issues (e.g., "Fixes #123")
- Screenshots/examples if applicable

## Development Guidelines

### Unified Jacker CLI

The Jacker project uses a unified CLI (`jacker`) that consolidates all functionality. When contributing:

- All new features should be added to the main `jacker` script
- Use the library modules in `assets/lib/` for shared functionality
- Follow the existing command structure and patterns

### Library Modules

Jacker uses modular libraries in `assets/lib/`:

- `common.sh` - Core utility functions, logging, environment loading
- `setup.sh` - Installation and configuration
- `config.sh` - Configuration management
- `security.sh` - Security operations
- `monitoring.sh` - Health checks and monitoring
- `maintenance.sh` - Backup, restore, updates
- `fixes.sh` - Problem resolution functions

Example of adding a new command:

```bash
# In the main jacker script
case "${1:-}" in
    your-command)
        shift
        source "$SCRIPT_DIR/assets/lib/your-module.sh"
        your_function "$@"
        ;;
esac
```

### Shell Scripts

All shell scripts must follow production-ready standards:

**Required Standards:**
- Use `#!/usr/bin/env bash` shebang
- Include error handling: `set -euo pipefail` (main scripts only, not sourced libraries)
- **Quote all variable expansions**: `"$var"` not `$var`
- Use array-safe patterns for loops (avoid word-splitting)
- Add ShellCheck directives when needed
- Add comments for complex logic
- Follow existing patterns

**Example of Proper Variable Quoting:**
```bash
# Good - properly quoted
echo "Value: $variable"
docker exec "$container_name" echo "test"
if [[ "$count" -gt 0 ]]; then

# Bad - unquoted (causes word-splitting)
echo "Value: $variable"
docker exec $container_name echo "test"
if [[ $count -gt 0 ]]; then
```

**Array-Safe Loop Pattern:**
```bash
# Good - array-safe iteration
mapfile -t services < <(docker ps --format '{{.Names}}')
for service in "${services[@]}"; do
    echo "Processing: $service"
done

# Bad - word-splitting vulnerable
for service in $(docker ps --format '{{.Names}}'); do
    echo "Processing: $service"
done
```

Example library module:

```bash
#!/usr/bin/env bash
#
# lib/your-module.sh - Brief description
#

set -euo pipefail

# Function documentation
your_function() {
    local param="${1:-}"

    # Your code here
    info "Processing: $param"

    # Use common functions for output
    success "Operation completed"
}
```

### Docker Compose Services

- Place service definitions in `compose/` directory
- Include them in `docker-compose.yml` with `include:` directive
- Use environment variables from `.env`
- Add Traefik labels for routing
- Include health checks
- Document the service in `compose/README.md`

**Network Configuration:**
- Assign services to appropriate networks (see `docs/architecture/OVERVIEW.md`)
- Use existing networks when possible:
  - `traefik_proxy` - Web-accessible services
  - `database` - Database services
  - `monitoring` - Monitoring stack
  - `cache` - Redis and cache services
  - `socket_proxy` - Docker API access
  - `backup` - Backup utilities
  - `default` - General services
- Add IPAM configuration if creating new networks (192.168.76-254.x available)

**Example Service Definition:**
```yaml
services:
  myservice:
    image: myimage:latest
    networks:
      - traefik_proxy
      - monitoring
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myservice.rule=Host(`myservice.${PUBLIC_FQDN}`)"
```

### Documentation

- Update README.md for significant changes
- Add service documentation to `compose/README.md`
- Update CHANGELOG.md for all user-facing changes
- Add architecture notes to `docs/architecture/` if needed
- Keep documentation clear, concise, and up-to-date
- Cross-reference related documentation

### Testing

Before submitting a pull request:

1. **Run Pre-Deployment Validation**:
   ```bash
   ./validate.sh
   ```
   All 12 checks must pass before deployment.

2. **Lint the jacker CLI and libraries**:
   ```bash
   shellcheck jacker
   shellcheck assets/lib/*.sh
   ```
   Must have zero critical warnings.

3. **Test installation**: Fresh install on clean system
   ```bash
   # Ensure DNS configured first
   ./jacker init
   ```

4. **Check health**: Ensure all services are healthy
   ```bash
   ./jacker health
   ```

5. **Test affected commands**:
   ```bash
   ./jacker status
   ./jacker config validate
   ./jacker logs
   ```

6. **Verify functionality**: Manual testing of affected features

7. **Test SSL certificates** (if init script modified):
   ```bash
   # Verify certificates obtained
   ls -lh data/traefik/acme/acme.json
   # Should be > 100 bytes
   ```

## Project Structure

```
jacker/
├── jacker              # Unified CLI (main entry point)
├── validate.sh         # Pre-deployment validation (12 checks)
├── assets/             # Support files
│   ├── lib/           # Library modules
│   │   ├── common.sh      # Core utilities
│   │   ├── setup.sh       # Installation functions
│   │   ├── config.sh      # Configuration management
│   │   ├── security.sh    # Security operations
│   │   ├── monitoring.sh  # Health and monitoring
│   │   ├── maintenance.sh # Backup/restore/updates
│   │   └── fixes.sh       # Problem resolution
│   └── templates/     # Configuration templates
├── compose/           # Modular service definitions (26 services)
├── config/            # Service configurations
├── data/              # Persistent data (gitignored)
├── secrets/           # Docker secrets (gitignored)
├── docs/              # Documentation
│   ├── architecture/  # System architecture docs
│   ├── guides/        # How-to guides
│   └── archive/       # Historical phase reports
├── .github/           # GitHub workflows and configs
├── docker-compose.yml # Main compose file with includes
├── CHANGELOG.md       # Version history
├── CONTRIBUTING.md    # This file
└── README.md          # User documentation
```

## Getting Help

- **Documentation**: https://jacker.jacar.es
- **Discussions**: GitHub Discussions for questions
- **Issues**: GitHub Issues for bugs and features
- **Email**: support@jacker.jacar.es

## Review Process

1. **Automated Checks**: CI workflows must pass
   - ShellCheck linting
   - Docker Compose validation
   - Security scanning
   - Integration tests
   - Documentation checks

2. **Code Review**: Maintainers will review your PR
   - Code quality and style
   - Test coverage
   - Documentation completeness
   - Security considerations

3. **Merge**: After approval and passing checks

## Recognition

Contributors will be:
- Acknowledged in release notes
- Listed in project credits
- Invited to join the contributors team

## License

By contributing to Jacker, you agree that your contributions will be licensed under the [MIT License](LICENSE).

## Questions?

Don't hesitate to ask! Open a discussion or reach out via:
- GitHub Discussions
- GitHub Issues
- Email: support@jacker.jacar.es

Thank you for contributing to Jacker! 🎉
