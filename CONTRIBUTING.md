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
   - Jacker version
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
# Run ShellCheck linting
make lint

# Run test suite
make test

# Test installation (if applicable)
make install

# Check health
make health
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

### Shell Scripts

- Follow existing patterns in `assets/` directory
- Use `#!/usr/bin/env bash` shebang
- Add ShellCheck directives when needed
- Source `common.sh` for shared functions
- Include error handling (`set -euo pipefail`)
- Add comments for complex logic

Example:

```bash
#!/usr/bin/env bash
#
# script-name.sh - Brief description
#

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assets/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Your code here
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
- Update CLAUDE.md for codebase changes that affect development
- Keep documentation clear, concise, and up-to-date

### Testing

Before submitting a pull request:

1. **Lint all scripts**: `make lint`
2. **Run tests**: `make test`
3. **Test installation**: Fresh install on clean system (if applicable)
4. **Check health**: `make health` passes all checks
5. **Verify functionality**: Manual testing of affected features

## Project Structure

```
jacker/
├── assets/              # Scripts and utilities
│   ├── lib/            # Shared libraries
│   ├── setup.sh        # Main installation script
│   ├── backup.sh       # Backup functionality
│   └── *.sh            # Maintenance scripts
├── compose/            # Modular service definitions
├── data/               # Persistent data (gitignored)
├── .github/            # GitHub workflows and configs
├── docker-compose.yml  # Main compose file
├── Makefile           # Management commands
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
