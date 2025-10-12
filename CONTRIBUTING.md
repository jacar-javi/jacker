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

When creating new library modules:

- Use `#!/usr/bin/env bash` shebang
- Add ShellCheck directives when needed
- Include error handling (`set -euo pipefail`)
- Add comments for complex logic
- Follow existing patterns

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

### Documentation

- Update README.md for significant changes
- Add service documentation to `compose/README.md`
- Keep documentation clear, concise, and up-to-date

### Testing

Before submitting a pull request:

1. **Lint the jacker CLI and libraries**:
   ```bash
   shellcheck jacker
   shellcheck assets/lib/*.sh
   ```

2. **Test installation**: Fresh install on clean system
   ```bash
   ./jacker init
   ```

3. **Check health**: Ensure all services are healthy
   ```bash
   ./jacker health
   ```

4. **Test affected commands**:
   ```bash
   ./jacker status
   ./jacker config validate
   ./jacker logs
   ```

5. **Verify functionality**: Manual testing of affected features

## Project Structure

```
jacker/
├── jacker              # Unified CLI (main entry point)
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
├── compose/           # Modular service definitions
├── config/            # Service configurations
├── data/              # Persistent data (gitignored)
├── secrets/           # Docker secrets (gitignored)
├── .github/           # GitHub workflows and configs
├── docker-compose.yml # Main compose file with includes
├── Makefile          # Backward compatibility wrapper
└── README.md         # User documentation
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
